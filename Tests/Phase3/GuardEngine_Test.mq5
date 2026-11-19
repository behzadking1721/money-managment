//+------------------------------------------------------------------+
//|                                             GuardEngine_Test.mq5 |
//|      Phase 3 + 2.3: unified guards, priority, sink, limits      |
//+------------------------------------------------------------------+
#property script_show_inputs
#include "..\\..\\Include\\Guards\\GuardEngine.mqh"
#include "..\\..\\Include\\Core\\RejectSink.mqh"

int g_fail=0; int g_sinkCalls=0; string g_lastCode="";
void Assert(bool c,const string n){ if(!c){Print("FAIL: ",n); g_fail++;} else Print("OK: ",n); }

class CSinkMock : public IRejectSink
{
public:
   virtual void OnExecutionReject(const string symbol,const string reasonCode,const string messageEN,uint retcode,const string context){ g_sinkCalls++; g_lastCode=reasonCode; }
   virtual void OnGuardReject(const MM_GuardResult &gr,const string symbol){ g_sinkCalls++; g_lastCode=gr.reasonCode; }
};

void OnStart()
{
   g_fail=0; g_sinkCalls=0; g_lastCode="";
   CSinkMock sink; CGuardEngine eng; eng.Init(GetPointer(sink), true);
   MM_TradePlan plan; plan.Reset(); plan.symbol=_Symbol; plan.side=POSITION_TYPE_BUY; plan.lot=0.1;
   plan.entryPrice=SymbolInfoDouble(_Symbol,SYMBOL_ASK); plan.slPrice=plan.entryPrice-200*SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   MM_GuardConfig cfg; cfg.Reset();

   MM_GuardReport rep;
   // Base: may block on connection in some envs; force permission checks off for isolation
   cfg.requireTerminalConnected=false; cfg.requireTradeAllowed=false; cfg.requireExpertEnabled=false; cfg.requireAccountTradeAllowed=false;
   bool ok=eng.CanExecute(plan,cfg,rep);
   Assert(ok && rep.allowed, "allow when clean");

   // Protection block - daily loss
   MM_GuardConfig c1=cfg; c1.dailyLossLimitPct=5.0; c1.dailyLossPct=5.0;
   ok=eng.CanExecute(plan,c1,rep);
   Assert(!ok && rep.hasBlock && rep.firstBlock.reasonCode=="DAILY_LOSS_LIMIT", "daily loss block");
   Assert(g_sinkCalls>0 && g_lastCode=="DAILY_LOSS_LIMIT", "block routed to sink");

   // Prop block (higher priority than protection)
   g_sinkCalls=0;
   MM_GuardConfig c2=cfg; c2.accountMode=ACCOUNT_PROP; c2.propEnabled=true; c2.propDailyLossLimitPct=5.0; c2.propDailyLossUsedPct=5.0; c2.dailyLossLimitPct=5.0; c2.dailyLossPct=5.0;
   ok=eng.CanExecute(plan,c2,rep);
   Assert(!ok && rep.firstBlock.guardId=="Prop", "priority Prop before Protection");

   // News stale warn by default
   g_sinkCalls=0;
   MM_GuardConfig c3=cfg; c3.newsEnabled=true; c3.newsDataAvailable=false; c3.newsIsStale=true; c3.newsOfflineBlock=false;
   ok=eng.CanExecute(plan,c3,rep);
   Assert(ok && rep.hasWarn, "news stale warn allows by default");
   Assert(g_sinkCalls>0, "warn routed to sink");

   // News blackout block when configured
   MM_GuardConfig c4=cfg; c4.newsEnabled=true; c4.newsInBlackout=true; c4.newsBlackoutOnHigh=true;
   ok=eng.CanExecute(plan,c4,rep);
   Assert(!ok && rep.firstBlock.reasonCode=="NEWS_BLACKOUT", "news blackout blocks");

   // Session block
   MM_GuardConfig c5=cfg; c5.sessionFilterEnabled=true; c5.sessionAllowed=false;
   ok=eng.CanExecute(plan,c5,rep);
   Assert(!ok && rep.firstBlock.reasonCode=="SESSION_BLOCK", "session block");

   // Spread block vs warn
   MM_GuardConfig c6=cfg; c6.spreadCheckEnabled=true; c6.spreadPoints=50; c6.maxSpreadPoints=30;
   ok=eng.CanExecute(plan,c6,rep);
   Assert(!ok && rep.firstBlock.reasonCode=="SPREAD_TOO_HIGH", "spread block");
   MM_GuardConfig c7=cfg; c7.spreadCheckEnabled=true; c7.spreadPoints=25; c7.maxSpreadPoints=30; c7.spreadWarnPoints=20;
   ok=eng.CanExecute(plan,c7,rep);
   Assert(ok && rep.hasWarn, "spread warn");

   // Preview should not call sink
   g_sinkCalls=0;
   MM_GuardConfig c8=cfg; c8.dailyLossLimitPct=5.0; c8.dailyLossPct=5.0;
   ok=eng.Preview(plan,c8,rep);
   Assert(!ok && g_sinkCalls==0, "preview no sink side-effects");

   // Phase 2.3: weekly/monthly loss, max drawdown, daily trades, consecutive loss, cooldown
   MM_GuardConfig c9=cfg; c9.weeklyLossLimitPct=5.0; c9.weeklyLossPct=5.0;
   ok=eng.CanExecute(plan,c9,rep);
   Assert(!ok && rep.hasBlock && rep.firstBlock.reasonCode=="WEEKLY_LOSS_LIMIT", "weekly loss block");

   MM_GuardConfig c10=cfg; c10.monthlyLossLimitPct=8.0; c10.monthlyLossPct=8.0;
   ok=eng.CanExecute(plan,c10,rep);
   Assert(!ok && rep.hasBlock && rep.firstBlock.reasonCode=="MONTHLY_LOSS_LIMIT", "monthly loss block");

   MM_GuardConfig c11=cfg; c11.maxDrawdownPct=10.0; c11.currentDrawdownPct=10.0;
   ok=eng.CanExecute(plan,c11,rep);
   Assert(!ok && rep.hasBlock && rep.firstBlock.reasonCode=="MAX_DRAWDOWN", "max drawdown block");

   MM_GuardConfig c12=cfg; c12.maxTradesPerDay=3; c12.tradesToday=3;
   ok=eng.CanExecute(plan,c12,rep);
   Assert(!ok && rep.hasBlock && rep.firstBlock.reasonCode=="MAX_TRADES_DAY", "daily trade limit block");

   MM_GuardConfig c13=cfg; c13.maxConsecLoss=2; c13.consecLosses=2; c13.inCooldown=false;
   ok=eng.CanExecute(plan,c13,rep);
   Assert(!ok && rep.hasBlock && rep.firstBlock.reasonCode=="CONSEC_LOSS_LIMIT", "consecutive loss limit block");

   MM_GuardConfig c14=cfg; c14.inCooldown=true; c14.cooldownMinutes=30;
   ok=eng.CanExecute(plan,c14,rep);
   Assert(!ok && rep.hasBlock && rep.firstBlock.reasonCode=="COOLDOWN", "cooldown block");

   // Below limits allowed
   MM_GuardConfig c15=cfg; c15.weeklyLossLimitPct=5.0; c15.weeklyLossPct=4.9; c15.monthlyLossLimitPct=8.0; c15.monthlyLossPct=7.9; c15.maxDrawdownPct=10.0; c15.currentDrawdownPct=9.9; c15.maxTradesPerDay=3; c15.tradesToday=2; c15.maxConsecLoss=3; c15.consecLosses=2; c15.inCooldown=false;
   ok=eng.CanExecute(plan,c15,rep);
   Assert(ok && rep.allowed && !rep.hasBlock, "below all limits allowed");

   if(g_fail==0) Print("GuardEngine_Test: ALL PASS"); else Print("GuardEngine_Test: FAIL count=",g_fail);
}
