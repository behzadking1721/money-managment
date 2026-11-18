//+------------------------------------------------------------------+
//|                                                  Statistics.mqh  |
//|        Phase 6: TradeLogger/Stats from OnTradeTransaction events |
//+------------------------------------------------------------------+
#ifndef MM_STATISTICS_MQH
#define MM_STATISTICS_MQH

#include "../Core/Contracts.mqh"
#include "../Utils/Common.mqh"

#define MM_MAX_CLOSED_TRADES 500
#define MM_MAX_OPEN_TRACK    120

struct MM_OpenTradeTrack
{
   long     positionId;
   ulong    ticket;
   string   symbol;
   ENUM_POSITION_TYPE side;
   double   volume;
   double   openPrice;
   double   sl;
   double   initialRiskMoney;
   datetime openTime;
   ENUM_MM_ACCOUNT_MODE accountMode;
   bool     active;
   void Reset(){ positionId=0; ticket=0; symbol=""; side=POSITION_TYPE_BUY; volume=0; openPrice=0; sl=0; initialRiskMoney=0; openTime=0; accountMode=ACCOUNT_PERSONAL; active=false; }
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

   void HandleOpen(const MM_TradeEvent &event)
   {
      int idx = AllocOpen();
      m_open[idx].Reset();
      m_open[idx].active=true;
      m_open[idx].positionId=event.positionId;
      m_open[idx].ticket=(event.ticket!=0?event.ticket:event.order);
      m_open[idx].symbol=event.symbol;
      m_open[idx].side=event.side;
      m_open[idx].volume=event.volume;
      m_open[idx].openPrice=event.price;
      m_open[idx].sl=event.sl;
      m_open[idx].openTime=(event.timeServer!=0?event.timeServer:TimeCurrent());
      m_open[idx].accountMode=m_currentMode;
      double r = CalcInitialRisk(event.symbol, event.price, event.sl, event.volume);
      if(r<=0 && m_lastPlannedSymbol==event.symbol && (TimeCurrent()-m_lastPlannedTime) < 180)
         r = m_lastPlannedRisk;
      m_open[idx].initialRiskMoney=r;
      m_lastPlannedRisk=0; m_lastPlannedSymbol="";
   }

   void HandleClose(const MM_TradeEvent &event)
   {
      int idx = FindOpenByPos(event.positionId);
      if(idx<0) idx = FindOpenByTicket(event.ticket);
      if(idx<0) idx = FindOpenBySymbol(event.symbol);
      MM_ClosedTrade t; t.Reset();
      t.positionId=event.positionId; t.ticket=(event.ticket!=0?event.ticket:event.order);
      t.symbol=event.symbol;
      t.closeTime=(event.timeServer!=0?event.timeServer:TimeCurrent());
      t.closePrice=event.price; t.profit=event.profit; t.commission=event.commission; t.swap=event.swap;
      t.volume=event.volume;
      double initRisk=0;
      if(idx>=0 && m_open[idx].active)
      {
         t.openTime=m_open[idx].openTime;
         t.openPrice=m_open[idx].openPrice;
         t.accountMode=m_open[idx].accountMode;
         t.typeStr = (m_open[idx].side==POSITION_TYPE_BUY)?"BUY":"SELL";
         if(t.volume<=0) t.volume=m_open[idx].volume;
         if(t.symbol=="") t.symbol=m_open[idx].symbol;
         initRisk=m_open[idx].initialRiskMoney;
         if(initRisk<=0) initRisk=CalcInitialRisk(t.symbol,t.openPrice,m_open[idx].sl,m_open[idx].volume);
         m_open[idx].active=false;
      }
      else
      {
         t.openTime=t.closeTime; t.openPrice=t.closePrice; t.typeStr=""; t.accountMode=m_currentMode;
      }
      t.durationSec = (t.openTime>0 && t.closeTime>=t.openTime)? (long)(t.closeTime-t.openTime) : 0;
      double net = t.profit + t.commission + t.swap;
      t.rMultiple = (initRisk>0)? (net/initRisk) : 0.0;
      PushClosed(t);
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
      else if(event.type==MM_EVENT_CLOSE) HandleClose(event);
   }

   void GetKpi(MM_Kpi &out){ ComputeKpi(out, ACCOUNT_PERSONAL, false); }
   void GetKpiForMode(ENUM_MM_ACCOUNT_MODE mode, MM_Kpi &out){ ComputeKpi(out, mode, true); }
   int ClosedCount(){ return m_closedCount; }

   bool ExportCSV(string filename="", ENUM_MM_ACCOUNT_MODE modeFilter=ACCOUNT_PERSONAL, bool filterByMode=false)
   {
      string path = (filename=="")? m_csvPath : filename;
      int h=FileOpen(path, FILE_WRITE|FILE_CSV|FILE_COMMON|FILE_ANSI, ',');
      if(h==INVALID_HANDLE){ Print("Stats: failed to open CSV ",path); return false; }
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
      Print("Stats: CSV exported ",path);
      return true;
   }

   void CloseCSV(){}
   // legacy helpers
   double WinRate(){ MM_Kpi k; GetKpi(k); return k.winRate; }
   double ProfitFactor(){ MM_Kpi k; GetKpi(k); return k.profitFactor; }
   int TotalTrades(){ MM_Kpi k; GetKpi(k); return k.trades; }
};

#endif // MM_STATISTICS_MQH
