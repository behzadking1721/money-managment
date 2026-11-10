//+------------------------------------------------------------------+
//|                                                  TakeProfit.mqh  |
//+------------------------------------------------------------------+
#ifndef TAKE_PROFIT_MQH
#define TAKE_PROFIT_MQH
#include "../Utils/Common.mqh"

class CTakeProfit
{
public:
   void CalculateTPs(string symbol, ENUM_TP_METHOD method, double value, double entryPrice, double slPrice, bool isBuy, double &tp1, double &tp2, double &tp3, int &count)
   {
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      double atr = GetATR(symbol, PERIOD_H1, 14);
      double slDist = MathAbs(entryPrice - slPrice);
      count = 3;
      switch(method)
      {
         case TP_FIXED_POINTS:
            tp1 = isBuy ? entryPrice + value * point : entryPrice - value * point;
            tp2 = isBuy ? entryPrice + value * 2 * point : entryPrice - value * 2 * point;
            tp3 = isBuy ? entryPrice + value * 3 * point : entryPrice - value * 3 * point;
            break;
         case TP_ATR:
            tp1 = isBuy ? entryPrice + value * atr : entryPrice - value * atr;
            tp2 = isBuy ? entryPrice + value * 2 * atr : entryPrice - value * 2 * atr;
            tp3 = isBuy ? entryPrice + value * 3 * atr : entryPrice - value * 3 * atr;
            break;
         case TP_RR:
         {
            double rr = value; // R multiple
            tp1 = isBuy ? entryPrice + slDist * rr : entryPrice - slDist * rr;
            tp2 = isBuy ? entryPrice + slDist * rr * 2 : entryPrice - slDist * rr * 2;
            tp3 = isBuy ? entryPrice + slDist * rr * 3 : entryPrice - slDist * rr * 3;
            break;
         }
         case TP_STRUCTURE:
            tp1 = isBuy ? iHigh(symbol, PERIOD_H1, 1) : iLow(symbol, PERIOD_H1, 1);
            tp2 = isBuy ? iHigh(symbol, PERIOD_H4, 1) : iLow(symbol, PERIOD_H4, 1);
            tp3 = tp2;
            count = 2;
            break;
      }
      int dig = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      tp1 = NormalizeDouble(tp1, dig); tp2 = NormalizeDouble(tp2, dig); tp3 = NormalizeDouble(tp3, dig);
   }
};
#endif
