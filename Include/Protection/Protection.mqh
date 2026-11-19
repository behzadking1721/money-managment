#ifndef PROTECTION_MQH
#define PROTECTION_MQH
#include "../Utils/Common.mqh"
#include "../Core/Logger.mqh"

// Phase 2.3: protection state & limits accounting.
// - Daily/weekly/monthly boundaries use MT5 server time (TimeTradeServer fallback TimeCurrent).
// - Daily/weekly/monthly loss & profit are realized accounting over completed trades only:
//   net per completed trade = profit + commission + swap (aggregated once per trade lifecycle).
//   No floating P/L in period loss/profit; no invented historical period data on init/reset.
// - Period pct basis: realized loss in period / period-start balance (balance snapshot at period start).
// - Daily trade limit counts actual risk-increasing exposure events (new entry exposure), deduped by order ticket.
// - Consecutive win/loss streak updates once per completed trade outcome.
class CProtection
{
private:
   double   m_startBalance;
   double   m_dayStartBalance;
   double   m_dayStartEquity;
   double   m_weekStartBalance;
   double   m_monthStartBalance;
   double   m_peakEquity;
   double   m_peakBalance;

   double   m_dailyProfit;
   double   m_dailyLoss;
   double   m_weeklyProfit;
   double   m_weeklyLoss;
   double   m_monthlyProfit;
   double   m_monthlyLoss;

   datetime m_dayStart;
   int      m_dayKey;
   int      m_weekKey;
   int      m_monthKey;

   int      m_tradesToday;
   int      m_consecutiveLosses;
   int      m_consecutiveWins;
   datetime m_cooldownUntil;

   ulong    m_countedExposureOrders[256];
   int      m_countedExposureCount;
   int      m_countedExposureHead;

   SPropFirmRules m_rules; bool m_hasRules;

   double RefBalance(){ return (m_startBalance>0)?m_startBalance:AccountInfoDouble(ACCOUNT_BALANCE); }

   datetime EffectiveServerTime(datetime srv=0)
   {
      if(srv>0) return srv;
      datetime t=TimeTradeServer();
      if(t==0) t=TimeCurrent();
      return t;
   }

   int DayKey(datetime srv){ MqlDateTime dt; TimeToStruct(srv,dt); return dt.year*10000 + dt.mon*100 + dt.day; }
   int MonthKey(datetime srv){ MqlDateTime dt; TimeToStruct(srv,dt); return dt.year*100 + dt.mon; }
   int WeekKeyMonday(datetime srv)
   {
      MqlDateTime dt; TimeToStruct(srv,dt);
      int doy=dt.day_of_year; if(doy<=0) doy=1;
      // Anchor week 0 to the first Monday of the year (Monday-start weeks).
      // Days before the first Monday form a partial first week (weekIndex=0).
      MqlDateTime jan1=dt; jan1.mon=1; jan1.day=1; jan1.hour=0; jan1.min=0; jan1.sec=0;
      datetime jan1Time=StructToTime(jan1);
      MqlDateTime jan1dt; TimeToStruct(jan1Time,jan1dt);
      int jan1Dow=jan1dt.day_of_week; // 0=Sun
      int daysUntilMonday=(1-jan1Dow+7)%7; // days from Jan 1 to first Monday
      int firstMondayDoy=1+daysUntilMonday;
      int weekIndex;
      if(doy < firstMondayDoy) weekIndex=0;
      else weekIndex=(doy-firstMondayDoy)/7;
      return dt.year*100 + weekIndex;
   }

   void SyncPeaksInternal()
   {
      double eq=AccountInfoDouble(ACCOUNT_EQUITY); if(eq>m_peakEquity) m_peakEquity=eq;
      double bal=AccountInfoDouble(ACCOUNT_BALANCE); if(bal>m_peakBalance) m_peakBalance=bal;
   }

   void ResetDaily(datetime srv)
   {
      m_dayStartBalance=AccountInfoDouble(ACCOUNT_BALANCE);
      m_dayStartEquity=AccountInfoDouble(ACCOUNT_EQUITY);
      m_dailyProfit=0; m_dailyLoss=0;
      m_tradesToday=0;
      m_countedExposureCount=0;
      m_countedExposureHead=0;
      m_dayStart=srv;
      m_dayKey=DayKey(srv);
      SyncPeaksInternal();
      g_mmLog.Info("DAY_RESET","dayStartBal="+DoubleToString(m_dayStartBalance,2)+" dayStartEq="+DoubleToString(m_dayStartEquity,2));
   }

   void ResetWeekly(datetime srv)
   {
      m_weekStartBalance=AccountInfoDouble(ACCOUNT_BALANCE);
      m_weeklyProfit=0; m_weeklyLoss=0;
      m_weekKey=WeekKeyMonday(srv);
      g_mmLog.Info("WEEK_RESET","weekStartBal="+DoubleToString(m_weekStartBalance,2));
   }

   void ResetMonthly(datetime srv)
   {
      m_monthStartBalance=AccountInfoDouble(ACCOUNT_BALANCE);
      m_monthlyProfit=0; m_monthlyLoss=0;
      m_monthKey=MonthKey(srv);
      g_mmLog.Info("MONTH_RESET","monthStartBal="+DoubleToString(m_monthStartBalance,2));
   }

public:
   void Init()
   {
      datetime srv=EffectiveServerTime(0);
      m_startBalance=AccountInfoDouble(ACCOUNT_BALANCE);
      m_dayStartBalance=m_startBalance;
      m_dayStartEquity=AccountInfoDouble(ACCOUNT_EQUITY);
      m_weekStartBalance=m_startBalance;
      m_monthStartBalance=m_startBalance;
      m_peakEquity=AccountInfoDouble(ACCOUNT_EQUITY);
      m_peakBalance=m_startBalance;
      m_dailyProfit=0; m_dailyLoss=0; m_weeklyProfit=0; m_weeklyLoss=0; m_monthlyProfit=0; m_monthlyLoss=0;
      m_dayStart=srv;
      m_dayKey=DayKey(srv); m_weekKey=WeekKeyMonday(srv); m_monthKey=MonthKey(srv);
      m_tradesToday=0; m_consecutiveLosses=0; m_consecutiveWins=0; m_cooldownUntil=0;
      m_countedExposureCount=0; m_countedExposureHead=0; m_hasRules=false;
   }

   // Server-time period sync. Call on tick/timer with TimeTradeServer() (or 0 to resolve).
   // Rolls day/week/month boundaries independently; does not invent historical period data.
   void SyncPeriods(datetime serverTime=0)
   {
      datetime srv=EffectiveServerTime(serverTime);
      int dk=DayKey(srv), wk=WeekKeyMonday(srv), mk=MonthKey(srv);
      bool inited = (m_dayKey!=0 || m_weekKey!=0 || m_monthKey!=0);
      if(!inited)
      {
         m_dayKey=dk; m_weekKey=wk; m_monthKey=mk;
         if(m_dayStart==0) m_dayStart=srv;
         if(m_dayStartBalance<=0) m_dayStartBalance=AccountInfoDouble(ACCOUNT_BALANCE);
         if(m_dayStartEquity<=0) m_dayStartEquity=AccountInfoDouble(ACCOUNT_EQUITY);
         if(m_weekStartBalance<=0) m_weekStartBalance=AccountInfoDouble(ACCOUNT_BALANCE);
         if(m_monthStartBalance<=0) m_monthStartBalance=AccountInfoDouble(ACCOUNT_BALANCE);
         return;
      }
      if(mk!=m_monthKey) ResetMonthly(srv);
      if(wk!=m_weekKey) ResetWeekly(srv);
      if(dk!=m_dayKey) ResetDaily(srv);
   }

   void SetRules(SPropFirmRules &r){m_rules=r;m_hasRules=true;}

   // Compatibility: server-time daily reset.
   void NewDay()
   {
      datetime srv=EffectiveServerTime(0);
      // Ensure higher periods rolled if needed, then force new day baseline/counters.
      SyncPeriods(srv);
      ResetDaily(srv);
   }

   void SyncPeaks(){ SyncPeaksInternal(); }

   // Legacy compatibility (deprecated for Phase 2.3). Does NOT count exposure and does NOT affect period accounting
   // except best-effort daily P/L; prefer RegisterExposureOrder + RecordCompletedTrade.
   void RecordTrade(double profit)
   {
      if(profit>0){m_dailyProfit+=profit; m_consecutiveWins++; m_consecutiveLosses=0;}
      else if(profit<0){ double l=-profit; m_dailyLoss+=l; m_consecutiveLosses++; m_consecutiveWins=0;}
   }

   // Count actual risk-increasing exposure once per entry/order (deduped). Pending orders count only when filled (deal exposure).
   bool RegisterExposureOrder(ulong orderTicket, ulong dealTicket=0)
   {
      ulong key = (orderTicket!=0)?orderTicket:dealTicket;
      if(key==0) return false;
      if(IsExposureOrderCounted(orderTicket, dealTicket)) return false;
      if(m_countedExposureCount < 256)
      {
         int idx = (m_countedExposureHead + m_countedExposureCount) % 256;
         m_countedExposureOrders[idx]=key;
         m_countedExposureCount++;
      }
      else
      {
         // ring fallback: overwrite oldest, keep recent keys; still count exposure
         m_countedExposureOrders[m_countedExposureHead]=key;
         m_countedExposureHead = (m_countedExposureHead + 1) % 256;
      }
      m_tradesToday++;
      return true;
   }

   bool IsExposureOrderCounted(ulong orderTicket, ulong dealTicket=0)
   {
      ulong key = (orderTicket!=0)?orderTicket:dealTicket;
      if(key==0) return false;
      for(int i=0;i<m_countedExposureCount;i++)
      {
         int idx = (m_countedExposureHead + i) % 256;
         if(m_countedExposureOrders[idx]==key) return true;
      }
      return false;
   }

   // Record one completed trade outcome (aggregated realized net = profit+commission+swap) once per trade lifecycle.
   // Updates daily/weekly/monthly realized profit/loss and consecutive streak. No floating P/L.
   void RecordCompletedTrade(double netResult)
   {
      if(!MathIsValidNumber(netResult)) return;
      if(netResult > 0.0)
      {
         m_dailyProfit += netResult;
         m_weeklyProfit += netResult;
         m_monthlyProfit += netResult;
         m_consecutiveWins++;
         m_consecutiveLosses=0;
      }
      else if(netResult < 0.0)
      {
         double l = -netResult;
         m_dailyLoss += l;
         m_weeklyLoss += l;
         m_monthlyLoss += l;
         m_consecutiveLosses++;
         m_consecutiveWins=0;
      }
      else
      {
         // break-even: do not alter streak
      }
   }

   // Apply cooldown-after-losses policy based on current streak. Call after RecordCompletedTrade on loss outcomes.
   void ApplyConsecLossPolicy(int maxConsecLoss, int cooldownMinutes, datetime serverTimeNow=0)
   {
      if(maxConsecLoss<=0) return;
      datetime now=EffectiveServerTime(serverTimeNow);
      if(m_consecutiveLosses >= maxConsecLoss)
      {
         if(cooldownMinutes>0)
         {
            datetime until = now + cooldownMinutes*60;
            if(until > m_cooldownUntil) m_cooldownUntil = until;
         }
         else
         {
            // limit reached with no cooldown configured: block via streak until reset condition handled externally
         }
      }
   }

   // Expire cooldown timer. When a cooldown period ends, clear timer and reset loss streak for a fresh window.
   void UpdateCooldown(datetime serverTimeNow=0)
   {
      if(m_cooldownUntil<=0) return;
      datetime now=EffectiveServerTime(serverTimeNow);
      if(now >= m_cooldownUntil)
      {
         m_cooldownUntil=0;
         m_consecutiveLosses=0;
      }
   }

   double DailyLoss(){return m_dailyLoss;}
   double DailyProfit(){return m_dailyProfit;}
   double WeeklyLoss(){return m_weeklyLoss;}
   double WeeklyProfit(){return m_weeklyProfit;}
   double MonthlyLoss(){return m_monthlyLoss;}
   double MonthlyProfit(){return m_monthlyProfit;}
   int TradesToday(){return m_tradesToday;}
   int ConsecutiveLosses(){return m_consecutiveLosses;}

   double DayStartBalance(){return m_dayStartBalance>0?m_dayStartBalance:AccountInfoDouble(ACCOUNT_BALANCE);}
   double DayStartEquity(){return m_dayStartEquity>0?m_dayStartEquity:AccountInfoDouble(ACCOUNT_EQUITY);}
   double WeekStartBalance(){return m_weekStartBalance>0?m_weekStartBalance:AccountInfoDouble(ACCOUNT_BALANCE);}
   double MonthStartBalance(){return m_monthStartBalance>0?m_monthStartBalance:AccountInfoDouble(ACCOUNT_BALANCE);}
   double PeakEquity(){ SyncPeaksInternal(); return m_peakEquity; }
   double PeakBalance(){ SyncPeaksInternal(); return m_peakBalance; }
   double StartBalance(){ return m_startBalance>0?m_startBalance:AccountInfoDouble(ACCOUNT_BALANCE); }

   double DailyLossPct(double refBalance=0)
   {
      double ref = (refBalance>0)?refBalance:DayStartBalance(); if(ref<=0) ref=AccountInfoDouble(ACCOUNT_BALANCE);
      return (ref>0)?(m_dailyLoss/ref*100.0):0.0;
   }
   double DailyProfitPct(double refBalance=0)
   {
      double ref = (refBalance>0)?refBalance:DayStartBalance(); if(ref<=0) ref=AccountInfoDouble(ACCOUNT_BALANCE);
      return (ref>0)?(m_dailyProfit/ref*100.0):0.0;
   }
   double WeeklyLossPct(double refBalance=0)
   {
      double ref = (refBalance>0)?refBalance:WeekStartBalance(); if(ref<=0) ref=AccountInfoDouble(ACCOUNT_BALANCE);
      return (ref>0)?(m_weeklyLoss/ref*100.0):0.0;
   }
   double MonthlyLossPct(double refBalance=0)
   {
      double ref = (refBalance>0)?refBalance:MonthStartBalance(); if(ref<=0) ref=AccountInfoDouble(ACCOUNT_BALANCE);
      return (ref>0)?(m_monthlyLoss/ref*100.0):0.0;
   }

   double CurrentDrawdownPct()
   {
      SyncPeaksInternal();
      double eq=AccountInfoDouble(ACCOUNT_EQUITY);
      if(m_peakEquity<=0) return 0.0;
      return MathMax(0.0,(m_peakEquity-eq)/m_peakEquity*100.0);
   }

   double RemainingDailyDDMoney(double limitPct)
   {
      if(limitPct<=0) return 0.0;
      double ref = DayStartBalance(); if(ref<=0) ref=AccountInfoDouble(ACCOUNT_BALANCE);
      double allowed = ref * limitPct / 100.0;
      return MathMax(0.0, allowed - m_dailyLoss);
   }
   double RemainingMaxDDMoney(double limitPct, bool fromEquity=true)
   {
      if(limitPct<=0) return 0.0;
      SyncPeaksInternal();
      double ref = fromEquity ? (m_peakEquity>0?m_peakEquity:AccountInfoDouble(ACCOUNT_EQUITY))
                              : (m_startBalance>0?m_startBalance:AccountInfoDouble(ACCOUNT_BALANCE));
      if(ref<=0) return 0.0;
      double eq=AccountInfoDouble(ACCOUNT_EQUITY);
      double allowedLoss = ref * limitPct / 100.0;
      double usedLoss = MathMax(0.0, ref - eq);
      return MathMax(0.0, allowedLoss - usedLoss);
   }

   bool CheckDailyLossLimit(double limitPercent)
   {
      if(limitPercent>0 && DailyLossPct()>=limitPercent) return false;
      if(m_hasRules&&m_rules.maxDailyLoss>0){
         double ref=(m_rules.ddReference==DD_FROM_EQUITY)?DayStartEquity():DayStartBalance();
         if(ref>0 && (m_dailyLoss/ref*100.0)>=m_rules.maxDailyLoss) return false;
      }return true;
   }
   bool CheckDailyProfitLimit(double limitPercent)
   {
      if(limitPercent>0 && DailyProfitPct()>=limitPercent) return false;
      return true;
   }
   bool CheckMaxDrawdown(double maxDDPercent)
   {
      if(maxDDPercent>0 && CurrentDrawdownPct()>=maxDDPercent) return false;
      if(m_hasRules&&m_rules.maxTotalDD>0){
         double eq=AccountInfoDouble(ACCOUNT_EQUITY);
         double ref=(m_rules.ddReference==DD_FROM_EQUITY)?PeakEquity():StartBalance();
         if(ref>0){ double totalDD=(ref-eq)/ref*100.0; if(totalDD>=m_rules.maxTotalDD) return false; }
      }return true;
   }
   bool CheckMaxTradesPerDay(int maxTrades){if(maxTrades>0&&m_tradesToday>=maxTrades)return false;return true;}
   bool CheckConsecutiveLoss(int maxConsecLoss,int cooldownMinutes)
   {
      datetime now=EffectiveServerTime(0);
      UpdateCooldown(now); // expire cooldown and reset streak for a fresh window when due
      if(maxConsecLoss>0 && m_consecutiveLosses>=maxConsecLoss){
         if(cooldownMinutes>0)
         {
            if(m_cooldownUntil==0) m_cooldownUntil=now+cooldownMinutes*60;
            if(now < m_cooldownUntil) return false;
            // cooldown elapsed in this call window
            m_cooldownUntil=0; m_consecutiveLosses=0; return true;
         }
         // no cooldown configured: remain blocked by streak until a winning/completed outcome policy resets it elsewhere
         return false;
      }
      return true;
   }
   bool CheckCooldown()
   {
      datetime now=EffectiveServerTime(0);
      UpdateCooldown(now);
      if(m_cooldownUntil>0 && now < m_cooldownUntil) return false;
      return true;
   }
   void SetCooldown(int minutes){ m_cooldownUntil=EffectiveServerTime(0)+minutes*60; }
   double LotReductionFactor(int consecLosses,double reductionPerLoss=0.5,double floor=0.25)
   { double f=1.0-consecLosses*reductionPerLoss; if(f<floor)f=floor; if(f>1)f=1; return f; }
   double DDRecoveryFactor(double currentDDPercent,double threshold=3.0)
   { if(currentDDPercent<=threshold)return 1.0; return MathMax(0.25,1.0-(currentDDPercent-threshold)*0.1); }
   bool IsWeekendCloseTime(int closeHourFriday=20)
   { MqlDateTime dt;TimeToStruct(TimeCurrent(),dt); if(dt.day_of_week==5&&dt.hour>=closeHourFriday)return true; if(dt.day_of_week==6||dt.day_of_week==0)return true; return false; }
   bool SwapWarning(string symbol,double maxSwapCost=0)
   { double swapLong=SymbolInfoDouble(symbol,SYMBOL_SWAP_LONG);double swapShort=SymbolInfoDouble(symbol,SYMBOL_SWAP_SHORT); if(MathAbs(swapLong)>maxSwapCost||MathAbs(swapShort)>maxSwapCost)return true; return false; }
   bool VirtualSLHit(ulong ticket,double virtualSL)
   { if(!PositionSelectByTicket(ticket))return false; double price=PositionGetDouble(POSITION_PRICE_CURRENT); ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE); if(type==POSITION_TYPE_BUY)return price<=virtualSL; return price>=virtualSL; }
};
#endif
