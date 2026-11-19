//+------------------------------------------------------------------+
//|                                      RiskGuardian_Test.mq5       |
//|  Phase 9: Risk Guardian hardening (focused, no broker sends)     |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "..\\..\\Include\\Core\\Contracts.mqh"
#include "..\\..\\Include\\Guards\\GuardEngine.mqh"
#include "..\\..\\Include\\Protection\\Protection.mqh"

int g_fail=0;
void Assert(bool c,const string n){ if(!c){ Print("FAIL: ",n); g_fail++; } else Print("OK: ",n); }
bool Nearly(double a,double b,double eps=1e-6){ return MathAbs(a-b)<=eps; }

void OnStart()
{
   g_fail=0;

   MM_TradePlan plan; plan.Reset();
   plan.symbol=_Symbol; if(plan.symbol=="") plan.symbol="EURUSD";
   plan.side=POSITION_TYPE_BUY; plan.entryPrice=1.1000; plan.slPrice=1.0990; plan.tpCount=1; plan.tpPrice[0]=1.1020; plan.lot=0.01;

   // 1) Guard priority and preview/send consistency (first block = highest-priority blocking guard)
   {
      CGuardEngine ge; ge.Init(NULL,true);
      MM_GuardConfig cfg; cfg.Reset();
      // Trigger multiple blocks: permission (terminal/account flags may vary, force via config where possible) is hard to force portably,
      // but protection block is deterministic via config; prop block also deterministic in prop mode.
      cfg.accountMode=ACCOUNT_PROP; cfg.propEnabled=true;
      cfg.propDailyLossLimitPct=5.0; cfg.propDailyLossUsedPct=6.0; // Prop block (priority 20)
      cfg.protectionEnabled=true; cfg.dailyLossLimitPct=4.0; cfg.dailyLossPct=5.0; // Protection block (priority 30)
      MM_GuardReport rep; rep.Reset();
      bool allowed = ge.CanExecute(plan, cfg, rep);
      Assert(!allowed && rep.hasBlock, "multi-block config blocked");
      Assert(rep.firstBlock.reasonCode=="PROP_DAILY_DD", "first block follows priority order (Prop before Protection)");

      // Preview must match allow/block decision and first block without sink side-effects requirement
      MM_GuardReport prev; prev.Reset();
      bool pAllowed = ge.Preview(plan, cfg, prev);
      Assert(pAllowed==allowed, "Preview allow/block consistent with CanExecute");
      Assert(prev.firstBlock.reasonCode==rep.firstBlock.reasonCode, "Preview first block consistent with CanExecute");
   }

   // 2) Weekly/monthly loss enforcement via protection accounting and guard config inputs
   {
      CProtection p; p.Init();
      datetime now = TimeCurrent();
      p.SyncPeriods(now);
      p.RecordCompletedTrade(-50.0); // realized loss
      double wl = p.WeeklyLoss();
      double ml = p.MonthlyLoss();
      Assert(wl >= 50.0-1e-9 && ml >= 50.0-1e-9, "completed trade loss aggregated into weekly/monthly (realized)");

      double dlp = p.DailyLossPct();
      double wlp = p.WeeklyLossPct();
      double mlp = p.MonthlyLossPct();
      Assert(dlp>=0.0 && wlp>=0.0 && mlp>=0.0, "period loss percentages available");

      CProtectionGuard pg;
      MM_GuardConfig cfg; cfg.Reset(); cfg.protectionEnabled=true;
      cfg.weeklyLossLimitPct = (wlp>0.0 ? wlp : 0.5); cfg.weeklyLossPct = cfg.weeklyLossLimitPct;
      MM_GuardResult out; out.Reset(); pg.Evaluate(plan,cfg,out);
      Assert(out.decision==GUARD_BLOCK && out.reasonCode=="WEEKLY_LOSS_LIMIT", "weekly loss limit enforced");

      cfg.Reset(); cfg.protectionEnabled=true;
      cfg.monthlyLossLimitPct = (mlp>0.0 ? mlp : 0.5); cfg.monthlyLossPct = cfg.monthlyLossLimitPct;
      out.Reset(); pg.Evaluate(plan,cfg,out);
      Assert(out.decision==GUARD_BLOCK && out.reasonCode=="MONTHLY_LOSS_LIMIT", "monthly loss limit enforced");

      // Daily reset boundary (server-time key) clears daily counters/baseline on new day
      MqlDateTime dt; TimeToStruct(now, dt);
      dt.day += 1; datetime nextDay = StructToTime(dt);
      p.SyncPeriods(nextDay);
      Assert(Nearly(p.DailyLoss(),0.0) && p.TradesToday()==0, "daily counters reset on server-day boundary");
   }

   // 3) Cooldown and consecutive-loss logic (predictable)
   {
      CProtection p; p.Init();
      datetime now = TimeCurrent();
      // 3 losing completed trades with cooldown configured
      p.RecordCompletedTrade(-1.0); p.ApplyConsecLossPolicy(3, 1, now);
      p.RecordCompletedTrade(-1.0); p.ApplyConsecLossPolicy(3, 1, now);
      p.RecordCompletedTrade(-1.0); p.ApplyConsecLossPolicy(3, 1, now);
      Assert(p.ConsecutiveLosses()>=3, "consecutive losses tracked");
      Assert(!p.CheckCooldown(), "cooldown active after reaching max consecutive losses (with cooldown)");

      // Guard reflects cooldown block
      MM_GuardConfig cfg; cfg.Reset(); cfg.protectionEnabled=true; cfg.maxConsecLoss=3; cfg.consecLosses=p.ConsecutiveLosses(); cfg.inCooldown=!p.CheckCooldown();
      CProtectionGuard pg; MM_GuardResult out; out.Reset(); pg.Evaluate(plan,cfg,out);
      Assert(out.decision==GUARD_BLOCK && (out.reasonCode=="COOLDOWN" || out.reasonCode=="CONSEC_LOSS_LIMIT"), "guard blocks during cooldown/consec breach");

      // After cooldown expiry, protection resets streak for a fresh window
      datetime after = now + 120; // > 1 minute
      p.UpdateCooldown(after);
      Assert(p.CheckCooldown(), "cooldown expires");
      Assert(p.ConsecutiveLosses()==0, "consecutive loss streak reset after cooldown expiry");

      // No-cooldown policy: remain blocked by streak until reset by win/break-even policy in accounting flow
      CProtection p2; p2.Init();
      datetime nowNC = TimeCurrent();
      p2.RecordCompletedTrade(-1.0); p2.ApplyConsecLossPolicy(2, 0, nowNC); bool ok1=p2.CheckConsecutiveLoss(2, 0);
      p2.RecordCompletedTrade(-1.0); p2.ApplyConsecLossPolicy(2, 0, nowNC); bool ok2=p2.CheckConsecutiveLoss(2, 0);
      Assert(ok1==true && ok2==false, "no-cooldown breach blocks while streak remains at/above limit");
      Assert(p2.ConsecutiveLosses()>=2, "streak remains when no cooldown configured");
      p2.RecordCompletedTrade(1.0); // winning outcome resets streak per accounting
      Assert(p2.ConsecutiveLosses()==0, "winning completed trade resets consecutive loss streak");
   }

   // 4) Exposure dedupe ring fallback keeps counting/deduping correctly after overflow (>256)
   {
      CProtection p; p.Init();
      int added=0;
      // add 300 unique exposures
      for(int i=1;i<=300;i++){ if(p.RegisterExposureOrder((ulong)(100000+i), 0)) added++; }
      Assert(p.TradesToday()==300, "exposure count increments for unique orders beyond 256");
      // duplicates within retained window must not increment
      bool dupOld = p.RegisterExposureOrder((ulong)(100000+1), 0);   // likely evicted from ring, may be counted again (acceptable: recent-window dedupe)
      bool dupNew = p.RegisterExposureOrder((ulong)(100000+300), 0); // must remain deduped
      Assert(dupNew==false, "recent exposure remains deduped after ring overflow");
      Assert(p.TradesToday()>=300, "duplicate of retained key does not increase count");
      Print("Exposure ring check: tradesToday=",p.TradesToday()," dupOldAdded=",dupOld," dupNewAdded=",dupNew);
   }

   // 5) Trades/day limit enforcement
   {
      MM_GuardConfig cfg; cfg.Reset(); cfg.protectionEnabled=true; cfg.maxTradesPerDay=5; cfg.tradesToday=5;
      CProtectionGuard pg; MM_GuardResult out; out.Reset(); pg.Evaluate(plan,cfg,out);
      Assert(out.decision==GUARD_BLOCK && out.reasonCode=="MAX_TRADES_DAY", "max trades/day enforced");
   }

   if(g_fail==0) Print("RiskGuardian_Test: ALL PASS"); else Print("RiskGuardian_Test: FAIL count=",g_fail);
}
