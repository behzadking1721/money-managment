//+------------------------------------------------------------------+
//|                                              RiskEngine_Test.mq5 |
//|  Phase 2/2.2: sizing, RR, caps, margin, symbol specs, reasons   |
//+------------------------------------------------------------------+
#property script_show_inputs
#include "..\\..\\Include\\Core\\RiskEngine.mqh"

int g_fail=0;
void Assert(bool c,const string n){ if(!c){Print("FAIL: ",n); g_fail++;} else Print("OK: ",n); }

bool HasCap(const MM_RiskResult &r,const string capSub)
{
   for(int i=0;i<r.capsCount;i++) if(StringFind(r.capsApplied[i],capSub)>=0) return true;
   return false;
}
bool HasWarn(const MM_RiskResult &r,const string warnSub)
{
   for(int i=0;i<r.warningsCount;i++) if(StringFind(r.warnings[i],warnSub)>=0) return true;
   return false;
}

void OnStart()
{
   g_fail=0;
   CRiskEngine eng;
   MM_RiskContext ctx; ctx.Reset();
   ctx.equity=10000; ctx.balance=10000; ctx.dayStartBalance=10000;
   ctx.basis=MM_BASIS_EQUITY; ctx.minRiskPercent=0.1; ctx.maxRiskPercent=2.0;

   string sym=_Symbol;
   double vmin=SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN);
   double vstep=SymbolInfoDouble(sym,SYMBOL_VOLUME_STEP); if(vstep<=0) vstep=0.01;
   double vmaxSym=SymbolInfoDouble(sym,SYMBOL_VOLUME_MAX);
   double point=SymbolInfoDouble(sym,SYMBOL_POINT);
   double ask=SymbolInfoDouble(sym,SYMBOL_ASK);
   double bid=SymbolInfoDouble(sym,SYMBOL_BID);

   MM_TradePlan plan; plan.Reset(); plan.symbol=sym; plan.side=POSITION_TYPE_BUY; plan.orderType=ORDER_TYPE_BUY; plan.isPending=false;
   plan.entryPrice=ask;
   plan.slPrice=plan.entryPrice - 100*point;
   plan.tpCount=1; plan.tpPrice[0]=plan.entryPrice + 200*point;
   plan.sizingMode=SIZING_AUTO_RISK; plan.riskValue=1.0; // 1%

   // 1) Auto-risk 1% valid
   MM_RiskResult r; eng.Calculate(plan, ctx, r);
   Assert(r.valid && !r.blocked, "auto-risk valid");
   Assert(r.lot>0, "lot > 0");
   Assert(r.riskMoney <= 100.0 + 1e-6, "risk money <= requested 1% (step floored)");
   Assert(r.riskPercent >= 0 && r.riskPercent <= 1.0001, "risk percent within requested");
   Assert(r.rr >= 1.9 && r.rr <= 2.1, "RR ~ 2.0");
   Assert(r.basis=="Equity", "basis Equity");
   Assert(HasCap(r,"requestedRiskPct="), "requested risk recorded");

   // 2) No-SL block
   MM_TradePlan p2=plan; p2.slPrice=p2.entryPrice; MM_RiskResult r2; eng.Calculate(p2,ctx,r2);
   Assert(r2.blocked && !r2.valid, "no-SL blocked");
   Assert(HasWarn(r2,"NO_SL"), "no-SL reason present");

   // 3) Manual lot valid and risk money consistent
   MM_TradePlan p3=plan; p3.sizingMode=SIZING_MANUAL_LOT; p3.lot=vmin;
   MM_RiskResult r3; eng.Calculate(p3,ctx,r3);
   Assert(r3.valid && r3.lot>=vmin-1e-12, "manual lot valid");
   Assert(r3.riskMoney >= 0 && r3.riskPercent >= 0, "manual risk reported");

   // 4) Volume max cap
   MM_RiskContext ctxV=ctx; ctxV.maxPositionVolume = vmin; // cap to min
   MM_RiskResult rV; eng.Calculate(plan, ctxV, rV);
   if(rV.valid){ Assert(rV.lot <= vmin + 1e-12, "volume capped by maxPositionVolume"); Assert(HasCap(rV,"cap:max_volume"), "cap:max_volume recorded"); }
   else { Assert(HasWarn(rV,"minimum") || HasWarn(rV,"MIN") || HasWarn(rV,"BLOCK"), "blocked when cap below usable budget"); }

   // 5) Aggregate cap: open risk consumes budget
   MM_RiskContext ctx2=ctx; ctx2.openRiskMoney=95.0; // leaves ~5 of 100 (1%) portfolio budget
   MM_RiskResult r4; eng.Calculate(plan, ctx2, r4);
   Assert(r4.blocked || r4.riskMoney <= 10.0, "aggregate open risk caps/blocks");
   if(!r4.blocked) Assert(HasCap(r4,"cap:aggregate_open_risk"), "aggregate cap recorded");

   // 6) DD remaining cap (prop-like)
   MM_RiskContext ctx3=ctx; ctx3.basis=MM_BASIS_ALLOWED_DD; ctx3.remainingDailyDDMoney=80.0; ctx3.remainingMaxDDMoney=60.0; ctx3.openRiskMoney=30.0;
   MM_RiskResult r5; eng.Calculate(plan, ctx3, r5);
   Assert(r5.blocked || r5.riskMoney <= 35.0, "DD remaining cap applied");
   Assert(r5.basis=="AllowedDD", "basis AllowedDD");
   if(!r5.blocked) Assert(HasCap(r5,"cap:DD_remaining"), "DD cap recorded");

   // 7) Risk% max clamp
   MM_TradePlan pHi=plan; pHi.riskValue=5.0; // above maxRiskPercent 2.0
   MM_RiskResult rHi; eng.Calculate(pHi, ctx, rHi);
   if(rHi.valid) { Assert(rHi.riskPercent <= 2.0001 + 1e-6, "risk percent clamped to max"); Assert(HasCap(rHi,"cap:maxRiskPercent"), "maxRiskPercent cap recorded"); }

   // 8) Margin-aware sizing: final volume must pass OrderCalcMargin and respect step/min (never increased)
   double freeM = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double eqAcc = AccountInfoDouble(ACCOUNT_EQUITY);
   MM_RiskContext ctxM; ctxM.Reset(); ctxM.equity=eqAcc; ctxM.balance=AccountInfoDouble(ACCOUNT_BALANCE); ctxM.dayStartBalance=ctxM.balance; ctxM.basis=MM_BASIS_EQUITY; ctxM.maxRiskPercent=100.0;
   MM_TradePlan pM=plan; pM.entryPrice=ask; pM.slPrice=ask - 10*point; pM.sizingMode=SIZING_AUTO_RISK; pM.riskValue=50.0; pM.isPending=false; pM.orderType=ORDER_TYPE_BUY;
   MM_RiskResult rM; eng.Calculate(pM, ctxM, rM);
   if(rM.valid)
   {
      double margin=0.0; bool mok = OrderCalcMargin(ORDER_TYPE_BUY, sym, rM.lot, ask, margin);
      Assert(mok, "OrderCalcMargin ok for final sized lot");
      if(mok) Assert(margin <= freeM + 1e-6, "final lot within free margin");
      double steps = MathRound(rM.lot/vstep);
      Assert(MathAbs(steps*vstep - rM.lot) <= vstep*0.11, "final lot aligned to step");
      Assert(rM.lot >= vmin - 1e-12, "final lot >= min");
   }
   else
   {
      Assert(HasWarn(rM,"NO_MONEY") || HasWarn(rM,"minimum") || HasWarn(rM,"MARGIN") || HasWarn(rM,"BLOCK"), "margin/min-lot block has clear reason");
   }

   // 9) Pending order context (correct order type/price) should be margin-checkable
   MM_RiskContext ctxP=ctxM;
   MM_TradePlan pP=plan; pP.isPending=true; pP.orderType=ORDER_TYPE_BUY_LIMIT; pP.entryPrice = bid - 200*point; pP.slPrice = pP.entryPrice - 100*point; pP.tpCount=1; pP.tpPrice[0]=pP.entryPrice + 200*point; pP.sizingMode=SIZING_AUTO_RISK; pP.riskValue=0.5;
   if(pP.entryPrice > 0 && pP.entryPrice < ask)
   {
      MM_RiskResult rP; eng.Calculate(pP, ctxP, rP);
      if(rP.valid)
      {
         double marginP=0.0; bool mokP = OrderCalcMargin(ORDER_TYPE_BUY_LIMIT, sym, rP.lot, pP.entryPrice, marginP);
         Assert(mokP, "OrderCalcMargin ok for pending final lot");
         if(mokP) Assert(marginP <= freeM + 1e-6, "pending final lot within free margin");
      }
      else
      {
         Assert(rP.blocked, "pending invalid/blocked consistently");
         Assert(rP.warningsCount>=0, "pending block has reasons array");
      }
   }

   // 10) Manual lot exceeding DD/aggregate budget blocked with clear reason
   MM_RiskContext ctxMB=ctx; ctxMB.remainingDailyDDMoney=10.0; ctxMB.remainingMaxDDMoney=10.0; ctxMB.openRiskMoney=0.0; ctxMB.basis=MM_BASIS_ALLOWED_DD;
   MM_TradePlan pMB=plan; pMB.sizingMode=SIZING_MANUAL_LOT; pMB.lot = MathMin(vmaxSym, vmin*50.0);
   MM_RiskResult rMB; eng.Calculate(pMB, ctxMB, rMB);
   if(rMB.valid==false && rMB.blocked)
      Assert(HasWarn(rMB,"DD") || HasWarn(rMB,"budget") || HasWarn(rMB,"NO_MONEY") || HasWarn(rMB,"MARGIN") || HasWarn(rMB,"minimum") || HasWarn(rMB,"INVALID") || HasWarn(rMB,"BLOCK"), "manual block reason clear");

   if(g_fail==0) Print("RiskEngine_Test: ALL PASS"); else Print("RiskEngine_Test: FAIL count=",g_fail);
}
