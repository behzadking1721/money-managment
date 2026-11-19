//+------------------------------------------------------------------+
//|                                         StopsValidator_Test.mq5  |
//|        Phase 2/2.2: stops/freeze/margin/entry/symbol checks      |
//+------------------------------------------------------------------+
#property script_show_inputs
#include "..\\..\\Include\\Core\\StopsValidator.mqh"

int g_fail=0;
void Assert(bool c,const string n){ if(!c){Print("FAIL: ",n); g_fail++;} else Print("OK: ",n); }

void OnStart()
{
   g_fail=0;
   CStopsValidator v; MM_StopsCheck chk; string sym=_Symbol;
   double ask=SymbolInfoDouble(sym,SYMBOL_ASK), bid=SymbolInfoDouble(sym,SYMBOL_BID);
   double point=SymbolInfoDouble(sym,SYMBOL_POINT);
   double minDist=v.MinStopDistancePrice(sym);
   double far = minDist + 200*point; if(far < 200*point) far = 200*point;

   // Buy market SL/TP valid
   bool ok=v.ValidateSLTP(sym,true,ask,ask-far,ask+far*2,chk);
   Assert(ok && !chk.blocked,"buy SLTP valid");

   // SL too close
   ok=v.ValidateSLTP(sym,true,ask,ask-point,ask+far,chk);
   Assert(!ok && chk.blocked && chk.reasonCode=="INVALID_STOPS","SL too close blocked");

   // No SL
   ok=v.ValidateSLTP(sym,true,ask,0,ask+far,chk);
   Assert(!ok && chk.reasonCode=="NO_SL","no SL blocked");

   // Sell SL/TP valid
   ok=v.ValidateSLTP(sym,false,bid,bid+far,bid-far*2,chk);
   Assert(ok,"sell SLTP valid");

   // Pending inference
   ENUM_ORDER_TYPE t;
   Assert(v.InferPendingType(true, bid-far, ask,bid,t) && t==ORDER_TYPE_BUY_LIMIT,"infer buy limit");
   Assert(v.InferPendingType(true, ask+far, ask,bid,t) && t==ORDER_TYPE_BUY_STOP,"infer buy stop");
   Assert(v.InferPendingType(false, ask+far, ask,bid,t) && t==ORDER_TYPE_SELL_LIMIT,"infer sell limit");
   Assert(v.InferPendingType(false, bid-far, ask,bid,t) && t==ORDER_TYPE_SELL_STOP,"infer sell stop");

   // Margin check reasonable lot
   double vmin=SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN);
   ok=v.ValidateMargin(sym,ORDER_TYPE_BUY,vmin,ask,chk);
   Assert(ok,"margin ok for min lot");

   // Plan validation uses correct market/pending context and enforces margin/volume
   MM_TradePlan plan; plan.Reset(); plan.symbol=sym; plan.side=POSITION_TYPE_BUY; plan.isPending=false; plan.orderType=ORDER_TYPE_BUY;
   plan.entryPrice=ask; plan.slPrice=ask-far; plan.tpCount=1; plan.tpPrice[0]=ask+far*2; plan.lot=vmin;
   ok = v.ValidatePlan(plan, chk);
   Assert(ok, "market plan valid for min lot");

   // Pending plan with correct type/price context
   MM_TradePlan pp=plan; pp.isPending=true; pp.orderType=ORDER_TYPE_BUY_LIMIT; pp.entryPrice=bid-far; pp.slPrice=pp.entryPrice-far; pp.tpPrice[0]=pp.entryPrice+far*2;
   if(pp.entryPrice < ask)
   {
      ok = v.ValidatePlan(pp, chk);
      Assert(ok || chk.reasonCode=="INVALID_STOPS" || chk.reasonCode=="NO_MONEY" || chk.reasonCode=="MARGIN_CALC_FAIL" || chk.reasonCode=="NO_PRICE", "pending plan validated with consistent reason when blocked");
   }

   // Volume outside limits blocked
   MM_TradePlan pv=plan; pv.lot = SymbolInfoDouble(sym,SYMBOL_VOLUME_MAX) * 10.0;
   ok = v.ValidatePlan(pv, chk);
   Assert(!ok && chk.reasonCode=="INVALID_VOLUME", "volume outside limits blocked");

   if(g_fail==0) Print("StopsValidator_Test: ALL PASS"); else Print("StopsValidator_Test: FAIL count=",g_fail);
}
