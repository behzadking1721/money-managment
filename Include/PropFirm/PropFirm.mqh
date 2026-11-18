#ifndef PROP_FIRM_MQH
#define PROP_FIRM_MQH
#include "../Utils/Common.mqh"
#include "../Protection/Protection.mqh"
class CPropFirm
{
private:
   SPropFirmRules m_rules; bool m_enabled;
   datetime m_firstTradeDay; int m_tradingDays; double m_startBalance; double m_peakEquity;
   double m_dailyProfits[]; int m_dailyCount;
public:
   void Init(){m_enabled=false;m_firstTradeDay=0;m_tradingDays=0;m_startBalance=AccountInfoDouble(ACCOUNT_BALANCE);m_peakEquity=AccountInfoDouble(ACCOUNT_EQUITY);ArrayResize(m_dailyProfits,0);m_dailyCount=0;}
   void Enable(SPropFirmRules &r){m_rules=r;m_enabled=true;m_startBalance=AccountInfoDouble(ACCOUNT_BALANCE);m_peakEquity=AccountInfoDouble(ACCOUNT_EQUITY);}
   void Disable(){m_enabled=false;}
   bool IsEnabled(){return m_enabled;}
   // Presets
   void LoadPreset(string name,SPropFirmRules &r)
   {
      r.name=name;
      if(name=="FTMO")
      {r.mode=PROP_CHALLENGE;r.ddReference=DD_FROM_EQUITY;r.maxDailyLoss=5;r.maxTotalDD=10;r.profitTarget=10;r.minTradingDays=4;r.consistencyPercent=0;r.maxPositionSize=0;r.newsBlackout=true;r.weekendClose=true;}
      else if(name=="MFF")
      {r.mode=PROP_CHALLENGE;r.ddReference=DD_FROM_BALANCE;r.maxDailyLoss=5;r.maxTotalDD=12;r.profitTarget=8;r.minTradingDays=5;r.consistencyPercent=40;r.maxPositionSize=0;r.newsBlackout=true;r.weekendClose=true;}
      else if(name=="FundedNext")
      {r.mode=PROP_FUNDED;r.ddReference=DD_FROM_EQUITY;r.maxDailyLoss=5;r.maxTotalDD=10;r.profitTarget=0;r.minTradingDays=0;r.consistencyPercent=0;r.maxPositionSize=0;r.newsBlackout=true;r.weekendClose=false;}
      else if(name=="The5ers")
      {r.mode=PROP_CHALLENGE;r.ddReference=DD_FROM_BALANCE;r.maxDailyLoss=5;r.maxTotalDD=10;r.profitTarget=6;r.minTradingDays=0;r.consistencyPercent=0;r.maxPositionSize=2;r.newsBlackout=false;r.weekendClose=false;}
   }
   bool CheckConsistency(double todayProfit)
   {
      if(!m_enabled||m_rules.consistencyPercent<=0)return true;
      // consistency: no single day > X% of total profit
      double total=0;for(int i=0;i<m_dailyCount;i++)total+=m_dailyProfits[i];total+=todayProfit;
      if(total<=0)return true;
      double maxDay=MathMax(todayProfit,0);for(int i=0;i<m_dailyCount;i++)if(m_dailyProfits[i]>maxDay)maxDay=m_dailyProfits[i];
      if(maxDay/total*100.0>m_rules.consistencyPercent)return false;
      return true;
   }
   void RecordTradingDay(double dayProfit)
   {
      if(!m_enabled)return;
      // record day profit and resize
      if(m_dailyCount>=ArraySize(m_dailyProfits))ArrayResize(m_dailyProfits,m_dailyCount+1);
      m_dailyProfits[m_dailyCount++]=dayProfit;
      MqlDateTime dt;TimeToStruct(TimeCurrent(),dt);static int lastDay=-1;
      if(dt.day!=lastDay){m_tradingDays++;lastDay=dt.day;}
   }
   int TradingDays(){return m_tradingDays;}
   bool MinTradingDaysMet(){if(!m_enabled||m_rules.minTradingDays<=0)return true;return m_tradingDays>=m_rules.minTradingDays;}
   bool ProfitTargetMet()
   {
      if(!m_enabled||m_rules.profitTarget<=0)return true;
      double profit=(AccountInfoDouble(ACCOUNT_BALANCE)-m_startBalance)/m_startBalance*100.0;
      return profit>=m_rules.profitTarget;
   }
   bool CheckMaxPositionSize(double lot,string symbol)
   {
      if(!m_enabled||m_rules.maxPositionSize<=0)return true;
      double bal=AccountInfoDouble(ACCOUNT_BALANCE);
      // rough: lot value vs balance
      double contractSize=SymbolInfoDouble(symbol,SYMBOL_TRADE_CONTRACT_SIZE);
      double price=SymbolInfoDouble(symbol,SYMBOL_BID);
      double value=lot*contractSize*price;
      if(value/bal*100.0>m_rules.maxPositionSize)return false;
      return true;
   }
   // Correlation warning: simple check by counting positions on correlated symbols
   bool CorrelationWarning(string symbol)
   {
      if(!m_enabled)return false;
      // placeholder: warn if >3 positions on same base currency
      string base=StringSubstr(symbol,0,3);
      int cnt=0;
      for(int i=0;i<PositionsTotal();i++){
         ulong t=PositionGetTicket(i);if(t==0)continue;
         string s=PositionGetString(POSITION_SYMBOL);
         if(StringSubstr(s,0,3)==base)cnt++;
      }
      return cnt>=3;
   }
   SPropFirmRules GetRules(){return m_rules;}
   void SetRules(const SPropFirmRules &r){ m_rules=r; m_enabled=true; }
   void SyncBaseline(double startBalance,double peakEquity){ if(startBalance>0) m_startBalance=startBalance; if(peakEquity>m_peakEquity) m_peakEquity=peakEquity; }

   double DailyLossRef(double dayStartBalance,double dayStartEquity)
   {
      if(m_rules.ddReference==DD_FROM_EQUITY) return (dayStartEquity>0)?dayStartEquity:AccountInfoDouble(ACCOUNT_EQUITY);
      return (dayStartBalance>0)?dayStartBalance:AccountInfoDouble(ACCOUNT_BALANCE);
   }
   double MaxDDRef(double startBalance,double peakEquity)
   {
      if(m_rules.ddReference==DD_FROM_EQUITY) return (peakEquity>0)?peakEquity:AccountInfoDouble(ACCOUNT_EQUITY);
      return (startBalance>0)?startBalance:AccountInfoDouble(ACCOUNT_BALANCE);
   }
   double DailyLossUsedPct(double dailyLossMoney,double dayStartBalance,double dayStartEquity)
   {
      if(!m_enabled || m_rules.maxDailyLoss<=0) return 0.0;
      double ref=DailyLossRef(dayStartBalance,dayStartEquity); if(ref<=0) return 0.0;
      return (dailyLossMoney/ref)*100.0;
   }
   double TotalDDUsedPct(double currentEquity,double peakEquity,double startBalance)
   {
      if(!m_enabled || m_rules.maxTotalDD<=0) return 0.0;
      double ref=MaxDDRef(startBalance,peakEquity); if(ref<=0) return 0.0;
      return MathMax(0.0,(ref-currentEquity)/ref*100.0);
   }
   double RemainingDailyDDMoney(double dailyLossMoney,double dayStartBalance,double dayStartEquity)
   {
      if(!m_enabled || m_rules.maxDailyLoss<=0) return 0.0;
      double ref=DailyLossRef(dayStartBalance,dayStartEquity); if(ref<=0) return 0.0;
      return MathMax(0.0, ref*m_rules.maxDailyLoss/100.0 - dailyLossMoney);
   }
   double RemainingMaxDDMoney(double currentEquity,double peakEquity,double startBalance)
   {
      if(!m_enabled || m_rules.maxTotalDD<=0) return 0.0;
      double ref=MaxDDRef(startBalance,peakEquity); if(ref<=0) return 0.0;
      double allowed=ref*m_rules.maxTotalDD/100.0;
      double used=MathMax(0.0, ref-currentEquity);
      return MathMax(0.0, allowed-used);
   }
};
#endif
