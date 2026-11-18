//+------------------------------------------------------------------+
//|                                                  Statistics.mqh  |
//|     Phase 6/7: TradeLogger/Stats, partial aggregation, open risk |
//+------------------------------------------------------------------+
#ifndef MM_STATISTICS_MQH
#define MM_STATISTICS_MQH

#include "../Core/Contracts.mqh"
#include "../Core/Logger.mqh"
#include "../Utils/Common.mqh"

#define MM_MAX_CLOSED_TRADES 500
#define MM_MAX_OPEN_TRACK    120

struct MM_OpenTradeTrack
{
   long     positionId;
   ulong    ticket;
   string   symbol;
   ENUM_POSITION_TYPE side;
   double   volumeInitial;
   double   volumeRemain;
   double   openPrice;
   double   sl;
   double   initialRiskMoney;
   double   realizedProfit;
   double   realizedCommission;
   double   realizedSwap;
   double   closedVolume;
   datetime openTime;
   datetime lastEventTime;
   ENUM_MM_ACCOUNT_MODE accountMode;
   bool     active;
   void Reset(){ positionId=0; ticket=0; symbol=""; side=POSITION_TYPE_BUY; volumeInitial=0; volumeRemain=0; openPrice=0; sl=0; initialRiskMoney=0; realizedProfit=0; realizedCommission=0; realizedSwap=0; closedVolume=0; openTime=0; lastEventTime=0; accountMode=ACCOUNT_PERSONAL; active=false; }
};

struct MM_ClosedTrade
{
   ulong    ticket;
   long     positionId;
   string   symbol;
   string   typeStr;
   datetime openTime;
   datetime closeTime;
   double   volume;
   double   openPrice;
   double   closePrice;
   double   profit;
   double   commission;
   double   swap;
   double   rMultiple;
   long     durationSec;
   ENUM_MM_ACCOUNT_MODE accountMode;
   void Reset(){ ticket=0; positionId=0; symbol=""; typeStr=""; openTime=0; closeTime=0; volume=0; openPrice=0; closePrice=0; profit=0; commission=0; swap=0; rMultiple=0; durationSec=0; accountMode=ACCOUNT_PERSONAL; }
};

struct MM_Kpi
{
   int    trades;
   int    wins;
   int    losses;
   double winRate;
   double profitFactor;
   double expectancy;
   double avgR;
   double maxDrawdown;      // peak-to-trough on cumulative net (money)
   double avgDurationMin;
   double grossProfit;
   double grossLoss;
   double netProfit;
   void Reset(){ trades=0; wins=0; losses=0; winRate=0; profitFactor=0; expectancy=0; avgR=0; maxDrawdown=0; avgDurationMin=0; grossProfit=0; grossLoss=0; netProfit=0; }
};

class CStatistics : public ITradeEventListener
{
private:
   MM_OpenTradeTrack m_open[MM_MAX_OPEN_TRACK];
   int               m_openCount;
   MM_ClosedTrade    m_closed[MM_MAX_CLOSED_TRADES];
   int               m_closedCount;
   int               m_closedHead;
   string            m_csvPath;
   ENUM_MM_ACCOUNT_MODE m_currentMode;
   double            m_lastPlannedRisk;
   string            m_lastPlannedSymbol;
   datetime          m_lastPlannedTime;

   int FindOpenByPos(long posId)
   {
      if(posId==0) return -1;
      for(int i=0;i<m_openCount;i++) if(m_open[i].active && m_open[i].positionId==posId) return i;
      return -1;
   }
   int FindOpenByTicket(ulong ticket)
   {
      if(ticket==0) return -1;
      for(int i=0;i<m_openCount;i++) if(m_open[i].active && m_open[i].ticket==ticket) return i;
      return -1;
   }
   int FindOpenBySymbol(const string sym)
   {
      for(int i=m_openCount-1;i>=0;i--) if(m_open[i].active && m_open[i].symbol==sym) return i;
      return -1;
   }
   int AllocOpen()
   {
      for(int i=0;i<m_openCount;i++) if(!m_open[i].active) return i;
      if(m_openCount<MM_MAX_OPEN_TRACK){ int i=m_openCount++; m_open[i].Reset(); return i; }
      m_open[0].Reset(); return 0;
   }
   void PushClosed(const MM_ClosedTrade &t)
   {
      int idx = (m_closedCount < MM_MAX_CLOSED_TRADES) ? m_closedCount++ : m_closedHead;
      m_closed[idx]=t;
      if(m_closedCount>=MM_MAX_CLOSED_TRADES) m_closedHead=(m_closedHead+1)%MM_MAX_CLOSED_TRADES;
   }
   bool GetClosed(int index, MM_ClosedTrade &out)
   {
      if(index<0 || index>=m_closedCount) return false;
      int idx = (m_closedCount < MM_MAX_CLOSED_TRADES) ? index : (m_closedHead+index)%MM_MAX_CLOSED_TRADES;
      out=m_closed[idx]; return true;
   }

   double CalcInitialRisk(const string symbol,double openPrice,double sl,double volume)
   {
      double slDist=MathAbs(openPrice-sl);
      if(slDist<=0 || volume<=0) return 0;
      double tickVal=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE);
      double tickSize=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
      if(tickVal<=0 || tickSize<=0) return 0;
      return (slDist/tickSize)*tickVal*volume;
   }

   double RemainingRisk(const MM_OpenTradeTrack &t)
   {
      if(t.volumeRemain<=0) return 0;
      double r=CalcInitialRisk(t.symbol,t.openPrice,t.sl,t.volumeRemain);
      if(r<=0 && t.volumeInitial>0) r = t.initialRiskMoney * (t.volumeRemain / t.volumeInitial);
      return r;
   }

   void SyncOpenFromPosition(MM_OpenTradeTrack &t)
   {
      if(t.positionId==0) return;
      if(PositionSelectByTicket((ulong)t.positionId))
      {
         t.volumeRemain = PositionGetDouble(POSITION_VOLUME);
         t.sl = PositionGetDouble(POSITION_SL);
         t.openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         return;
      }
      if(t.symbol!="" && PositionSelect(t.symbol))
      {
         if((long)PositionGetInteger(POSITION_IDENTIFIER)==t.positionId || (long)PositionGetInteger(POSITION_TICKET)==t.positionId)
         {
            t.volumeRemain = PositionGetDouble(POSITION_VOLUME);
            t.sl = PositionGetDouble(POSITION_SL);
            t.openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         }
      }
   }

   // Returns true while the tracked position is still present on the server.
   // Checks by ticket first (POSITION_TICKET == positionId), then by symbol
   // (netting accounts where the position id equals the position identifier).
   bool PositionStillOpen(long positionId,const string symbol)
   {
      if(positionId==0) return false;
      if(PositionSelectByTicket((ulong)positionId)) return true;
      if(symbol!="" && PositionSelect(symbol))
      {
         if((long)PositionGetInteger(POSITION_IDENTIFIER)==positionId) return true;
         if((long)PositionGetInteger(POSITION_TICKET)==positionId) return true;
      }
      return false;
   }

   void FinalizeTrade(int idx,const MM_TradeEvent &event,double totalProfit,double totalComm,double totalSwap,double totalVol,datetime closeTime,double closePrice)
   {
      if(idx<0 || idx>=m_openCount || !m_open[idx].active) return;
      MM_OpenTradeTrack tr=m_open[idx];
      MM_ClosedTrade t; t.Reset();
      t.positionId=tr.positionId; t.ticket=(tr.ticket!=0?tr.ticket:(event.ticket!=0?event.ticket:event.order));
      t.symbol=(tr.symbol!=""?tr.symbol:event.symbol);
      t.openTime=tr.openTime; t.closeTime=closeTime;
      t.openPrice=tr.openPrice; t.closePrice=closePrice;
      t.volume=(totalVol>0?totalVol:(tr.volumeInitial>0?tr.volumeInitial:tr.closedVolume));
      t.profit=totalProfit; t.commission=totalComm; t.swap=totalSwap;
      t.typeStr=(tr.side==POSITION_TYPE_BUY)?"BUY":"SELL";
      t.accountMode=tr.accountMode;
      t.durationSec=(t.openTime>0 && t.closeTime>=t.openTime)? (long)(t.closeTime-t.openTime) : 0;
      double initRisk=tr.initialRiskMoney; if(initRisk<=0) initRisk=CalcInitialRisk(t.symbol,t.openPrice,tr.sl,tr.volumeInitial);
      double net=t.profit+t.commission+t.swap;
      t.rMultiple=(initRisk>0)?(net/initRisk):0.0;
      PushClosed(t);
      m_open[idx].active=false;
   }

   void HandleOpen(const MM_TradeEvent &event)
   {
      int idx = FindOpenByPos(event.positionId);
      if(idx>=0 && m_open[idx].active)
      {
         // netting add/scale-in: increase volume and risk baseline
         double addVol=event.volume;
         if(addVol>0)
         {
            m_open[idx].volumeInitial += addVol;
            m_open[idx].volumeRemain += addVol;
            m_open[idx].openPrice = (event.price>0)?event.price:m_open[idx].openPrice;
         }
         m_open[idx].lastEventTime=(event.timeServer!=0?event.timeServer:TimeCurrent());
         return;
      }
      idx = AllocOpen();
      m_open[idx].Reset();
      m_open[idx].active=true;
      m_open[idx].positionId=event.positionId;
      m_open[idx].ticket=(event.ticket!=0?event.ticket:event.order);
      m_open[idx].symbol=event.symbol;
      m_open[idx].side=event.side;
      m_open[idx].volumeInitial=event.volume;
      m_open[idx].volumeRemain=event.volume;
      m_open[idx].openPrice=event.price;
      m_open[idx].sl=event.sl;
      m_open[idx].openTime=(event.timeServer!=0?event.timeServer:TimeCurrent());
      m_open[idx].lastEventTime=m_open[idx].openTime;
      m_open[idx].accountMode=m_currentMode;
      double r = CalcInitialRisk(event.symbol, event.price, event.sl, event.volume);
      if(r<=0 && m_lastPlannedSymbol==event.symbol && (TimeCurrent()-m_lastPlannedTime) < 300)
         r = m_lastPlannedRisk;
      m_open[idx].initialRiskMoney=r;
      m_lastPlannedRisk=0; m_lastPlannedSymbol="";
   }

   void HandlePartialClose(const MM_TradeEvent &event)
   {
      int idx = FindOpenByPos(event.positionId);
      if(idx<0) idx = FindOpenByTicket(event.ticket);
      if(idx<0) idx = FindOpenBySymbol(event.symbol);
      if(idx<0 || !m_open[idx].active)
      {
         // cannot aggregate; record as standalone partial-close trade
         MM_ClosedTrade t; t.Reset();
         t.ticket=(event.ticket!=0?event.ticket:event.order); t.positionId=event.positionId; t.symbol=event.symbol;
         t.openTime=event.timeServer; t.closeTime=event.timeServer; t.openPrice=event.price; t.closePrice=event.price;
         t.volume=event.volume; t.profit=event.profit; t.commission=event.commission; t.swap=event.swap;
         t.accountMode=m_currentMode; t.durationSec=0; t.rMultiple=0;
         PushClosed(t);
         g_mmLog.Warn("STATS_PARTIAL_ORPHAN","Partial close without tracked open pos="+(string)event.positionId+" sym="+event.symbol);
         return;
      }
      m_open[idx].realizedProfit += event.profit;
      m_open[idx].realizedCommission += event.commission;
      m_open[idx].realizedSwap += event.swap;
      m_open[idx].closedVolume += event.volume;
      m_open[idx].lastEventTime = (event.timeServer!=0?event.timeServer:TimeCurrent());
      // update remaining volume from live position if possible
      double beforeRemain = m_open[idx].volumeRemain;
      SyncOpenFromPosition(m_open[idx]);
      if(m_open[idx].volumeRemain <= 0.0 || !PositionStillOpen(m_open[idx].positionId, m_open[idx].symbol))
      {
         double totalVol = m_open[idx].closedVolume; if(totalVol<=0) totalVol=m_open[idx].volumeInitial;
         FinalizeTrade(idx,event,m_open[idx].realizedProfit,m_open[idx].realizedCommission,m_open[idx].realizedSwap,totalVol,m_open[idx].lastEventTime,event.price);
      }
      else
      {
         // proportionally reduce baseline risk to remaining exposure
         if(beforeRemain>0 && m_open[idx].volumeRemain < beforeRemain && m_open[idx].volumeInitial>0)
         {
            double frac = m_open[idx].volumeRemain / beforeRemain;
            if(frac<0) frac=0;
            m_open[idx].initialRiskMoney = MathMax(0.0, m_open[idx].initialRiskMoney * frac);
         }
      }
   }

   void HandleClose(const MM_TradeEvent &event)
   {
      int idx = FindOpenByPos(event.positionId);
      if(idx<0) idx = FindOpenByTicket(event.ticket);
      if(idx<0) idx = FindOpenBySymbol(event.symbol);
      if(idx<0 || !m_open[idx].active)
      {
         MM_ClosedTrade t; t.Reset();
         t.positionId=event.positionId; t.ticket=(event.ticket!=0?event.ticket:event.order);
         t.symbol=event.symbol;
         t.closeTime=(event.timeServer!=0?event.timeServer:TimeCurrent());
         t.closePrice=event.price; t.profit=event.profit; t.commission=event.commission; t.swap=event.swap;
         t.volume=event.volume; t.openTime=t.closeTime; t.openPrice=t.closePrice; t.typeStr=""; t.accountMode=m_currentMode;
         t.durationSec=0; t.rMultiple=0;
         PushClosed(t);
         return;
      }
      double totalProfit = m_open[idx].realizedProfit + event.profit;
      double totalComm   = m_open[idx].realizedCommission + event.commission;
      double totalSwap   = m_open[idx].realizedSwap + event.swap;
      double totalVol    = m_open[idx].closedVolume + event.volume;
      if(totalVol<=0) totalVol=m_open[idx].volumeInitial;
      datetime ct = (event.timeServer!=0?event.timeServer:TimeCurrent());
      FinalizeTrade(idx,event,totalProfit,totalComm,totalSwap,totalVol,ct,event.price);
   }

   void ComputeKpi(MM_Kpi &k, ENUM_MM_ACCOUNT_MODE modeFilter, bool filterByMode)
   {
      k.Reset();
      double sumR=0; double sumDur=0; int durN=0;
      double equity=0, peak=0, maxDD=0;
      bool first=true;
      for(int i=0;i<m_closedCount;i++)
      {
         MM_ClosedTrade t; if(!GetClosed(i,t)) continue;
         if(filterByMode && t.accountMode!=modeFilter) continue;
         k.trades++;
         double net = t.profit + t.commission + t.swap;
         k.netProfit += net;
         if(net>0){ k.wins++; k.grossProfit += net; }
         else if(net<0){ k.losses++; k.grossLoss += -net; }
         sumR += t.rMultiple;
         if(t.durationSec>0){ sumDur += (double)t.durationSec; durN++; }
         equity += net;
         if(first){ peak=equity; maxDD=0; first=false; }
         if(equity>peak) peak=equity;
         double dd = peak - equity;
         if(dd>maxDD) maxDD=dd;
      }
      if(k.trades>0)
      {
         k.winRate = (double)k.wins / (double)k.trades * 100.0;
         k.expectancy = k.netProfit / (double)k.trades;
         k.avgR = sumR / (double)k.trades;
         if(k.grossLoss>0) k.profitFactor = k.grossProfit / k.grossLoss;
         else k.profitFactor = (k.grossProfit>0? 999.0 : 0.0);
         if(durN>0) k.avgDurationMin = (sumDur/(double)durN)/60.0;
      }
      k.maxDrawdown = maxDD;
   }

public:
   CStatistics(){ m_openCount=0; m_closedCount=0; m_closedHead=0; m_csvPath="MoneyManager_trades.csv"; m_currentMode=ACCOUNT_PERSONAL; m_lastPlannedRisk=0; m_lastPlannedSymbol=""; m_lastPlannedTime=0; }

   void Init(string csvName="MoneyManager_trades.csv")
   {
      m_csvPath=csvName; m_openCount=0; m_closedCount=0; m_closedHead=0; m_lastPlannedRisk=0; m_lastPlannedSymbol=""; m_lastPlannedTime=0;
   }

   void SetAccountMode(ENUM_MM_ACCOUNT_MODE mode){ m_currentMode=mode; }
   void RegisterPlannedRisk(const string symbol,double riskMoney,ENUM_MM_ACCOUNT_MODE mode)
   {
      m_lastPlannedSymbol=symbol; m_lastPlannedRisk=riskMoney; m_currentMode=mode; m_lastPlannedTime=TimeCurrent();
   }

   virtual void OnTradeEvent(const MM_TradeEvent &event)
   {
      if(event.type==MM_EVENT_OPEN) HandleOpen(event);
      else if(event.type==MM_EVENT_PARTIAL_FILL && event.reasonCode=="PARTIAL_CLOSE") HandlePartialClose(event);
      else if(event.type==MM_EVENT_PARTIAL_FILL && event.reasonCode=="INOUT") HandlePartialClose(event);
      else if(event.type==MM_EVENT_CLOSE) HandleClose(event);
   }

   double CalcOpenRiskMoney(long magicFilter=0, const string symbolFilter="")
   {
      double total=0.0;
      // prefer tracked open risk
      bool any=false;
      for(int i=0;i<m_openCount;i++)
      {
         if(!m_open[i].active) continue;
         if(symbolFilter!="" && m_open[i].symbol!=symbolFilter) continue;
         // sync to live where possible for accurate remaining
         SyncOpenFromPosition(m_open[i]);
         double r=RemainingRisk(m_open[i]);
         if(r>0){ total+=r; any=true; }
      }
      // fallback/supplement: scan live positions (covers untracked/manual positions)
      int totalPos=PositionsTotal();
      for(int i=0;i<totalPos;i++)
      {
         ulong ticket=PositionGetTicket(i);
         if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
         string sym=PositionGetString(POSITION_SYMBOL);
         long mg=(long)PositionGetInteger(POSITION_MAGIC);
         if(symbolFilter!="" && sym!=symbolFilter) continue;
         if(magicFilter!=0 && mg!=magicFilter) continue;
         long pid=(long)PositionGetInteger(POSITION_IDENTIFIER);
         if(FindOpenByPos(pid)>=0) continue; // already counted via track
         double vol=PositionGetDouble(POSITION_VOLUME);
         double open=PositionGetDouble(POSITION_PRICE_OPEN);
         double sl=PositionGetDouble(POSITION_SL);
         double slDist=MathAbs(open-sl);
         if(sl<=0 || slDist<=0 || vol<=0) continue;
         double tickVal=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE);
         double tickSize=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_SIZE);
         if(tickVal<=0 || tickSize<=0) continue;
         double perLot=(slDist/tickSize)*tickVal;
         if(perLot>0) total += perLot*vol;
      }
      return total;
   }

   void GetKpi(MM_Kpi &out){ ComputeKpi(out, ACCOUNT_PERSONAL, false); }
   void GetKpiForMode(ENUM_MM_ACCOUNT_MODE mode, MM_Kpi &out){ ComputeKpi(out, mode, true); }
   int ClosedCount(){ return m_closedCount; }

   bool ExportCSV(string filename="", ENUM_MM_ACCOUNT_MODE modeFilter=ACCOUNT_PERSONAL, bool filterByMode=false)
   {
      string path = (filename=="")? m_csvPath : filename;
      int h=FileOpen(path, FILE_WRITE|FILE_CSV|FILE_COMMON|FILE_ANSI, ',');
      if(h==INVALID_HANDLE){ Print("Stats: failed to open CSV ",path); g_mmLog.Error("CSV_OPEN_FAIL",path); return false; }
      FileWrite(h,"ticket","symbol","type","openTime","closeTime","volume","openPrice","closePrice","profit","commission","swap","R","duration","accountMode");
      for(int i=0;i<m_closedCount;i++)
      {
         MM_ClosedTrade t; if(!GetClosed(i,t)) continue;
         if(filterByMode && t.accountMode!=modeFilter) continue;
         int digits=(int)SymbolInfoInteger(t.symbol,SYMBOL_DIGITS); if(digits<=0) digits=5;
         FileWrite(h,
            (string)t.ticket,
            t.symbol,
            t.typeStr,
            TimeToString(t.openTime,TIME_DATE|TIME_SECONDS),
            TimeToString(t.closeTime,TIME_DATE|TIME_SECONDS),
            DoubleToString(t.volume,2),
            DoubleToString(t.openPrice,digits),
            DoubleToString(t.closePrice,digits),
            DoubleToString(t.profit,2),
            DoubleToString(t.commission,2),
            DoubleToString(t.swap,2),
            DoubleToString(t.rMultiple,4),
            (string)t.durationSec,
            (string)((int)t.accountMode)
         );
      }
      FileClose(h);
      g_mmLog.Info("CSV_EXPORT",path+" rows="+(string)m_closedCount);
      Print("Stats: CSV exported ",path);
      return true;
   }

   void CloseCSV(){}
   double WinRate(){ MM_Kpi k; GetKpi(k); return k.winRate; }
   double ProfitFactor(){ MM_Kpi k; GetKpi(k); return k.profitFactor; }
   int TotalTrades(){ MM_Kpi k; GetKpi(k); return k.trades; }
};

#endif // MM_STATISTICS_MQH
