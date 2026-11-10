//+------------------------------------------------------------------+
//|                                                  LotSizing.mqh   |
//+------------------------------------------------------------------+
#ifndef LOT_SIZING_MQH
#define LOT_SIZING_MQH
#include "../Utils/Common.mqh"

class CLotSizing
{
private:
   SProfile m_profile;
   bool     m_useCommission;
   double   m_commissionPerLot;

   double RiskPercentToLot(string symbol, double riskPercent, double slPoints)
   {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double riskMoney = balance * riskPercent / 100.0;
      return RiskMoneyToLot(symbol, riskMoney, slPoints);
   }
   double RiskMoneyToLot(string symbol, double riskMoney, double slPoints)
   {
      double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      double point     = SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(slPoints <= 0 || tickValue <= 0 || tickSize <= 0 || point <= 0) return 0;
      double slMoneyPerLot = (slPoints * point / tickSize) * tickValue;
      if(m_useCommission) slMoneyPerLot += m_commissionPerLot;
      if(slMoneyPerLot <= 0) return 0;
      return riskMoney / slMoneyPerLot;
   }
public:
   void Init(SProfile &profile, bool useCommission = true, double commissionPerLot = 0)
   {
      m_profile = profile; m_useCommission = useCommission; m_commissionPerLot = commissionPerLot;
   }
   double CalculateLot(string symbol, ENUM_LOT_METHOD method, double value, double slPoints, double atrValue = 0, double ddScale = 1.0)
   {
      double lot = 0;
      switch(method)
      {
         case LOT_FIXED: lot = value; break;
         case LOT_RISK_PERCENT: lot = RiskPercentToLot(symbol, value, slPoints); break;
         case LOT_RISK_MONEY: lot = RiskMoneyToLot(symbol, value, slPoints); break;
         case LOT_ATR_BASED:
         {
            double atrPts = (atrValue > 0) ? PriceToPoints(symbol, atrValue) : slPoints;
            if(atrPts <= 0) atrPts = slPoints;
            lot = RiskPercentToLot(symbol, m_profile.maxRiskPercent, atrPts);
            break;
         }
         case LOT_KELLY:
         {
            // Kelly: f = (bp - q)/b ; simplified using winRate & avgRR from profile value
            double winRate = value; // value as winrate 0..1
            double rr = (m_profile.tpValue > 0 && m_profile.slValue > 0) ? (m_profile.tpValue / m_profile.slValue) : 1.0;
            double q = 1.0 - winRate;
            double kelly = (winRate * rr - q) / rr;
            if(kelly < 0) kelly = 0;
            kelly = MathMin(kelly, 0.25); // cap
            lot = RiskPercentToLot(symbol, kelly * 100.0, slPoints);
            break;
         }
      }
      lot *= ddScale;
      // min/max risk clamp
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double minLot = m_profile.minRiskPercent > 0 ? RiskPercentToLot(symbol, m_profile.minRiskPercent, slPoints) : SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double maxLot = m_profile.maxRiskPercent > 0 ? RiskPercentToLot(symbol, m_profile.maxRiskPercent, slPoints) : SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      lot = MathMax(minLot, MathMin(maxLot, lot));
      return NormalizeLot(symbol, lot);
   }
   double DDScalingFactor(double currentDDPercent, double threshold = 5.0, double factor = 0.5)
   {
      if(currentDDPercent <= threshold) return 1.0;
      return factor;
   }
};
#endif
