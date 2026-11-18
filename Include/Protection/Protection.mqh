#ifndef PROTECTION_MQH
#define PROTECTION_MQH
#include "../Utils/Common.mqh"
#include "../Core/Logger.mqh"

class CProtection
{
private:
   double   m_startBalance;
   double   m_dayStartBalance;
   double   m_dayStartEquity;
   double   m_peakEquity;
   double   m_peakBalance;
   double   m_dailyProfit;
   double   m_dailyLoss;
   datetime m_dayStart;
   int      m_tradesToday;
   int      m_consecutiveLosses;
   int      m_consecutiveWins;
   datetime m_cooldownUntil;
   SPropFirmRules m_rules; bool m_hasRules;

   double RefBalance(){ return (m_startBalance>0)?m_startBalance:AccountInfoDouble(ACCOUNT_BALANCE); }

public:
   void Init()
   {
      m_startBalance=AccountInfoDouble(ACCOUNT_BALANCE);
      m_dayStartBalance=m_startBalance;
      m_dayStartEquity=AccountInfoDouble(ACCOUNT_EQUITY);
      m_peakEquity=AccountInfoDouble(ACCOUNT_EQUITY);
      m_peakBalance=m_startBalance;
      m_dailyProfit=0; m_dailyLoss=0; m_dayStart=TimeCurrent();
      m_tradesToday=0; m_consecutiveLosses=0; m_consecutiveWins=0; m_cooldownUntil=0; m_hasRules=false;
   }
   void SetRules(SPropFirmRules &r){m_rules=r;m_hasRules=true;}
   void NewDay()
   {
      m_dayStartBalance=AccountInfoDouble(ACCOUNT_BALANCE);
      m_dayStartEquity=AccountInfoDouble(ACCOUNT_EQUITY);
      m_dailyProfit=0; m_dailyLoss=0; m_dayStart=TimeCurrent(); m_tradesToday=0;
      // keep overall peak for max DD tracking
      double eq=AccountInfoDouble(ACCOUNT_EQUITY); if(eq>m_peakEquity) m_peakEquity=eq;
      double bal=AccountInfoDouble(ACCOUNT_BALANCE); if(bal>m_peakBalance) m_peakBalance=bal;
      g_mmLog.Info("DAY_RESET","dayStartBal="+DoubleToString(m_dayStartBalance,2)+" dayStartEq="+DoubleToString(m_dayStartEquity,2));
   }
   void SyncPeaks()
   {
      double eq=AccountInfoDouble(ACCOUNT_EQUITY); if(eq>m_peakEquity) m_peakEquity=eq;
      double bal=AccountInfoDouble(ACCOUNT_BALANCE); if(bal>m_peakBalance) m_peakBalance=bal;
   }
   void RecordTrade(double profit)
   {
      if(profit>0){m_dailyProfit+=profit;m_consecutiveWins++;m_consecutiveLosses=0;}
      else if(profit<0){m_dailyLoss+=-profit;m_consecutiveLosses++;m_consecutiveWins=0;}
      m_tradesToday++;
   }

   double DailyLoss(){return m_dailyLoss;}
   double DailyProfit(){return m_dailyProfit;}
   int TradesToday(){return m_tradesToday;}
   int ConsecutiveLosses(){return m_consecutiveLosses;}
   double DayStartBalance(){return m_dayStartBalance>0?m_dayStartBalance:AccountInfoDouble(ACCOUNT_BALANCE);}
   double DayStartEquity(){return m_dayStartEquity>0?m_dayStartEquity:AccountInfoDouble(ACCOUNT_EQUITY);}
   double PeakEquity(){ SyncPeaks(); return m_peakEquity; }
   double PeakBalance(){ SyncPeaks(); return m_peakBalance; }
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
   double CurrentDrawdownPct()
   {
      SyncPeaks();
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
      SyncPeaks();
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
      if(maxConsecLoss>0&&m_consecutiveLosses>=maxConsecLoss){
         if(m_cooldownUntil==0)m_cooldownUntil=TimeCurrent()+cooldownMinutes*60;
         if(TimeCurrent()<m_cooldownUntil)return false;
         m_consecutiveLosses=0;m_cooldownUntil=0;
      }return true;
   }
   bool CheckCooldown(){if(m_cooldownUntil>0&&TimeCurrent()<m_cooldownUntil)return false;return true;}
   void SetCooldown(int minutes){m_cooldownUntil=TimeCurrent()+minutes*60;}
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
