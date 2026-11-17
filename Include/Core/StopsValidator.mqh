//+------------------------------------------------------------------+
//|                                              StopsValidator.mqh  |
//|        Phase 2: stops/freeze/margin/price validity checks        |
//+------------------------------------------------------------------+
#ifndef MM_STOPS_VALIDATOR_MQH
#define MM_STOPS_VALIDATOR_MQH

#include "Contracts.mqh"

struct MM_StopsCheck
{
   bool ok;
   bool blocked;
   string reasonCode;
   string messageEN;
   string warnings[8];
   int warnCount;
   void Reset(){ ok=true; blocked=false; reasonCode=""; messageEN=""; warnCount=0; }
   void Warn(const string w){ if(warnCount<8) warnings[warnCount++]=w; }
};

class CStopsValidator
{
public:
   double MinStopDistancePrice(const string symbol)
   {
      int stopsLevel = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
      int freezeLevel = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL);
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      int level = MathMax(stopsLevel, freezeLevel);
      if(level < 0) level = 0;
      return level * point;
   }

   // Infer pending order type from side and entry vs current market (auto-detect for drag). Returns false if ambiguous/market.
   bool InferPendingType(bool isBuy, double entry, double currentAsk, double currentBid, ENUM_ORDER_TYPE &outType)
   {
      if(isBuy)
      {
         if(entry < currentBid){ outType=ORDER_TYPE_BUY_LIMIT; return true; }
         if(entry > currentAsk){ outType=ORDER_TYPE_BUY_STOP; return true; }
         return false; // market zone
      }
      else
      {
         if(entry > currentAsk){ outType=ORDER_TYPE_SELL_LIMIT; return true; }
         if(entry < currentBid){ outType=ORDER_TYPE_SELL_STOP; return true; }
         return false;
      }
   }

   bool ValidatePendingEntry(const string symbol, ENUM_ORDER_TYPE type, double entry, double currentAsk, double currentBid, MM_StopsCheck &out)
   {
      out.Reset();
      double minDist = MinStopDistancePrice(symbol);
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(point<=0){ out.ok=false; out.blocked=true; out.reasonCode="INVALID_SYMBOL"; out.messageEN="Invalid symbol point"; return false; }
      switch(type)
      {
         case ORDER_TYPE_BUY_LIMIT:  if(!(entry < currentAsk - minDist)){ out.ok=false; out.blocked=true; out.reasonCode="INVALID_STOPS"; out.messageEN="BuyLimit entry too close/invalid vs Ask"; } break;
         case ORDER_TYPE_SELL_LIMIT: if(!(entry > currentBid + minDist)){ out.ok=false; out.blocked=true; out.reasonCode="INVALID_STOPS"; out.messageEN="SellLimit entry too close/invalid vs Bid"; } break;
         case ORDER_TYPE_BUY_STOP:   if(!(entry > currentAsk + minDist)){ out.ok=false; out.blocked=true; out.reasonCode="INVALID_STOPS"; out.messageEN="BuyStop entry too close/invalid vs Ask"; } break;
         case ORDER_TYPE_SELL_STOP:  if(!(entry < currentBid - minDist)){ out.ok=false; out.blocked=true; out.reasonCode="INVALID_STOPS"; out.messageEN="SellStop entry too close/invalid vs Bid"; } break;
         default: break;
      }
      return out.ok;
   }

   bool ValidateSLTP(const string symbol, bool isBuy, double entry, double sl, double tp, MM_StopsCheck &out)
   {
      out.Reset();
      double minDist = MinStopDistancePrice(symbol);
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(point<=0){ out.ok=false; out.blocked=true; out.reasonCode="INVALID_SYMBOL"; out.messageEN="Invalid symbol point"; return false; }
      if(sl<=0){ out.ok=false; out.blocked=true; out.reasonCode="NO_SL"; out.messageEN="Stop loss required"; return false; }
      if(isBuy)
      {
         if(!(sl < entry - minDist + 1e-12)){ out.ok=false; out.blocked=true; out.reasonCode="INVALID_STOPS"; out.messageEN="SL too close/above entry for Buy"; }
         if(tp>0 && !(tp > entry + minDist - 1e-12)){ out.ok=false; out.blocked=true; out.reasonCode="INVALID_STOPS"; out.messageEN="TP too close/below entry for Buy"; }
      }
      else
      {
         if(!(sl > entry + minDist - 1e-12)){ out.ok=false; out.blocked=true; out.reasonCode="INVALID_STOPS"; out.messageEN="SL too close/below entry for Sell"; }
         if(tp>0 && !(tp < entry - minDist + 1e-12)){ out.ok=false; out.blocked=true; out.reasonCode="INVALID_STOPS"; out.messageEN="TP too close/above entry for Sell"; }
      }
      if(out.ok)
      {
         double slDist=MathAbs(entry-sl);
         if(slDist <= minDist + 2*point) out.Warn("SL near broker minimum distance");
      }
      return out.ok;
   }

   bool ValidateMargin(const string symbol, ENUM_ORDER_TYPE orderType, double volume, double price, MM_StopsCheck &out)
   {
      out.Reset();
      double margin=0.0;
      if(!OrderCalcMargin(orderType, symbol, volume, price, margin))
      {
         out.ok=false; out.blocked=true; out.reasonCode="MARGIN_CALC_FAIL"; out.messageEN="OrderCalcMargin failed";
         return false;
      }
      double free=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(margin > free)
      {
         out.ok=false; out.blocked=true; out.reasonCode="NO_MONEY"; out.messageEN="Insufficient free margin";
         return false;
      }
      if(free>0 && margin/free > 0.8) out.Warn("High margin usage (>80% free)");
      return true;
   }

   // Full pre-send validation for a TradePlan. Returns first blocking reason; accumulates warnings.
   bool ValidatePlan(const MM_TradePlan &plan, MM_StopsCheck &out)
   {
      out.Reset();
      string sym=plan.symbol;
      double ask=SymbolInfoDouble(sym,SYMBOL_ASK), bid=SymbolInfoDouble(sym,SYMBOL_BID);
      bool isBuy = (plan.side==POSITION_TYPE_BUY);
      double price = plan.entryPrice>0?plan.entryPrice:(isBuy?ask:bid);
      if(plan.isPending)
      {
         if(!ValidatePendingEntry(sym, plan.orderType, plan.entryPrice, ask, bid, out)) return false;
      }
      double tp = plan.tpCount>0?plan.tpPrice[0]:0;
      if(!ValidateSLTP(sym, isBuy, price, plan.slPrice, tp, out)) return false;
      ENUM_ORDER_TYPE ot = plan.isPending ? plan.orderType : (isBuy?ORDER_TYPE_BUY:ORDER_TYPE_SELL);
      if(!ValidateMargin(sym, ot, plan.lot, price, out)) return false;
      // volume bounds
      double vmin=SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN), vmax=SymbolInfoDouble(sym,SYMBOL_VOLUME_MAX);
      if(plan.lot < vmin || plan.lot > vmax){ out.ok=false; out.blocked=true; out.reasonCode="INVALID_VOLUME"; out.messageEN="Lot outside symbol volume limits"; return false; }
      if(SymbolInfoInteger(sym,SYMBOL_TRADE_MODE)==SYMBOL_TRADE_MODE_DISABLED){ out.ok=false; out.blocked=true; out.reasonCode="TRADE_DISABLED"; out.messageEN="Trading disabled for symbol"; return false; }
      return true;
   }
};

#endif // MM_STOPS_VALIDATOR_MQH
