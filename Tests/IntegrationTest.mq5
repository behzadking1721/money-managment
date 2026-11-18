//+------------------------------------------------------------------+
//|                                              IntegrationTest.mq5 |
//|              Phase 7 integration smoke checks (script)           |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "..\\Include\\Core\\Logger.mqh"
#include "..\\Include\\Core\\ExecutionPolicy.mqh"
#include "..\\Include\\Core\\StopsValidator.mqh"
#include "..\\Include\\Core\\Contracts.mqh"
#include "..\\Include\\Guards\\GuardEngine.mqh"
#include "..\\Include\\News\\NewsManager.mqh"
#include "..\\Include\\Protection\\Protection.mqh"
#include "..\\Include\\PropFirm/PropFirm.mqh"
#include "..\\Include\\Statistics\\Statistics.mqh"
#include "..\\Include\\Utils\\Common.mqh"

int g_fail=0; int g_pass=0;
void Assert(bool cond,const string name)
{
   if(cond){ g_pass++; Print("PASS: ",name); }
   else { g_fail++; Print("FAIL: ",name); }
}

void OnStart()
{
   g_fail=0; g_pass=0;
   Print("=== Phase 7 Integration Smoke Test ===");

   // Logger
   g_mmLog.Init("mm_phase7_test");
   g_mmLog.Info("TEST","logger init");
   g_mmLog.Warn("TEST","logger warn");
   Assert(true, "logger init/log does not crash");

   // News staleness/source
   CNewsManager news; news.Init();
   news.SetStaleAfterSec(60);
   Assert(news.HasData(), "news has seeded/manual data");
   string src=news.SourceTag();
   Assert(src=="manual" || src=="stale" || src=="cache" || src=="live", "news source tag available");
   news.MarkUpdated("live", true);
   Assert(news.SourceTag()=="live" || news.SourceTag()=="stale", "news mark updated sets source logic");

   // Protection DD/remaining
   CProtection prot; prot.Init();
   prot.SyncPeaks();
   prot.RecordTrade(-50.0);
   double dlp = prot.DailyLossPct();
   Assert(dlp>=0.0, "protection daily loss pct computed");
   double remD = prot.RemainingDailyDDMoney(5.0);
   Assert(remD>=0.0, "protection remaining daily DD money computed");
   double remM = prot.RemainingMaxDDMoney(10.0, true);
   Assert(remM>=0.0, "protection remaining max DD money computed");

   // Prop firm DD helpers
   CPropFirm prop; prop.Init();
   SPropFirmRules rules; prop.LoadPreset("FTMO", rules); prop.Enable(rules);
   double usedDaily = prop.DailyLossUsedPct(100.0, 10000.0, 10000.0);
   double remDaily = prop.RemainingDailyDDMoney(100.0, 10000.0, 10000.0);
   double remMax = prop.RemainingMaxDDMoney(9500.0, 10000.0, 10000.0);
   Assert(usedDaily>=0.0, "prop daily DD used pct computed");
   Assert(remDaily>=0.0, "prop remaining daily DD computed");
   Assert(remMax>=0.0, "prop remaining max DD computed");

   // Execution policy retcodes
   CExecutionPolicy exec;
   Assert(exec.IsRetryable(TRADE_RETCODE_REQUOTE), "requote retryable");
   Assert(exec.IsTerminalBlock(TRADE_RETCODE_INVALID_STOPS), "invalid stops terminal");
   Assert(exec.IsSuccess(TRADE_RETCODE_DONE_PARTIAL), "done partial success");
   string unk = exec.RetcodeReason(65535);
   Assert(unk=="RETCODE_UNKNOWN", "unknown retcode classified");
   Assert(exec.RetcodeReason(TRADE_RETCODE_NO_MONEY)!="", "known retcode reason mapped");

   // Stops validator on live symbol
   CStopsValidator stops;
   MM_StopsCheck chk; chk.Reset();
   bool propsOk = stops.SymbolPropsOk(_Symbol, chk);
   Assert(propsOk, "symbol properties available for current symbol");
   MM_TradePlan plan; plan.Reset(); plan.symbol=_Symbol; plan.side=POSITION_TYPE_BUY; plan.isPending=false;
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK); double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   plan.entryPrice=ask; plan.slPrice=ask - 200*point; plan.tpCount=1; plan.tpPrice[0]=ask + 300*point;
   plan.lot = NormalizeLot(_Symbol, SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN));
   MM_StopsCheck vchk; bool vres = stops.ValidatePlan(plan, vchk);
   // plan may be blocked by margin/stops in some environments; validation must execute and set reason when blocked
   Assert(vres==vchk.ok, "validate plan returns consistent ok state");
   if(!vres) Print("INFO: ValidatePlan blocked as expected in this context reason=", vchk.reasonCode);

   // Statistics aggregation / open risk (event-driven)
   CStatistics stats; stats.Init("MoneyManager_itest.csv"); stats.SetAccountMode(ACCOUNT_PERSONAL);
   MM_TradeEvent ev; ev.Reset(); ev.symbol=_Symbol; ev.positionId=777001; ev.ticket=777001; ev.order=777001;
   ev.side=POSITION_TYPE_BUY; ev.volume=NormalizeLot(_Symbol, SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN));
   ev.price=ask; ev.sl=plan.slPrice; ev.timeServer=TimeCurrent(); ev.type=MM_EVENT_OPEN;
   stats.RegisterPlannedRisk(_Symbol, 100.0, ACCOUNT_PERSONAL);
   stats.OnTradeEvent(ev);
   double openRisk = stats.CalcOpenRiskMoney(0, _Symbol);
   Assert(openRisk>=0.0, "open risk computed after open event");

   MM_TradeEvent pc; pc=ev; pc.type=MM_EVENT_PARTIAL_FILL; pc.reasonCode="PARTIAL_CLOSE";
   pc.profit=1.0; pc.volume=MathMax(SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN)/2.0, SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP));
   pc.timeServer=TimeCurrent()+1;
   stats.OnTradeEvent(pc);

   MM_TradeEvent cl; cl=ev; cl.type=MM_EVENT_CLOSE; cl.reasonCode="CLOSE"; cl.profit=2.0; cl.price=ask+50*point; cl.timeServer=TimeCurrent()+2;
   stats.OnTradeEvent(cl);
   MM_Kpi k; k.Reset(); stats.GetKpi(k);
   Assert(k.trades>=1, "statistics records closed trade(s)");

   // Guards: news stale warn by default, block when offline-block, session block
   CGuardEngine guards; guards.Init(NULL,false);
   MM_GuardConfig cfg; cfg.Reset();
   cfg.requireTerminalConnected=false; cfg.requireTradeAllowed=false; cfg.requireExpertEnabled=false; cfg.requireAccountTradeAllowed=false;
   cfg.newsEnabled=true; cfg.newsDataAvailable=true; cfg.newsIsStale=true; cfg.newsOfflineBlock=false; cfg.newsInBlackout=false;
   MM_GuardReport rep; bool okNewsWarn = guards.CanExecute(plan,cfg,rep);
   Assert(okNewsWarn && rep.hasWarn, "news stale warns by default");

   cfg.newsOfflineBlock=true; okNewsWarn = guards.CanExecute(plan,cfg,rep);
   Assert(!okNewsWarn && rep.hasBlock, "news stale blocks when offline block enabled");

   MM_GuardConfig cfg2; cfg2.Reset();
   cfg2.requireTerminalConnected=false; cfg2.requireTradeAllowed=false; cfg2.requireExpertEnabled=false; cfg2.requireAccountTradeAllowed=false;
   cfg2.sessionFilterEnabled=true; cfg2.sessionAllowed=false;
   MM_GuardReport rep2; bool okSess = guards.CanExecute(plan,cfg2,rep2);
   Assert(!okSess && rep2.hasBlock, "session filter blocks when not allowed");

   Print("=== Phase 7 Integration Smoke Test: PASS=",g_pass," FAIL=",g_fail," ===");
}
