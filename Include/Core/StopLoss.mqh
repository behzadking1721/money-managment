//+------------------------------------------------------------------+
//|                                                     StopLoss.mqh |
//+------------------------------------------------------------------+
#ifndef STOP_LOSS_MQH
#define STOP_LOSS_MQH
#include "../Utils/Common.mqh"

class CStopLoss
{
public:
   double CalculateSL(string symbol, ENUM_SL_METHOD method, double value, double entryPrice, bool isBuy, ENUM_TIMEFRAMES tf = PERIOD_H1, int atrPeriod = 14)
   {
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      double atr = GetATR(symbol, tf, atrPeriod);
      double sl = 0;
      switch(method)
      {
         case SL_FIXED_POINTS:
            sl = isBuy ? entryPrice - value * point : entryPrice + value * point;
            break;
         case SL_ATR:
            sl = isBuy ? entryPrice - value * atr : entryPrice + value * atr;
            break;
         case SL_SWING:
         {
            // swing low/high over last N bars
            int bars = (int)value; if(bars < 2) bars = 10;
            double ext = isBuy ? 1e18 : -1e18;
            for(int i = 1; i <= bars; i++)
            {
               if(isBuy) ext = MathMin(ext, iLow(symbol, tf, i));
               else ext = MathMax(ext, iHigh(symbol, tf, i));
            }
            double buf = GetATR(symbol, tf, 14) * 0.1;
            sl = isBuy ? ext - buf : ext + buf;
            break;
         }
         case SL_STRUCTURE:
         {
            // structure: last significant high/low
            sl = isBuy ? iLow(symbol, tf, 1) : iHigh(symbol, tf, 1);
            break;
         }
         case SL_PERCENT:
         {
            double pct = value / 100.0;
            sl = isBuy ? entryPrice * (1.0 - pct) : entryPrice * (1.0 + pct);
            break;
         }
      }
      return NormalizeDouble(sl, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
   }
   double SLToPoints(string symbol, double entryPrice, double slPrice)
   {
      return MathAbs(entryPrice - slPrice) / SymbolInfoDouble(symbol, SYMBOL_POINT);
   }
};
#endif
