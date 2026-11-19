//+------------------------------------------------------------------+
//|                                  PositionManagementEngine.mqh    |
//| Phase 16: automated position management on top of CPositionManager|
//| - Per-ticket, per-lifecycle automation (hedging and netting)      |
//| - Automated Break Even (points / R-multiple, one-time per stage)  |
//| - Automated trailing (fixed / ATR / candle, activation, step)     |
//| - Multi-level partial close with server-confirmed execution       |
//| - Time-based exit                                                 |
//| - Magic + symbol filtering, no unrelated manual position control  |
//| Persistence decision (see Docs/TECHNICAL_DEBT.md TD-19):          |
//| - No parallel state file. Restart safety is reconstructed from    |
//|   live positions and broker deal history for the position id.     |
//| - When history is unavailable/ambiguous (e.g. netting INOUT),     |
//|   partial-close stages are treated as UNKNOWN and are not         |
//|   re-executed; BE/trailing remain available because they are      |
//|   monotonic and therefore duplicate-safe.                         |
//| - No login/server/broker/credential data is read or stored.       |
//+------------------------------------------------------------------+
#ifndef MM_POSITION_MANAGEMENT_ENGINE_MQH
#define MM_POSITION_MANAGEMENT_ENGINE_MQH

#include "../Core/PositionManager.mqh"
#include "../Core/Logger.mqh"
#include "../Utils/Common.mqh"

#define MM_PM_MAX_TRACK 64
#define MM_PM_MAX_LEVELS 3

enum ENUM_MM_BE_TRIGGER
{
   MM_BE_TRIGGER_OFF = 0,
   MM_BE_TRIGGER_POINTS,
   MM_BE_TRIGGER_R,
   MM_BE_TRIGGER_ANY
};

struct MM_PosMgmtConfig
{
   bool                 enabled;
   int                  magic;
   bool                 manageOnlyOwnMagic;
   bool                 symbolFilterEnabled;
   string               symbolList;

   bool                 beEnabled;
   ENUM_MM_BE_TRIGGER   beTrigger;
   double               beProfitPoints;
   double               beRMultiple;
   ENUM_BE_MODE         beMode;
   double               beExtraPoints;

   bool                 trailEnabled;
   ENUM_TRAILING_MODE   trailMode;
   double               trailValue;
   ENUM_TIMEFRAMES      trailTimeframe;
   double               trailActivationPoints;
   double               trailActivationR;
   double               trailUpdateStepPoints;

   bool                 partialEnabled;
   int                  partialLevels;
   double               partialPct[MM_PM_MAX_LEVELS];
   double               partialTriggerR[MM_PM_MAX_LEVELS];
   bool                 partialLastCloseRemainder;

   bool                 timeExitEnabled;
   int                  maxMinutes;

   void Reset()
   {
      enabled=false;
      magic=MM_MAGIC_DEFAULT;
      manageOnlyOwnMagic=true;
      symbolFilterEnabled=false;
      symbolList="";
      beEnabled=true;
      beTrigger=MM_BE_TRIGGER_R;
      beProfitPoints=0;
      beRMultiple=1.0;
      beMode=BE_AT_BREAKEVEN;
      beExtraPoints=0;
      trailEnabled=true;
      trailMode=TRAIL_FIXED;
      trailValue=20;
      trailTimeframe=PERIOD_H1;
      trailActivationPoints=0;
      trailActivationR=0;
      trailUpdateStepPoints=5;
      partialEnabled=false;
      partialLevels=0;
      for(int i=0;i<MM_PM_MAX_LEVELS;i++){ partialPct[i]=0; partialTriggerR[i]=0; }
      partialLastCloseRemainder=false;
      timeExitEnabled=false;
      maxMinutes=0;
   }
};

struct MM_PosMgmtTrack
{
   long     positionId;
   ulong    ticket;
   string   symbol;
   int      side;
   datetime openTime;
   double   baselineVolume;
   bool     historyKnown;
   int      levelMask;
   bool     beDone;
   double   riskDistance;
   int      pendingLevel;
   double   pendingTargetVolume;
   datetime pendingTime;
   bool     seen;
   void Reset()
   {
      positionId=0; ticket=0; symbol=""; side=-1; openTime=0;
      baselineVolume=0; historyKnown=false; levelMask=0; beDone=false;
      riskDistance=0; pendingLevel=-1; pendingTargetVolume=0; pendingTime=0; seen=false;
   }
};

class CPositionManagementEngine
{
private:
   CPositionManager m_pm;
   CTrade           m_trade;
   MM_PosMgmtConfig m_cfg;
   MM_PosMgmtTrack  m_tracks[MM_PM_MAX_TRACK];
   int              m_count;
   ulong            m_magic;

   double VolumeDigits(double step)
   {
      if(step<=0) return 2.0;
      int d=(int)MathCeil(-MathLog10(step));
      if(d<0) d=0;
      return (double)d;
   }

   double NormalizeToStep(double vol,double step)
   {
      if(step<=0) step=0.01;
      double v=MathRound(vol/step)*step;
      return NormalizeDouble(v,(int)VolumeDigits(step));
   }

   double FloorToStep(double vol,double step)
   {
      if(step<=0) step=0.01;
      double v=MathFloor(vol/step+1e-9)*step;
      return NormalizeDouble(v,(int)VolumeDigits(step));
   }

   bool IsEligibleInternal(long magic,string symbol)
   {
      if(m_cfg.manageOnlyOwnMagic && magic!=(long)m_cfg.magic) return false;
      if(!m_cfg.symbolFilterEnabled) return true;
      if(m_cfg.symbolList=="") return true;
      string symName=symbol;
      StringToUpper(symName);
      string want=symName;
      string listStr=m_cfg.symbolList;
      string parts[];
      int n=StringSplit(listStr,',',parts);
      for(int i=0;i<n;i++)
      {
         string p=parts[i];
         StringToUpper(p);
         if(p=="") continue;
         if(p=="*") return true;
         if(p==want) return true;
      }
      return false;
   }

   int FindTrack(long positionId)
   {
      for(int i=0;i<m_count;i++) if(m_tracks[i].positionId==positionId) return i;
      return -1;
   }

   int NewTrack()
   {
      for(int i=0;i<m_count;i++) if(m_tracks[i].positionId==0) return i;
      if(m_count<MM_PM_MAX_TRACK){ m_tracks[m_count].Reset(); return m_count++; }
      return -1;
   }

   void ReconstructFromHistory(MM_PosMgmtTrack &rec,double currentVolume)
   {
      rec.historyKnown=false;
      rec.baselineVolume=currentVolume;
      rec.levelMask=0;
      if(!HistorySelectByPosition(rec.positionId)) return;

      int total=HistoryDealsTotal();
      double inVol=0.0, outVol=0.0;
      bool sawIn=false, ambiguous=false;
      for(int i=0;i<total;i++)
      {
         ulong dt=HistoryDealGetTicket(i);
         if(dt==0) continue;
         ENUM_DEAL_TYPE dtype=(ENUM_DEAL_TYPE)HistoryDealGetInteger(dt,DEAL_TYPE);
         if(dtype!=DEAL_TYPE_BUY && dtype!=DEAL_TYPE_SELL) continue;
         ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(dt,DEAL_ENTRY);
         double dv=HistoryDealGetDouble(dt,DEAL_VOLUME);
         if(entry==DEAL_ENTRY_IN){ inVol+=dv; sawIn=true; }
         else if(entry==DEAL_ENTRY_OUT) outVol+=dv;
         else if(entry==DEAL_ENTRY_INOUT) ambiguous=true; // close+open in one deal: volume split unknown
      }

      double step=SymbolInfoDouble(rec.symbol,SYMBOL_VOLUME_STEP);
      if(step<=0) step=0.01;

      if(!sawIn || inVol<=0 || ambiguous || m_cfg.partialLevels<=0)
      {
         // Unknown/ambiguous initial risk or lifecycle: do not invent executed stages.
         rec.historyKnown=false;
         rec.baselineVolume=currentVolume;
         rec.levelMask=0;
         return;
      }

      rec.baselineVolume=inVol;
      rec.levelMask=DeriveLevelMask(inVol,outVol,m_cfg.partialPct,m_cfg.partialLevels,step);
      rec.historyKnown=true;
   }

   int EnsureTrack(ulong ticket,const string symbol,ENUM_POSITION_TYPE type,datetime openTime)
   {
      long id=(long)PositionGetInteger(POSITION_IDENTIFIER);
      double vol=PositionGetDouble(POSITION_VOLUME);
      int idx=FindTrack(id);
      if(idx>=0)
      {
         // Netting reversal may preserve identifier but flip side/time: new logical lifecycle.
         if(m_tracks[idx].side!=(int)type || m_tracks[idx].openTime!=openTime)
         {
            m_tracks[idx].Reset();
            m_tracks[idx].positionId=id;
            ReconstructFromHistory(m_tracks[idx],vol);
         }
         m_tracks[idx].ticket=ticket;
         m_tracks[idx].symbol=symbol;
         m_tracks[idx].side=(int)type;
         m_tracks[idx].openTime=openTime;
         if(m_tracks[idx].riskDistance<=0)
         {
            double open=PositionGetDouble(POSITION_PRICE_OPEN);
            double sl=PositionGetDouble(POSITION_SL);
            if(sl>0) m_tracks[idx].riskDistance=MathAbs(open-sl);
         }
         m_tracks[idx].seen=true;
         return idx;
      }

      idx=NewTrack();
      if(idx<0) return -1;
      m_tracks[idx].Reset();
      m_tracks[idx].positionId=id;
      m_tracks[idx].ticket=ticket;
      m_tracks[idx].symbol=symbol;
      m_tracks[idx].side=(int)type;
      m_tracks[idx].openTime=openTime;
      m_tracks[idx].seen=true;
      double open=PositionGetDouble(POSITION_PRICE_OPEN);
      double sl=PositionGetDouble(POSITION_SL);
      if(sl>0) m_tracks[idx].riskDistance=MathAbs(open-sl);
      ReconstructFromHistory(m_tracks[idx],vol);
      return idx;
   }

   bool IsProtectedByBE(const string symbol,ENUM_POSITION_TYPE type,double openPrice,double sl)
   {
      if(sl<=0) return false;
      double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
      if(point<=0) return false;
      double extraPts=(m_cfg.beMode==BE_PLUS_POINTS)?m_cfg.beExtraPoints:0.0;
      double target=(type==POSITION_TYPE_BUY)?openPrice+extraPts*point:openPrice-extraPts*point;
      if(type==POSITION_TYPE_BUY) return (sl>=target-1e-12);
      return (sl<=target+1e-12);
   }

   void PruneTracks()
   {
      int w=0;
      for(int i=0;i<m_count;i++)
      {
         if(m_tracks[i].seen) m_tracks[w++]=m_tracks[i];
      }
      for(int i=w;i<m_count;i++) m_tracks[i].Reset();
      m_count=w;
   }

   bool CloseFullHardened(ulong ticket)
   {
      if(!m_trade.PositionClose(ticket)) return false;
      uint rc=m_trade.ResultRetcode();
      // DONE_PARTIAL is not a confirmed full close.
      if(rc==TRADE_RETCODE_DONE || rc==TRADE_RETCODE_DONE_PARTIAL) return true;
      if(rc==TRADE_RETCODE_PLACED) return true;
      return false;
   }

public:
   CPositionManagementEngine(){ m_count=0; m_magic=MM_MAGIC_DEFAULT; m_cfg.Reset(); }
   ~CPositionManagementEngine(){}

   void Init(ulong magic,const MM_PosMgmtConfig &cfg)
   {
      m_magic=magic;
      m_cfg=cfg;
      if(m_cfg.magic==0) m_cfg.magic=(int)magic;
      m_count=0;
      for(int i=0;i<MM_PM_MAX_TRACK;i++) m_tracks[i].Reset();
      m_pm.Init();
      m_pm.SetMagic((int)magic);
      m_trade.SetExpertMagicNumber(magic);
      m_trade.SetDeviationInPoints(MM_SLIPPAGE_DEFAULT);
   }

   void SetConfig(const MM_PosMgmtConfig &cfg)
   {
      m_cfg=cfg;
      m_pm.SetMagic(m_cfg.magic!=0?m_cfg.magic:(int)m_magic);
      m_trade.SetExpertMagicNumber((ulong)(m_cfg.magic!=0?m_cfg.magic:(int)m_magic));
   }
   void SetEnabled(bool on){ m_cfg.enabled=on; }
   bool Enabled(){ return m_cfg.enabled; }
   bool IsEligible(long magic,const string symbol){ return IsEligibleInternal(magic,symbol); }
   int TrackCount(){ return m_count; }
   bool GetTrack(int index,MM_PosMgmtTrack &out)
   {
      if(index<0 || index>=m_count) return false;
      out=m_tracks[index]; return true;
   }

   //--- Pure decision helpers (deterministic, no MT5 state) ---------
   static double ProfitPointsOf(ENUM_POSITION_TYPE type,double openPrice,double currentPrice,double point)
   {
      if(point<=0) return 0;
      if(type==POSITION_TYPE_BUY) return (currentPrice-openPrice)/point;
      return (openPrice-currentPrice)/point;
   }

   static double RMultipleOf(ENUM_POSITION_TYPE type,double openPrice,double riskDistance,double currentPrice)
   {
      if(riskDistance<=0) return 0;
      double profit=(type==POSITION_TYPE_BUY)?(currentPrice-openPrice):(openPrice-currentPrice);
      if(profit<=0) return 0;
      return profit/riskDistance;
   }

   static bool BETriggerReached(ENUM_MM_BE_TRIGGER trigger,double profitPoints,double rMultiple,
                                double pointsThreshold,double rThreshold,string &reason)
   {
      reason="no_trigger";
      if(trigger==MM_BE_TRIGGER_OFF) return false;
      bool ptsMet=(pointsThreshold>0 && profitPoints>=pointsThreshold);
      bool rMet=(rThreshold>0 && rMultiple>=rThreshold);
      if(trigger==MM_BE_TRIGGER_POINTS){ if(ptsMet){ reason="points_reached"; return true; } return false; }
      if(trigger==MM_BE_TRIGGER_R){ if(rMet){ reason="r_reached"; return true; } return false; }
      if(ptsMet || rMet){ reason=ptsMet?"points_reached":"r_reached"; return true; }
      return false;
   }

   static bool TrailActivationReached(double activationPoints,double activationR,
                                      double profitPoints,double rMultiple,string &reason)
   {
      reason="active";
      if(activationPoints>0 && profitPoints<activationPoints){ reason="activation_points_not_reached"; return false; }
      if(activationR>0 && rMultiple<activationR){ reason="activation_r_not_reached"; return false; }
      return true;
   }

   static bool ComputeTrailSL(ENUM_TRAILING_MODE mode,ENUM_POSITION_TYPE type,double currentPrice,
                              double atr,double candleLow,double candleHigh,double distance,double point,
                              double &outSL,string &reason)
   {
      outSL=0; reason="";
      if(mode==TRAIL_FIXED)
      {
         if(point<=0){ reason="invalid_point"; return false; }
         if(distance<=0){ reason="invalid_distance"; return false; }
         outSL=(type==POSITION_TYPE_BUY)?currentPrice-distance*point:currentPrice+distance*point;
         return true;
      }
      if(mode==TRAIL_ATR)
      {
         if(distance<=0){ reason="invalid_distance"; return false; }
         if(atr<=0){ reason="atr_unavailable"; return false; }
         outSL=(type==POSITION_TYPE_BUY)?currentPrice-distance*atr:currentPrice+distance*atr;
         return true;
      }
      if(mode==TRAIL_CANDLE)
      {
         if(type==POSITION_TYPE_BUY)
         {
            if(candleLow<=0){ reason="candle_invalid"; return false; }
            outSL=candleLow;
         }
         else
         {
            if(candleHigh<=0){ reason="candle_invalid"; return false; }
            outSL=candleHigh;
         }
         return true;
      }
      reason="unsupported_mode";
      return false;
   }

   static bool IsProtectiveImprovement(ENUM_POSITION_TYPE type,double currentSL,double candidateSL,
                                       double minStepPoints,double point)
   {
      if(candidateSL<=0 || point<=0) return false;
      double stepDist=(minStepPoints>0)?minStepPoints*point:0.0;
      if(currentSL<=0) return true;
      if(type==POSITION_TYPE_BUY) return (candidateSL>=currentSL+stepDist);
      return (candidateSL<=currentSL-stepDist);
   }

   // Computes a close volume from a baseline percentage. Returns false with a
   // reason when the level is not executable; outFullClose signals remainder mode.
   static bool ComputePartialCloseVolume(double currentVolume,double baselineVolume,double pct,
                                         bool closeRemainder,double volMin,double volMax,double volStep,
                                         double &outVolume,bool &outFullClose,string &reason)
   {
      outVolume=0; outFullClose=false; reason="";
      if(currentVolume<=0){ reason="no_volume"; return false; }
      if(volStep<=0) volStep=0.01;
      if(volMin<=0) volMin=volStep;

      if(closeRemainder)
      {
         outVolume=NormalizeDouble(currentVolume,(int)MathCeil(-MathLog10(volStep)));
         outFullClose=true;
         return true;
      }

      if(pct<=0 || pct>=100){ reason="invalid_percent"; return false; }
      if(baselineVolume<=0){ reason="no_baseline"; return false; }

      double raw=baselineVolume*pct/100.0;
      double v=MathRound(raw/volStep)*volStep;
      int vd=(int)MathCeil(-MathLog10(volStep)); if(vd<0) vd=0;
      v=NormalizeDouble(v,vd);

      double maxClose=currentVolume-volMin;
      if(v>maxClose) v=NormalizeDouble(MathFloor((maxClose)/volStep+1e-9)*volStep,vd);

      if(v<volMin){ reason="close_volume_below_min"; return false; }
      if(v>=currentVolume){ reason="close_volume_not_below_position"; return false; }
      if(v>volMax && volMax>0) v=NormalizeDouble(volMax,vd);
      outVolume=v;
      return true;
   }

   // Reconstructs executed stage mask from broker-confirmed closed volume.
   static int DeriveLevelMask(double baselineVolume,double closedVolume,const double &pcts[],
                              int levelCount,double volStep)
   {
      int mask=0;
      if(baselineVolume<=0 || levelCount<=0) return 0;
      if(volStep<=0) volStep=0.01;
      double cumulative=0.0;
      double tolerance=volStep*0.5;
      for(int i=0;i<levelCount && i<MM_PM_MAX_LEVELS;i++)
      {
         double pct=pcts[i];
         if(pct<=0 || pct>=100) continue;
         cumulative+=baselineVolume*pct/100.0;
         if(closedVolume+tolerance>=cumulative) mask|=(1<<i);
      }
      return mask;
   }

   static bool PartialLevelTriggerReached(double rMultiple,double triggerR,double profitPoints,double fallbackPoints)
   {
      if(triggerR>0 && rMultiple>=triggerR) return true;
      if(triggerR<=0 && fallbackPoints>0 && profitPoints>=fallbackPoints) return true;
      return false;
   }

   static bool PendingCloseConfirmed(double currentVolume,double targetVolume,double volStep)
   {
      if(volStep<=0) volStep=0.01;
      return (currentVolume<=targetVolume+volStep*0.5+1e-9);
   }

   static bool IsSameLifecycle(int storedSide,datetime storedOpen,int liveSide,datetime liveOpen)
   {
      return (storedSide==liveSide && storedOpen==liveOpen);
   }

   //--- Runtime management ------------------------------------------
   void OnTick()
   {
      if(!m_cfg.enabled){ return; }

      for(int i=0;i<m_count;i++) m_tracks[i].seen=false;

      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         ulong ticket=PositionGetTicket(i);
         if(ticket==0) continue;
         if(!PositionSelectByTicket(ticket)) continue;

         long magic=(long)PositionGetInteger(POSITION_MAGIC);
         string symbol=PositionGetString(POSITION_SYMBOL);
         if(!IsEligibleInternal(magic,symbol)) continue;

         ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         datetime openTime=(datetime)PositionGetInteger(POSITION_TIME);

         int idx=EnsureTrack(ticket,symbol,type,openTime);
         if(idx<0) continue;

         ManagePosition(idx,ticket,symbol,type);
      }

      PruneTracks();
   }

private:
   void ManagePosition(int idx,ulong ticket,const string symbol,ENUM_POSITION_TYPE type)
   {
      MM_PosMgmtTrack rec=m_tracks[idx];
      double openPrice=PositionGetDouble(POSITION_PRICE_OPEN);
      double sl=PositionGetDouble(POSITION_SL);
      double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
      if(point<=0) return;

      double bid=SymbolInfoDouble(symbol,SYMBOL_BID);
      double ask=SymbolInfoDouble(symbol,SYMBOL_ASK);
      double currentPrice=(type==POSITION_TYPE_BUY)?bid:ask;
      double trailPrice=PositionGetDouble(POSITION_PRICE_CURRENT);
      if(trailPrice<=0) trailPrice=currentPrice;

      // --- Pending partial-close confirmation (never assumed) ---
      if(rec.pendingLevel>=0)
      {
         double curVol=PositionGetDouble(POSITION_VOLUME);
         double step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
         if(PendingCloseConfirmed(curVol,rec.pendingTargetVolume,step))
         {
            m_tracks[idx].levelMask|=(1<<rec.pendingLevel);
            m_tracks[idx].pendingLevel=-1;
            g_mmLog.Info("PM_PARTIAL_CONFIRMED","ticket="+(string)ticket+" level="+(string)(rec.pendingLevel+1)+" vol="+DoubleToString(curVol,2));
         }
         else if((long)TimeCurrent()- (long)rec.pendingTime > 60)
         {
            // Request outcome still unconfirmed: clear pending so a retry is possible,
            // but do not mark the stage executed.
            m_tracks[idx].pendingLevel=-1;
            g_mmLog.Warn("PM_PARTIAL_UNCONFIRMED","ticket="+(string)ticket+" level="+(string)(rec.pendingLevel+1)+" not confirmed by server volume");
         }
         return;
      }

      // --- Time-based exit (full close path; risk-reducing) ---
      if(m_cfg.timeExitEnabled && m_cfg.maxMinutes>0)
      {
         if(m_pm.TimeBasedExit(ticket,m_cfg.maxMinutes))
         {
            g_mmLog.Info("PM_TIME_EXIT","ticket="+(string)ticket+" minutes="+(string)m_cfg.maxMinutes);
            return;
         }
      }

      double profitPoints=ProfitPointsOf(type,openPrice,currentPrice,point);
      double rMult=RMultipleOf(type,openPrice,rec.riskDistance,currentPrice);

      // --- Break Even (one-time per lifecycle, server truth also prevents duplicates) ---
      if(m_cfg.beEnabled && !rec.beDone)
      {
         string why="";
         if(BETriggerReached(m_cfg.beTrigger,profitPoints,rMult,m_cfg.beProfitPoints,m_cfg.beRMultiple,why))
         {
            if(IsProtectedByBE(symbol,type,openPrice,sl))
            {
               m_tracks[idx].beDone=true;
            }
            else if(m_cfg.beMode!=BE_NONE)
            {
               if(m_pm.MoveToBreakEven(ticket,m_cfg.beMode,m_cfg.beExtraPoints))
               {
                  m_tracks[idx].beDone=true;
                  g_mmLog.Info("PM_BE_APPLIED","ticket="+(string)ticket+" trigger="+why);
               }
            }
         }
      }

      // --- Trailing stop (monotonic; no loosening; update step; no redundant modifies) ---
      if(m_cfg.trailEnabled && m_cfg.trailMode!=TRAIL_NONE)
      {
         string ar="";
         if(TrailActivationReached(m_cfg.trailActivationPoints,m_cfg.trailActivationR,profitPoints,rMult,ar))
         {
            double atr=0.0, cLow=0.0, cHigh=0.0;
            if(m_cfg.trailMode==TRAIL_ATR) atr=GetATR(symbol,m_cfg.trailTimeframe,14);
            if(m_cfg.trailMode==TRAIL_CANDLE)
            {
               cLow=iLow(symbol,m_cfg.trailTimeframe,1);
               cHigh=iHigh(symbol,m_cfg.trailTimeframe,1);
            }
            double candidate=0; string cr="";
            if(ComputeTrailSL(m_cfg.trailMode,type,trailPrice,atr,cLow,cHigh,m_cfg.trailValue,point,candidate,cr))
            {
               int digits=(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
               if(digits<0) digits=5;
               candidate=NormalizeDouble(candidate,digits);
               if(IsProtectiveImprovement(type,sl,candidate,m_cfg.trailUpdateStepPoints,point))
               {
                  if(m_pm.TrailStop(ticket,m_cfg.trailMode,m_cfg.trailValue,m_cfg.trailTimeframe))
                     g_mmLog.Info("PM_TRAIL_APPLIED","ticket="+(string)ticket+" sl="+DoubleToString(candidate,digits));
               }
            }
         }
      }

      // --- Multi-level partial close (default off; unknown history => skipped) ---
      if(m_cfg.partialEnabled && m_cfg.partialLevels>0 && rec.historyKnown)
      {
         double curVol=PositionGetDouble(POSITION_VOLUME);
         double volMin=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
         double volMax=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
         double volStep=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
         if(volStep<=0) volStep=0.01;

         for(int lvl=0;lvl<m_cfg.partialLevels && lvl<MM_PM_MAX_LEVELS;lvl++)
         {
            if((m_tracks[idx].levelMask&(1<<lvl))!=0) continue;
            if(!PartialLevelTriggerReached(rMult,m_cfg.partialTriggerR[lvl],profitPoints,0)) break;

            bool isLast=(lvl==m_cfg.partialLevels-1);
            bool remainder=(isLast && m_cfg.partialLastCloseRemainder);
            double closeVol=0; bool fullClose=false; string reason="";
            if(!ComputePartialCloseVolume(curVol,rec.baselineVolume,m_cfg.partialPct[lvl],remainder,
                                          volMin,volMax,volStep,closeVol,fullClose,reason))
            {
               g_mmLog.Warn("PM_PARTIAL_SKIP","ticket="+(string)ticket+" level="+(string)(lvl+1)+" reason="+reason);
               break;
            }

            double targetVol=fullClose?0.0:(curVol-closeVol);
            if(fullClose)
            {
               if(!CloseFullHardened(ticket))
               {
                  g_mmLog.Warn("PM_PARTIAL_FAIL","ticket="+(string)ticket+" level="+(string)(lvl+1)+" retcode="+(string)m_trade.ResultRetcode());
                  break;
               }
            }
            else
            {
               double pctOfCurrent=closeVol/curVol*100.0;
               if(!m_pm.PartialClose(ticket,pctOfCurrent))
               {
                  g_mmLog.Warn("PM_PARTIAL_FAIL","ticket="+(string)ticket+" level="+(string)(lvl+1)+" reason="+m_pm.LastError()+" retcode="+(string)m_pm.LastRetcode());
                  break;
               }
            }

            m_tracks[idx].pendingLevel=lvl;
            m_tracks[idx].pendingTargetVolume=targetVol;
            m_tracks[idx].pendingTime=TimeCurrent();
            g_mmLog.Info("PM_PARTIAL_REQUESTED","ticket="+(string)ticket+" level="+(string)(lvl+1)+" close="+DoubleToString(closeVol,2)+" target="+DoubleToString(targetVol,2));
            break;
         }
      }
   }

public:
   string StatusSummary()
   {
      if(!m_cfg.enabled) return "AUTO off";
      string be="off";
      if(m_cfg.beEnabled && m_cfg.beTrigger!=MM_BE_TRIGGER_OFF)
      {
         if(m_cfg.beTrigger==MM_BE_TRIGGER_POINTS) be="BE "+DoubleToString(m_cfg.beProfitPoints,0)+"p";
         else if(m_cfg.beTrigger==MM_BE_TRIGGER_R) be="BE "+DoubleToString(m_cfg.beRMultiple,1)+"R";
         else be="BE p/R";
      }
      string tr=(m_cfg.trailEnabled && m_cfg.trailMode!=TRAIL_NONE)?("T "+DoubleToString(m_cfg.trailValue,0)):"T off";
      string pc=m_cfg.partialEnabled?("PC "+IntegerToString(m_cfg.partialLevels)):"PC off";
      string tx=(m_cfg.timeExitEnabled && m_cfg.maxMinutes>0)?("TX "+IntegerToString(m_cfg.maxMinutes)+"m"):"TX off";
      return "AUTO on | "+be+" | "+tr+" | "+pc+" | "+tx+" | n="+IntegerToString(m_count);
   }
};

#endif // MM_POSITION_MANAGEMENT_ENGINE_MQH
