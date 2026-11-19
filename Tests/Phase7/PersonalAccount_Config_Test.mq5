//+------------------------------------------------------------------+
//|                                 PersonalAccount_Config_Test.mq5   |
//|  Phase 7: Personal Account configuration hardening (focused)     |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "..\\..\\Include\\Utils\\Common.mqh"
#include "..\\..\\Include\\Core\\Contracts.mqh"
#include "..\\..\\Include\\Profiles\\Profiles.mqh"
#include "..\\..\\Include\\Protection\\Protection.mqh"
#include "..\\..\\Include\\Guards\\ProtectionGuard.mqh"
#include "..\\..\\Include\\Guards\\PropGuard.mqh"

int g_fail=0;
void Assert(bool c,const string n){ if(!c){ Print("FAIL: ",n); g_fail++; } else Print("OK: ",n); }
bool Nearly(double a,double b,double eps=1e-9){ return MathAbs(a-b)<=eps; }

// Focused checks for Phase 7 acceptance:
// - Personal mode default profile/limits transparent and operable without prop config.
// - Protection baselines/period tracking are initialized and diagnosable (server-time sync/reset semantics).
// - Prop-firm rules not enforced implicitly in personal mode.
void OnStart()
{
   g_fail=0;

   // 1) Personal profile defaults (safe, transparent)
   {
      CProfileManager pm; pm.Init(-1);
      MM_ProfileRecord pr; pr.Reset();
      bool has = pm.GetActive(pr);
      Assert(has, "profile manager has active profile");
      // Ensure a personal profile exists with expected defaults
      MM_ProfileRecord personal; personal.Reset();
      bool foundPersonal=false;
      for(int i=0;i<pm.Count();i++){ MM_ProfileRecord r; if(pm.Get(i,r) && r.profile.accountMode==ACCOUNT_PERSONAL){ personal=r; foundPersonal=true; break; } }
      Assert(foundPersonal, "personal profile exists by default");
      if(foundPersonal)
      {
         Assert(personal.profile.accountMode==ACCOUNT_PERSONAL, "personal account mode");
         Assert(personal.profile.riskBasis=="Equity" || personal.profile.riskBasis=="Balance" || personal.profile.riskBasis=="AllowedDD", "personal risk basis defined");
         Assert(personal.profile.defaultRiskPercent>0.0, "personal default risk % set");
         Assert(personal.dailyLossLimitPct>=0.0, "personal daily loss limit field present");
         Assert(personal.maxDrawdownPct>=0.0, "personal max drawdown limit field present");
         Assert(personal.weeklyLossLimitPct>=0.0, "personal weekly loss limit field present");
         Assert(personal.monthlyLossLimitPct>=0.0, "personal monthly loss limit field present");
         Assert(personal.cooldownMinutes>=0, "personal cooldown field present");
         Assert(personal.maxTradesPerDay>=0, "personal max trades/day field present");
         Print("Personal defaults: DL=",DoubleToString(personal.dailyLossLimitPct,2)," WL=",DoubleToString(personal.weeklyLossLimitPct,2)," ML=",DoubleToString(personal.monthlyLossLimitPct,2)," DD=",DoubleToString(personal.maxDrawdownPct,2)," Trades=",personal.maxTradesPerDay," CD=",personal.cooldownMinutes," CL=",personal.maxConsecLoss," basis=",personal.profile.riskBasis);
      }
   }

   // 2) Protection baselines/period tracking and reset behavior (server-time sync, no invention)
   {
      CProtection p; p.Init();
      datetime now = TimeCurrent();
      double bal = AccountInfoDouble(ACCOUNT_BALANCE);
      double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
      p.SyncPeriods(now);
      p.SyncPeaks();
      Assert(p.DayStartBalance() > 0.0 || bal==0.0, "day-start balance baseline initialized/diagnosable");
      Assert(p.DayStartEquity() >= 0.0, "day-start equity baseline initialized/diagnosable");
      Assert(p.PeakEquity() >= 0.0, "peak equity tracked");
      Assert(Nearly(p.DailyLoss(),0.0), "no invented historical daily loss on init");
      Assert(Nearly(p.WeeklyLoss(),0.0), "no invented historical weekly loss on init");
      Assert(Nearly(p.MonthlyLoss(),0.0), "no invented historical monthly loss on init");
      Assert(p.TradesToday()==0, "no invented trade count on init");
      // simulate completed trade accounting (realized net) and period counters
      p.RegisterExposureOrder(1001, 2001);
      Assert(p.TradesToday()==1, "exposure counted once");
      p.RegisterExposureOrder(1001, 2001);
      Assert(p.TradesToday()==1, "duplicate exposure deduped");
      p.RecordCompletedTrade(-10.0);
      Assert(p.DailyLoss()>=10.0-1e-9, "daily realized loss accounted");
      Assert(p.WeeklyLoss()>=10.0-1e-9, "weekly realized loss accounted");
      Assert(p.MonthlyLoss()>=10.0-1e-9, "monthly realized loss accounted");
      p.ApplyConsecLossPolicy(3, 60, now);
      p.UpdateCooldown(now);
      double dlp = p.DailyLossPct();
      double wlp = p.WeeklyLossPct();
      double mlp = p.MonthlyLossPct();
      double ddp = p.CurrentDrawdownPct();
      Assert(dlp>=0.0 && wlp>=0.0 && mlp>=0.0 && ddp>=0.0, "loss/DD percentages diagnosable");
      Print("Protection: dayStartBal=",DoubleToString(p.DayStartBalance(),2)," peakEq=",DoubleToString(p.PeakEquity(),2)," dailyLoss=",DoubleToString(p.DailyLoss(),2)," weeklyLoss=",DoubleToString(p.WeeklyLoss(),2)," monthlyLoss=",DoubleToString(p.MonthlyLoss(),2)," dd%=",DoubleToString(ddp,2));
   }

   // 3) Guard behavior: protection enforces configured personal limits; prop not implicitly enforced in personal mode
   {
      MM_TradePlan plan; plan.Reset(); plan.symbol=_Symbol; if(plan.symbol=="") plan.symbol="EURUSD";
      plan.side=POSITION_TYPE_BUY; plan.entryPrice=1.0; plan.slPrice=0.99; plan.tpCount=1; plan.tpPrice[0]=1.02; plan.lot=0.01;

      CProtectionGuard pg; MM_GuardConfig cfg; cfg.Reset();
      cfg.protectionEnabled=true;
      cfg.dailyLossLimitPct=5.0; cfg.dailyLossPct=5.0; // reached
      MM_GuardResult out; out.Reset();
      pg.Evaluate(plan,cfg,out);
      Assert(out.decision==GUARD_BLOCK && out.reasonCode=="DAILY_LOSS_LIMIT", "daily loss limit blocks when reached (personal config)");

      MM_GuardConfig cfg2; cfg2.Reset(); cfg2.protectionEnabled=true;
      cfg2.weeklyLossLimitPct=3.0; cfg2.weeklyLossPct=3.5;
      MM_GuardResult out2; out2.Reset(); pg.Evaluate(plan,cfg2,out2);
      Assert(out2.decision==GUARD_BLOCK && out2.reasonCode=="WEEKLY_LOSS_LIMIT", "weekly loss limit blocks when reached");

      MM_GuardConfig cfg3; cfg3.Reset(); cfg3.protectionEnabled=true;
      cfg3.monthlyLossLimitPct=6.0; cfg3.monthlyLossPct=6.0;
      MM_GuardResult out3; out3.Reset(); pg.Evaluate(plan,cfg3,out3);
      Assert(out3.decision==GUARD_BLOCK && out3.reasonCode=="MONTHLY_LOSS_LIMIT", "monthly loss limit blocks when reached");

      MM_GuardConfig cfg4; cfg4.Reset(); cfg4.protectionEnabled=true;
      cfg4.maxTradesPerDay=2; cfg4.tradesToday=2;
      MM_GuardResult out4; out4.Reset(); pg.Evaluate(plan,cfg4,out4);
      Assert(out4.decision==GUARD_BLOCK && out4.reasonCode=="MAX_TRADES_DAY", "max trades/day blocks when reached");

      MM_GuardConfig cfg5; cfg5.Reset(); cfg5.protectionEnabled=true;
      cfg5.inCooldown=true;
      MM_GuardResult out5; out5.Reset(); pg.Evaluate(plan,cfg5,out5);
      Assert(out5.decision==GUARD_BLOCK && out5.reasonCode=="COOLDOWN", "cooldown blocks when active");

      // Prop guard must not enforce implicitly in personal mode even if prop fields present.
      CPropGuard propG; MM_GuardConfig pcfg; pcfg.Reset();
      pcfg.accountMode=ACCOUNT_PERSONAL; pcfg.propEnabled=false;
      pcfg.propDailyLossLimitPct=4.0; pcfg.propDailyLossUsedPct=10.0; pcfg.propMaxTotalDDPct=8.0; pcfg.propTotalDDUsedPct=20.0;
      MM_GuardResult pout; pout.Reset(); propG.Evaluate(plan,pcfg,pout);
      Assert(pout.decision==GUARD_ALLOW, "prop guard inactive in personal mode");

      MM_GuardConfig pcfg2; pcfg2.Reset(); pcfg2.accountMode=ACCOUNT_PERSONAL; pcfg2.propEnabled=true; // misconfig/explicit flag must still not apply to personal account mode per guard contract
      pcfg2.propDailyLossLimitPct=4.0; pcfg2.propDailyLossUsedPct=10.0;
      MM_GuardResult pout2; pout2.Reset(); propG.Evaluate(plan,pcfg2,pout2);
      Assert(pout2.decision==GUARD_ALLOW, "prop guard not enforced for personal account mode");
   }

   if(g_fail==0) Print("PersonalAccount_Config_Test: ALL PASS"); else Print("PersonalAccount_Config_Test: FAIL count=",g_fail);
}
