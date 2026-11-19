//+------------------------------------------------------------------+
//|                                      ProtectionLimits_Test.mq5   |
//|        Phase 2.3: trade/loss/consec/cooldown/DD/aggregate/risk   |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "..\\..\\Include\\Protection\\Protection.mqh"
#include "..\\..\\Include\\Guards\\GuardEngine.mqh"
#include "..\\..\\Include\\Core\\RiskEngine.mqh"
#include "..\\..\\Include\\Core\\RejectSink.mqh"

int g_fail=0;
void Assert(bool c,const string n){ if(!c){Print("FAIL: ",n); g_fail++;} else Print("OK: ",n); }
bool HasCap(const MM_RiskResult &r,const string capSub){ for(int i=0;i<r.capsCount;i++) if(StringFind(r.capsApplied[i],capSub)>=0) return true; return false; }
bool HasWarn(const MM_RiskResult &r,const string warnSub){ for(int i=0;i<r.warningsCount;i++) if(StringFind(r.warnings[i],warnSub)>=0) return true; return false; }

class CNoopSink : public IRejectSink
{
public:
   virtual void OnExecutionReject(const string symbol,const string reasonCode,const string messageEN,uint retcode,const string context){}
   virtual void OnGuardReject(const MM_GuardResult &gr,const string symbol){}
};

void OnStart()
{
   g_fail=0;

   //--- 1) Daily trade counting (actual risk-increasing exposure, deduped by order ticket)
   CProtection prot; prot.Init();
   Assert(prot.TradesToday()==0, "trades today starts at 0");
   bool c1 = prot.RegisterExposureOrder(1001, 0);
   bool c2 = prot.RegisterExposureOrder(1001, 0); // duplicate same entry/order
   bool c3 = prot.RegisterExposureOrder(1001, 2001); // same order key, different deal - must not double count
   bool c4 = prot.RegisterExposureOrder(1002, 0);   // new entry
   Assert(c1 && !c2 && !c3 && c4, "exposure count dedup by order ticket");
   Assert(prot.TradesToday()==2, "trades today counts actual exposures once");
   prot.NewDay();
   Assert(prot.TradesToday()==0, "trades today reset on new day");

   //--- 2) Consecutive losses & cooldown lifecycle (completed trade outcome, once per trade lifecycle)
   CProtection p2; p2.Init();
   datetime base = TimeTradeServer(); if(base==0) base=TimeCurrent();
   p2.SyncPeriods(base);
   p2.RecordCompletedTrade(-10.0); p2.ApplyConsecLossPolicy(2, 30, base); // 1st loss
   Assert(p2.ConsecutiveLosses()==1, "consec losses increments on loss");
   Assert(p2.CheckCooldown(), "no cooldown before breach");
   p2.RecordCompletedTrade(-5.0);  p2.ApplyConsecLossPolicy(2, 30, base); // 2nd loss -> breach
   Assert(p2.ConsecutiveLosses()>=2, "consec losses reaches limit");
   Assert(!p2.CheckCooldown(), "cooldown active after breach");
   p2.UpdateCooldown(base + 31*60);
   Assert(p2.CheckCooldown(), "cooldown expires after duration");
   Assert(p2.ConsecutiveLosses()==0, "streak reset after cooldown expiry");

   CProtection p2w; p2w.Init(); p2w.SyncPeriods(base);
   p2w.RecordCompletedTrade(-1.0); p2w.RecordCompletedTrade(1.0);
   Assert(p2w.ConsecutiveLosses()==0, "win resets consec loss streak");

   //--- 3) Weekly/monthly realized loss accounting (server-time boundaries, no historical invention)
   CProtection p3; p3.Init();
   datetime mon = D'2026.11.16 10:00:00'; // Monday (server-time basis)
   p3.SyncPeriods(mon);
   double w0=p3.WeeklyLossPct(); double m0=p3.MonthlyLossPct();
   Assert(w0==0.0 && m0==0.0, "period loss pct starts at 0 (no invented history)");
   double wStart=p3.WeekStartBalance(); double mStart=p3.MonthStartBalance();
   Assert(wStart>0 && mStart>0, "period start balances initialized from current balance");
   p3.RecordCompletedTrade(- (wStart*0.05)); // 5% realized loss (profit+commission+swap aggregated once)
   Assert(MathAbs(p3.WeeklyLossPct() - 5.0) < 0.05, "weekly loss pct reflects realized completed-trade loss");
   Assert(MathAbs(p3.MonthlyLossPct() - 5.0) < 0.05, "monthly loss pct reflects realized completed-trade loss");
   p3.SyncPeriods(mon + 24*60*60); // next day, same week
   Assert(p3.TradesToday()==0, "daily counters reset on new server day");
   Assert(MathAbs(p3.WeeklyLossPct() - 5.0) < 0.05, "weekly loss preserved within same week");
   p3.SyncPeriods(mon + 7*24*60*60); // next week
   Assert(MathAbs(p3.WeeklyLossPct()) < 0.001, "weekly loss resets on new server week boundary");
   p3.SyncPeriods(D'2026.12.01 10:00:00'); // next month
   Assert(MathAbs(p3.MonthlyLossPct()) < 0.001, "monthly loss resets on new server month boundary");

   //--- 4) GuardEngine blocks new risk-increasing plans on protection limits (using fed config)
   CNoopSink sink; CGuardEngine eng; eng.Init(GetPointer(sink), true);
   MM_TradePlan plan; plan.Reset(); plan.symbol=_Symbol; plan.side=POSITION_TYPE_BUY; plan.lot=0.01;
   plan.entryPrice=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   plan.slPrice=plan.entryPrice - 200*SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   MM_GuardConfig cfg; cfg.Reset();
   cfg.requireTerminalConnected=false; cfg.requireTradeAllowed=false; cfg.requireExpertEnabled=false; cfg.requireAccountTradeAllowed=false;
   MM_GuardReport rep;

   cfg.weeklyLossLimitPct=5.0; cfg.weeklyLossPct=5.1;
   Assert(!eng.CanExecute(plan,cfg,rep) && rep.firstBlock.reasonCode=="WEEKLY_LOSS_LIMIT", "weekly loss limit blocks entry");
   cfg.Reset(); cfg.requireTerminalConnected=false; cfg.requireTradeAllowed=false; cfg.requireExpertEnabled=false; cfg.requireAccountTradeAllowed=false;

   cfg.monthlyLossLimitPct=8.0; cfg.monthlyLossPct=8.0;
   Assert(!eng.CanExecute(plan,cfg,rep) && rep.firstBlock.reasonCode=="MONTHLY_LOSS_LIMIT", "monthly loss limit blocks entry");
   cfg.Reset(); cfg.requireTerminalConnected=false; cfg.requireTradeAllowed=false; cfg.requireExpertEnabled=false; cfg.requireAccountTradeAllowed=false;

   cfg.maxDrawdownPct=10.0; cfg.currentDrawdownPct=10.0;
   Assert(!eng.CanExecute(plan,cfg,rep) && rep.firstBlock.reasonCode=="MAX_DRAWDOWN", "max drawdown blocks entry");
   cfg.Reset(); cfg.requireTerminalConnected=false; cfg.requireTradeAllowed=false; cfg.requireExpertEnabled=false; cfg.requireAccountTradeAllowed=false;

   cfg.maxTradesPerDay=2; cfg.tradesToday=2;
   Assert(!eng.CanExecute(plan,cfg,rep) && rep.firstBlock.reasonCode=="MAX_TRADES_DAY", "daily trade limit blocks entry");
   cfg.Reset(); cfg.requireTerminalConnected=false; cfg.requireTradeAllowed=false; cfg.requireExpertEnabled=false; cfg.requireAccountTradeAllowed=false;

   cfg.maxConsecLoss=3; cfg.consecLosses=3; cfg.inCooldown=false;
   Assert(!eng.CanExecute(plan,cfg,rep) && rep.firstBlock.reasonCode=="CONSEC_LOSS_LIMIT", "consecutive loss limit blocks entry");
   cfg.Reset(); cfg.requireTerminalConnected=false; cfg.requireTradeAllowed=false; cfg.requireExpertEnabled=false; cfg.requireAccountTradeAllowed=false;

   cfg.inCooldown=true; cfg.cooldownMinutes=15;
   Assert(!eng.CanExecute(plan,cfg,rep) && rep.firstBlock.reasonCode=="COOLDOWN", "cooldown blocks entry");
   cfg.Reset(); cfg.requireTerminalConnected=false; cfg.requireTradeAllowed=false; cfg.requireExpertEnabled=false; cfg.requireAccountTradeAllowed=false;

   // 5) Aggregate open-risk enforcement (authoritative in RiskEngine sizing; no duplicate formulas)
   CRiskEngine engRisk; MM_RiskContext rctx; rctx.Reset();
   rctx.equity=10000; rctx.balance=10000; rctx.dayStartBalance=10000; rctx.basis=MM_BASIS_EQUITY; rctx.maxRiskPercent=2.0;
   rctx.openRiskMoney=250.0; // exceeds 2% budget (200) -> must block
   MM_TradePlan rp; rp.Reset(); rp.symbol=_Symbol; rp.side=POSITION_TYPE_BUY; rp.orderType=ORDER_TYPE_BUY; rp.isPending=false;
   rp.entryPrice=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT); if(point<=0) point=0.00001;
   rp.slPrice=rp.entryPrice - 100*point; rp.tpCount=1; rp.tpPrice[0]=rp.entryPrice + 200*point; rp.sizingMode=SIZING_AUTO_RISK; rp.riskValue=1.0;
   MM_RiskResult rr; engRisk.Calculate(rp, rctx, rr);
   Assert(rr.blocked && !rr.valid, "aggregate open-risk budget blocks sizing");
   Assert(HasWarn(rr,"BLOCK") || HasWarn(rr,"budget") || HasCap(rr,"cap:aggregate_open_risk") || HasCap(rr,"cap:DD_remaining"), "aggregate/open-risk block reason present");

   // 6) Max drawdown consistency (equity-peak DD computed by protection)
   CProtection pdd; pdd.Init();
   double ddpct=pdd.CurrentDrawdownPct();
   Assert(ddpct>=0.0 && MathIsValidNumber(ddpct), "max drawdown pct computed consistently");

   // 7) Risk-reducing operations preserved: breached limits block new risk-increasing entry only;
   //    position management (BE/trail/close/SL-tighten/partial close) is not guard-gated in EA/router entry path.
   MM_GuardConfig blocked=cfg; blocked.requireTerminalConnected=false; blocked.requireTradeAllowed=false; blocked.requireExpertEnabled=false; blocked.requireAccountTradeAllowed=false;
   blocked.maxTradesPerDay=1; blocked.tradesToday=5; blocked.dailyLossLimitPct=1.0; blocked.dailyLossPct=5.0; blocked.inCooldown=true;
   bool entryAllowed = eng.CanExecute(plan, blocked, rep);
   Assert(!entryAllowed && rep.hasBlock, "breached limits block new risk-increasing entry");

   if(g_fail==0) Print("ProtectionLimits_Test: ALL PASS"); else Print("ProtectionLimits_Test: FAIL count=",g_fail);
}
//+------------------------------------------------------------------+
