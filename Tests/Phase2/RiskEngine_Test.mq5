//+------------------------------------------------------------------+
//|                                              RiskEngine_Test.mq5 |
//|          Phase 2: sizing, RR, no-SL block, aggregate/DD caps     |
//+------------------------------------------------------------------+
#property script_show_inputs
#include "..\\..\\Include\\Core\\RiskEngine.mqh"

int g_fail=0;
void Assert(bool c,const string n){ if(!c){Print("FAIL: ",n); g_fail++;} else Print("OK: ",n); }

void OnStart()
{
   g_fail=0;
   CRiskEngine eng;
   MM_RiskContext ctx; ctx.Reset();
   ctx.equity=10000; ctx.balance=10000; ctx.dayStartBalance=10000;
   ctx.basis=MM_BASIS_EQUITY; ctx.minRiskPercent=0.1; ctx.maxRiskPercent=2.0;

   MM_TradePlan plan; plan.Reset(); plan.symbol=_Symbol; plan.side=POSITION_TYPE_BUY;
   plan.entryPrice=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   plan.slPrice=plan.entryPrice - 100*SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   plan.tpCount=1; plan.tpPrice[0]=plan.entryPrice + 200*SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   plan.sizingMode=SIZING_AUTO_RISK; plan.riskValue=1.0; // 1%

   MM_RiskResult r; eng.Calculate(plan, ctx, r);
   Assert(r.valid && !r.blocked, "auto-risk valid");
   Assert(r.lot>0, "lot > 0");
   Assert(MathAbs(r.riskMoney - 100.0) < MathMax(5.0, r.riskMoney*0.15) || r.riskMoney<=100.0, "risk money near/below 1% (step floored)");
   Assert(r.rr >= 1.9 && r.rr <= 2.1, "RR ~ 2.0");

   // No-SL block
   MM_TradePlan p2=plan; p2.slPrice=p2.entryPrice; MM_RiskResult r2; eng.Calculate(p2,ctx,r2);
   Assert(r2.blocked && !r2.valid, "no-SL blocked");

   // Manual lot
   MM_TradePlan p3=plan; p3.sizingMode=SIZING_MANUAL_LOT; p3.lot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   MM_RiskResult r3; eng.Calculate(p3,ctx,r3);
   Assert(r3.valid && r3.lot>=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN), "manual lot valid");

   // Aggregate cap: open risk consumes budget
   MM_RiskContext ctx2=ctx; ctx2.openRiskMoney=95.0; // leaves ~5 of 100 (1%) portfolio budget
   MM_RiskResult r4; eng.Calculate(plan, ctx2, r4);
   Assert(r4.blocked || r4.riskMoney <= 10.0, "aggregate open risk caps/blocks");

   // DD remaining cap (prop-like)
   MM_RiskContext ctx3=ctx; ctx3.basis=MM_BASIS_ALLOWED_DD; ctx3.remainingDailyDDMoney=80.0; ctx3.remainingMaxDDMoney=60.0; ctx3.openRiskMoney=30.0;
   // allowed DD = min(80,60)-30 = 30
   MM_RiskResult r5; eng.Calculate(plan, ctx3, r5);
   Assert(r5.blocked || r5.riskMoney <= 35.0, "DD remaining cap applied");
   Assert(r5.basis=="AllowedDD", "basis AllowedDD");

   if(g_fail==0) Print("RiskEngine_Test: ALL PASS"); else Print("RiskEngine_Test: FAIL count=",g_fail);
}
