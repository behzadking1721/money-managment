#ifndef PROTECTION_MQH
#define PROTECTION_MQH
#include "../Utils/Common.mqh"
class CProtection
{
private:
   double m_startBalance; double m_startEquity; double m_peakEquity; double m_dailyProfit; double m_dailyLoss;
   datetime m_dayStart; int m_tradesToday; int m_consecutiveLosses; int m_consecutiveWins;
   datetime m_cooldownUntil; // seconds timestamp
   SPropFirmRules m_rules; bool m_hasRules;
public:
   void Init(){m_startBalance=AccountInfoDouble(ACCOUNT_BALANCE);m_startEquity=AccountInfoDouble(ACCOUNT_EQUITY);m_peakEquity=m_startEquity;m_dailyProfit=0;m_dailyLoss=0;m_dayStart=TimeCurrent();m_tradesToday=0;m_consecutiveLosses=0;m_consecutiveWins=0;m_cooldownUntil=0;m_hasRules=false;}
   void SetRules(SPropFirmRules &r){m_rules=r;m_hasRules=true;}
   void NewDay(){m_startBalance=AccountInfoDouble(ACCOUNT_BALANCE);m_startEquity=AccountInfoDouble(ACCOUNT_EQUITY);m_peakEquity=m_startEquity;m_dailyProfit=0;m_dailyLoss=0;m_dayStart=TimeCurrent();m_tradesToday=0;}
   void RecordTrade(double profit)
   {
      if(profit>0){m_dailyProfit+=profit;m_consecutiveWins++;m_consecutiveLosses=0;}
      else if(profit<0){m_dailyLoss+=-profit;m_consecutiveLosses++;m_consecutiveWins=0;}
      m_tradesToday++;
   }
   bool CheckDailyLossLimit(double limitPercent)
   {
      double bal=AccountInfoDouble(ACCOUNT_BALANCE);double lossPct=m_dailyLoss/bal*100.0;
      if(lossPct>=limitPercent)return false;
      if(m_hasRules&&m_rules.maxDailyLoss>0){
         double ref=(m_rules.ddReference==DD_FROM_EQUITY)?AccountInfoDouble(ACCOUNT_EQUITY):bal;
         double dd=m_dailyLoss/ref*100.0;if(dd>=m_rules.maxDailyLoss)return false;
      }return true;
   }
   bool CheckDailyProfitLimit(double limitPercent)
   {
      double bal=AccountInfoDouble(ACCOUNT_BALANCE);double profitPct=m_dailyProfit/bal*100.0;
      if(limitPercent>0&&profitPct>=limitPercent)return false;return true;
   }
   bool CheckMaxDrawdown(double maxDDPercent)
   {
      double eq=AccountInfoDouble(ACCOUNT_EQUITY);
      if(eq>m_peakEquity)m_peakEquity=eq;
      double dd=(m_peakEquity-eq)/m_peakEquity*100.0;
      if(dd>=maxDDPercent)return false;
      if(m_hasRules&&m_rules.maxTotalDD>0){
         double ref=(m_rules.ddReference==DD_FROM_EQUITY)?m_peakEquity:m_startBalance;
         double totalDD=(ref-eq)/ref*100.0;if(totalDD>=m_rules.maxTotalDD)return false;
      }return true;
   }
   bool CheckMaxTradesPerDay(int maxTrades){if(maxTrades>0&&m_tradesToday>=maxTrades)return false;return true;}
   bool CheckConsecutiveLoss(int maxConsecLoss,int cooldownMinutes)
   {
      if(maxConsecLoss>0&&m_consecutiveLosses>=maxConsecLoss){
         if(m_cooldownUntil==0)m_cooldownUntil=TimeCurrent()+cooldownMinutes*60;
         if(TimeCurrent()<m_cooldownUntil)return false;
         // reset after cooldown
         m_consecutiveLosses=0;m_cooldownUntil=0;
      }return true;
   }
   bool CheckCooldown(){if(m_cooldownUntil>0&&TimeCurrent()<m_cooldownUntil)return false;return true;}
   void SetCooldown(int minutes){m_cooldownUntil=TimeCurrent()+minutes*60;}
   // Lot reduction after loss
   double LotReductionFactor(int consecLosses,double reductionPerLoss=0.5,double floor=0.25)
   {
      double f=1.0-consecLosses*reductionPerLoss;
      if(f<floor)f=floor;if(f>1)f=1;return f;
   }
   // DD recovery mode: reduce risk when in drawdown
   double DDRecoveryFactor(double currentDDPercent,double threshold=3.0)
   {
      if(currentDDPercent<=threshold)return 1.0;
      return MathMax(0.25,1.0-(currentDDPercent-threshold)*0.1);
   }
   // Weekend auto-close
   bool IsWeekendCloseTime(int closeHourFriday=20)
   {
      MqlDateTime dt;TimeToStruct(TimeCurrent(),dt);
      if(dt.day_of_week==5&&dt.hour>=closeHourFriday)return true;
      if(dt.day_of_week==6||dt.day_of_week==0)return true;
      return false;
   }
   // Swap warning
   bool SwapWarning(string symbol,double maxSwapCost=0)
   {
      double swapLong=SymbolInfoDouble(symbol,SYMBOL_SWAP_LONG);double swapShort=SymbolInfoDouble(symbol,SYMBOL_SWAP_SHORT);
      if(MathAbs(swapLong)>maxSwapCost||MathAbs(swapShort)>maxSwapCost)return true;
      return false;
   }
   // Virtual SL/TP handled by monitor
   bool VirtualSLHit(ulong ticket,double virtualSL)
   {
      if(!PositionSelectByTicket(ticket))return false;
      double price=PositionGetDouble(POSITION_PRICE_CURRENT);
      ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(type==POSITION_TYPE_BUY)return price<=virtualSL;
      return price>=virtualSL;
   }
   int TradesToday(){return m_tradesToday;}
   int ConsecutiveLosses(){return m_consecutiveLosses;}
   double DailyProfit(){return m_dailyProfit;}
   double DailyLoss(){return m_dailyLoss;}
};
#endif
