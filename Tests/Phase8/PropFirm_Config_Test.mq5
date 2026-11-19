//+------------------------------------------------------------------+
//|                                      PropFirm_Config_Test.mq5    |
//|  Phase 8: Optional Prop Firm configuration (focused, no broker)  |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "..\\..\\Include\\Utils\\Common.mqh"
#include "..\\..\\Include\\Core\\Contracts.mqh"
#include "..\\..\\Include\\PropFirm\\PropFirm.mqh"
#include "..\\..\\Include\\Guards\\PropGuard.mqh"
#include "..\\..\\Include\\Guards\\ProtectionGuard.mqh"

int g_fail=0;
void Assert(bool c,const string n){ if(!c){ Print("FAIL: ",n); g_fail++; } else Print("OK: ",n); }
bool Nearly(double a,double b,double eps=1e-6){ return MathAbs(a-b)<=eps; }

// Phase 8 acceptance (verifiable/unit scope):
// - Optional and explicit; prop not implicitly enforced in personal mode.
// - Preset/rule mapping and DD used/remaining aligned to configured reference (equity/balance).
// - Supported prop limits block via guard when configured; unsupported/unverified rules not falsely enforced.
void OnStart()
{
   g_fail=0;

   // 1) Preset mapping
   {
      CPropFirm pf; pf.Init(); SPropFirmRules r;
      pf.LoadPreset("FTMO", r);
      Assert(r.mode==PROP_CHALLENGE && r.ddReference==DD_FROM_EQUITY, "FTMO mode/ref");
      Assert(Nearly(r.maxDailyLoss,5.0) && Nearly(r.maxTotalDD,10.0), "FTMO daily/max DD");
      Assert(Nearly(r.profitTarget,10.0) && r.minTradingDays==4, "FTMO target/min-days");
      Assert(r.newsBlackout==true && r.weekendClose==true, "FTMO news/weekend flags");

      pf.LoadPreset("MFF", r);
      Assert(r.ddReference==DD_FROM_BALANCE && Nearly(r.maxDailyLoss,5.0) && Nearly(r.maxTotalDD,12.0), "MFF DD ref/limits");
      Assert(Nearly(r.consistencyPercent,40.0) && r.minTradingDays==5, "MFF consistency/min-days mapped");

      pf.LoadPreset("FundedNext", r);
      Assert(r.mode==PROP_FUNDED && r.ddReference==DD_FROM_EQUITY && Nearly(r.maxDailyLoss,5.0) && Nearly(r.maxTotalDD,10.0), "FundedNext preset");

      pf.LoadPreset("The5ers", r);
      Assert(r.ddReference==DD_FROM_BALANCE && Nearly(r.maxPositionSize,2.0) && Nearly(r.profitTarget,6.0), "The5ers position/profit mapped");

      pf.LoadPreset("UNKNOWN_FIRM", r);
      Assert(r.maxDailyLoss==0.0 && r.maxTotalDD==0.0 && r.consistencyPercent==0.0, "unknown preset -> safe defaults (no false guarantees)");
   }

   // 2) DD used/remaining alignment with reference (equity/balance) and live baselines
   {
      CPropFirm pf; pf.Init(); SPropFirmRules r;
      // Equity-referenced (FTMO-like)
      pf.LoadPreset("FTMO", r); pf.Enable(r);
      double dayStartBal=10000, dayStartEq=10000, peakEq=10200, curEq=9900, startBal=10000;
      double dailyLossMoney=300; // 3%
      double usedDaily = pf.DailyLossUsedPct(dailyLossMoney, dayStartBal, dayStartEq);
      double usedMax   = pf.TotalDDUsedPct(curEq, peakEq, startBal); // (10200-9900)/10200*100 = ~2.941%
      double remDaily  = pf.RemainingDailyDDMoney(dailyLossMoney, dayStartBal, dayStartEq); // 500-300
      double remMax    = pf.RemainingMaxDDMoney(curEq, peakEq, startBal); // 1020-300
      Assert(Nearly(usedDaily,3.0,0.01), "equity-ref daily DD used %");
      Assert(Nearly(usedMax,(10200.0-9900.0)/10200.0*100.0,0.01), "equity-ref max DD used % from peak equity");
      Assert(Nearly(remDaily,200.0,0.01), "equity-ref remaining daily DD money");
      Assert(Nearly(remMax,(10200.0*0.10)-(10200.0-9900.0),0.01), "equity-ref remaining max DD money");

      // Balance-referenced (MFF-like)
      pf.LoadPreset("MFF", r); pf.Enable(r);
      dayStartBal=10000; dayStartEq=9800; peakEq=10100; curEq=9700; startBal=10000; dailyLossMoney=400;
      usedDaily = pf.DailyLossUsedPct(dailyLossMoney, dayStartBal, dayStartEq); // ref balance 10000 -> 4%
      usedMax   = pf.TotalDDUsedPct(curEq, peakEq, startBal); // ref balance 10000 -> (10000-9700)/10000=3%
      remDaily  = pf.RemainingDailyDDMoney(dailyLossMoney, dayStartBal, dayStartEq); // 500-400
      remMax    = pf.RemainingMaxDDMoney(curEq, peakEq, startBal); // 1200-300
      Assert(Nearly(usedDaily,4.0,0.01), "balance-ref daily DD used %");
      Assert(Nearly(usedMax,3.0,0.01), "balance-ref total DD used % from start balance");
      Assert(Nearly(remDaily,100.0,0.01), "balance-ref remaining daily DD money");
      Assert(Nearly(remMax,900.0,0.01), "balance-ref remaining max DD money");

      // Baseline sync keeps peaks/baseline usable
      pf.SyncBaseline(10000, 10300, 10250);
      Assert(pf.MaxDDRef(10000,10300) >= 10000.0, "max DD ref derived from configured baseline/ref");
   }

   // 3) Guard enforcement: explicit prop mode only, supported rules block, separation from personal
   {
      MM_TradePlan plan; plan.Reset(); plan.symbol=_Symbol; if(plan.symbol=="") plan.symbol="EURUSD";
      plan.side=POSITION_TYPE_BUY; plan.entryPrice=1.1000; plan.slPrice=1.0990; plan.tpCount=1; plan.tpPrice[0]=1.1020; plan.lot=0.10;

      CPropGuard pg;
      MM_GuardConfig cfg; cfg.Reset();
      cfg.accountMode=ACCOUNT_PROP; cfg.propEnabled=true;
      cfg.propDailyLossLimitPct=5.0; cfg.propDailyLossUsedPct=5.0;
      MM_GuardResult out; out.Reset(); pg.Evaluate(plan,cfg,out);
      Assert(out.decision==GUARD_BLOCK && out.reasonCode=="PROP_DAILY_DD", "prop daily DD limit blocks when reached");

      cfg.Reset(); cfg.accountMode=ACCOUNT_PROP; cfg.propEnabled=true;
      cfg.propMaxTotalDDPct=10.0; cfg.propTotalDDUsedPct=10.5;
      out.Reset(); pg.Evaluate(plan,cfg,out);
      Assert(out.decision==GUARD_BLOCK && out.reasonCode=="PROP_MAX_DD", "prop max DD limit blocks when reached");

      cfg.Reset(); cfg.accountMode=ACCOUNT_PROP; cfg.propEnabled=true;
      cfg.propMaxTradesPerDay=3; cfg.tradesToday=3;
      out.Reset(); pg.Evaluate(plan,cfg,out);
      Assert(out.decision==GUARD_BLOCK && out.reasonCode=="PROP_MAX_TRADES", "prop max trades/day blocks when reached");

      // Separation: not enforced in personal mode and not implicitly when disabled
      cfg.Reset(); cfg.accountMode=ACCOUNT_PERSONAL; cfg.propEnabled=false;
      cfg.propDailyLossLimitPct=5.0; cfg.propDailyLossUsedPct=100.0; cfg.propMaxTotalDDPct=10.0; cfg.propTotalDDUsedPct=100.0;
      out.Reset(); pg.Evaluate(plan,cfg,out);
      Assert(out.decision==GUARD_ALLOW, "prop rules not enforced in personal mode");

      cfg.Reset(); cfg.accountMode=ACCOUNT_PROP; cfg.propEnabled=false;
      cfg.propDailyLossLimitPct=5.0; cfg.propDailyLossUsedPct=100.0;
      out.Reset(); pg.Evaluate(plan,cfg,out);
      Assert(out.decision==GUARD_ALLOW, "prop rules not enforced when prop not explicitly enabled");

      // Unsupported/unverified consistency rule must not be falsely enforced when reliability disabled in config
      cfg.Reset(); cfg.accountMode=ACCOUNT_PROP; cfg.propEnabled=true;
      cfg.propConsistencyEnabled=false; cfg.propConsistencyPct=40.0; cfg.propTodayProfitPct=99.0;
      out.Reset(); pg.Evaluate(plan,cfg,out);
      Assert(out.decision!=GUARD_BLOCK || out.reasonCode!="PROP_CONSISTENCY", "unverified consistency not falsely blocking");
   }

   if(g_fail==0) Print("PropFirm_Config_Test: ALL PASS"); else Print("PropFirm_Config_Test: FAIL count=",g_fail);
}
