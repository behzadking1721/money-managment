//+------------------------------------------------------------------+
//|                                                MoneyManager.mq5  |
//|     Phase 7: hardening wiring + Phase 2.1 safety corrections     |
//|     Phase 2.3: risk protection & trade limits (exposure/counting)|
//+------------------------------------------------------------------+
#property copyright "Money Manager"
#property version   "1.73"
#property strict

#include "Include/Utils/Common.mqh"
#include "Include/Core/Contracts.mqh"
#include "Include/Core/Logger.mqh"
#include "Include/Core/RiskEngine.mqh"
#include "Include/Core/StopsValidator.mqh"
#include "Include/Core/ExecutionPolicy.mqh"
#include "Include/Core/ExecutionRouter.mqh"
#include "Include/Core/StopLoss.mqh"
#include "Include/Core/TakeProfit.mqh"
#include "Include/Core/OrderManager.mqh"
#include "Include/Core/PositionManager.mqh"
#include "Include/State/StateStore.mqh"
#include "Include/State/RecoveryEngine.mqh"
#include "Include/Trade/TradeLifecycle.mqh"
#include "Include/Guards/GuardEngine.mqh"
#include "Include/Protection/Protection.mqh"
#include "Include/PropFirm/PropFirm.mqh"
#include "Include/News/NewsManager.mqh"
#include "Include/Session/SessionManager.mqh"
#include "Include/Profiles/Profiles.mqh"
#include "Include/Alerts/Alerts.mqh"
#include "Include/Statistics/Statistics.mqh"
#include "Include/UI/PanelShell.mqh"
#include "Include/UI/PositionDragTool.mqh"

input group "=== Account ==="
input ENUM_MM_ACCOUNT_MODE InpAccountMode = ACCOUNT_PERSONAL;

input group "=== Risk ==="
input ENUM_MM_SIZING_MODE InpSizingMode = SIZING_AUTO_RISK;
input double InpRiskPercent = 1.0;
input double InpManualLot = 0.10;
input double InpMaxRiskPercent = 2.0;
input double InpMinRiskPercent = 0.25;
input double InpDailyLossLimit = 5.0;
input double InpDailyProfitLimit = 0.0;
input double InpWeeklyLossLimit = 0.0;
input double InpMonthlyLossLimit = 0.0;
input double InpMaxDrawdown = 10.0;
input int    InpMaxTradesPerDay = 0;
input int    InpMaxConsecLoss = 3;
input int    InpCooldownMinutes = 60;
input int    InpSlippage = MM_SLIPPAGE_DEFAULT;

input group "=== Trailing / BE ==="
input ENUM_BE_MODE InpBEMode = BE_PLUS_POINTS;
input double InpBEPoints = 10;
input ENUM_TRAILING_MODE InpTrailMode = TRAIL_NONE;
input double InpTrailValue = 20;
input int InpMaxMinutesInTrade = 0;

input group "=== Prop Firm ==="
input bool InpPropFirmEnabled = false;
input string InpPropPreset = "FTMO";
input ENUM_PROP_MODE InpPropMode = PROP_CHALLENGE;

input group "=== News / Session / Spread ==="
input bool InpNewsEnabled = true;
input bool InpNewsBlackout = false;
input bool InpNewsOfflineBlock = false;
input int InpNewsMinutesBefore = 15;
input int InpNewsMinutesAfter = 15;
input bool InpSessionFilter = false;
input double InpMaxSpreadPoints = 0.0;
input double InpSpreadWarnPoints = 0.0;

input group "=== UI ==="
input bool InpUILangFA = false;
input int  InpMagic = MM_MAGIC_DEFAULT;

CRiskEngine g_risk; CStopsValidator g_stops; CExecutionPolicy g_execPolicy; CExecutionRouter g_router;
CPositionManager g_positions; CProtection g_prot; CPropFirm g_prop; CNewsManager g_news;
CSessionManager g_session; CAlertManager g_alerts; CStatistics g_stats; CProfileManager g_profiles;
CStateStore g_store; CTradeLifecycle g_lifecycle; CGuardEngine g_guards;
CRecoveryEngine g_recovery;
CPanelShell g_ui; CDragTool g_drag; CPositionDragTool g_posDrag;

MM_RiskContext g_riskCtx; MM_GuardConfig g_guardCfg; MM_ExecPolicy g_policy;
MM_DragTemplate g_tpl; bool g_tplSaved=false;
bool g_lastConnected=true;
bool g_lastNewsBlackout=false;

// Phase 2.1: runtime-only account-switch detection (never persisted/logged as identity)
// Uses MT5 account login value in memory only for best-effort in-session switch detection.
// Restart continuity cannot be proven without forbidden persistent identity; handled conservatively.
long g_rtAccountMarker = -1;
bool g_rtMarkerInitialized = false;

//--- Phase 2.3: completed-trade aggregation & dedup (authoritative protection accounting)
// Accounting basis: realized net per completed directional trade lifecycle =
//   sum(profit + commission + swap + fee) from lifecycle deals/position-linked adjustments included exactly once.
// Daily/weekly/monthly boundaries and cooldown timing use MT5 server time (TimeTradeServer, fallback TimeCurrent).
// Exposure counting (daily trade limit): actual risk-increasing exposure on DEAL_ENTRY_IN and on netting reversal
//   opening exposure (DEAL_ENTRY_INOUT leaving opposite position open), deduped by order ticket.
// Consecutive streak/cooldown: updated once per completed directional trade outcome.
// Netting note: DEAL_ENTRY_INOUT can preserve POSITION_IDENTIFIER while replacing POSITION_TICKET; it closes previous
//   directional exposure and opens opposite exposure. Previous and new directional trades must not be merged.
//   Reversal deal profit is realized on closed portion; commission/swap/fee may not be reliably separable between
//   close/open sides -> attributed conservatively to the closed lifecycle (no split invention). Limitation documented.
#define MM_MAX_POS_TRACK 128
#define MM_MAX_SEEN_DEALS 512
struct MM_PosCloseTrack
{
   long     positionId;      // DEAL_POSITION_ID / POSITION_IDENTIFIER (stable)
   string   symbol;
   double   netRealized;     // sum(profit+commission+swap+fee) aggregated once per lifecycle
   double   closedVolume;
   bool     seenEntry;
   bool     finalized;
   datetime lastEventTime;
   void Reset(){ positionId=0; symbol=""; netRealized=0; closedVolume=0; seenEntry=false; finalized=false; lastEventTime=0; }
};
MM_PosCloseTrack g_posTrack[MM_MAX_POS_TRACK];
int g_posTrackCount=0;
ulong g_seenDealTickets[MM_MAX_SEEN_DEALS];
int g_seenDealCount=0;

int FindActivePosTrack(long positionId)
{
   if(positionId<=0) return -1;
   for(int i=0;i<g_posTrackCount;i++) if(g_posTrack[i].positionId==positionId && !g_posTrack[i].finalized) return i;
   return -1;
}
int AllocPosTrack(long positionId,const string symbol)
{
   int idx=FindActivePosTrack(positionId);
   if(idx>=0) return idx;
   for(int i=0;i<g_posTrackCount;i++) if(g_posTrack[i].positionId==0){ g_posTrack[i].Reset(); g_posTrack[i].positionId=positionId; g_posTrack[i].symbol=symbol; return i; }
   // reuse finalized slot (accounting already done) for new logical lifecycle on same identifier
   for(int i=0;i<g_posTrackCount;i++) if(g_posTrack[i].finalized){ g_posTrack[i].Reset(); g_posTrack[i].positionId=positionId; g_posTrack[i].symbol=symbol; return i; }
   if(g_posTrackCount<MM_MAX_POS_TRACK){ idx=g_posTrackCount++; g_posTrack[idx].Reset(); g_posTrack[idx].positionId=positionId; g_posTrack[idx].symbol=symbol; return idx; }
   idx=0; g_posTrack[idx].Reset(); g_posTrack[idx].positionId=positionId; g_posTrack[idx].symbol=symbol; return idx;
}
bool IsDealSeen(ulong dealTicket)
{
   if(dealTicket==0) return false;
   int n=g_seenDealCount>MM_MAX_SEEN_DEALS?MM_MAX_SEEN_DEALS:g_seenDealCount;
   for(int i=0;i<n;i++) if(g_seenDealTickets[i]==dealTicket) return true;
   return false;
}
void MarkDealSeen(ulong dealTicket)
{
   if(dealTicket==0) return;
   if(g_seenDealCount < MM_MAX_SEEN_DEALS) g_seenDealTickets[g_seenDealCount++]=dealTicket;
   else { g_seenDealTickets[g_seenDealCount % MM_MAX_SEEN_DEALS]=dealTicket; g_seenDealCount = MM_MAX_SEEN_DEALS + ((g_seenDealCount-MM_MAX_SEEN_DEALS+1)%MM_MAX_SEEN_DEALS); }
}
bool PositionStillOpen(long positionId,const string symbol, ENUM_POSITION_TYPE expectedSide=POSITION_TYPE_BUY)
   {
      if(positionId<=0) return false;
      if(PositionSelectByTicket((ulong)positionId))
      {
         if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==expectedSide)
            return (PositionGetDouble(POSITION_VOLUME)>0.0);
         return false; // direction flipped: netting reversal, not still open
      }
      if(symbol!="" && PositionSelect(symbol))
      {
         // netting: POSITION_IDENTIFIER stable across reversal (ticket may change)
         if(((long)PositionGetInteger(POSITION_IDENTIFIER)==positionId || (long)PositionGetInteger(POSITION_TICKET)==positionId)
            && (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==expectedSide)
            return (PositionGetDouble(POSITION_VOLUME)>0.0);
         return false; // id matches but direction flipped -> netting reversal
      }
      return false;
   }
void FinalizeCompletedLifecycle(int idx, datetime evTime)
{
   if(idx<0 || idx>=MM_MAX_POS_TRACK) return;
   if(g_posTrack[idx].finalized) return;
   double net = g_posTrack[idx].netRealized;
   g_prot.SyncPeriods(evTime);
   g_prot.RecordCompletedTrade(net);
   if(net < 0.0)
      g_prot.ApplyConsecLossPolicy(EffMaxConsecLoss(), EffCooldownMinutes(), evTime);
   else
      g_prot.UpdateCooldown(evTime);
   if(InpPropFirmEnabled && g_prop.IsEnabled()) g_prop.RecordTradingDay(g_prot.DailyProfit());
   g_posTrack[idx].finalized=true;
   g_mmLog.Info("TRADE_COMPLETED","pos="+(string)g_posTrack[idx].positionId+" net="+DoubleToString(net,2)+" dailyLoss="+DoubleToString(g_prot.DailyLoss(),2)+" consecLosses="+(string)g_prot.ConsecutiveLosses()+" tradesToday="+(string)g_prot.TradesToday());
}

bool PropExplicitEnabled(){ return (InpPropFirmEnabled || InpAccountMode==ACCOUNT_PROP); }
ENUM_MM_ACCOUNT_MODE EffectiveAccountMode(){ return InpAccountMode; }

double EffDailyLossLimit(){ MM_ProfileRecord pr; if(g_profiles.GetActive(pr)) return pr.dailyLossLimitPct; return InpDailyLossLimit; }
double EffDailyProfitLimit(){ MM_ProfileRecord pr; if(g_profiles.GetActive(pr)) return pr.dailyProfitLimitPct; return InpDailyProfitLimit; }
double EffWeeklyLossLimit(){ MM_ProfileRecord pr; if(g_profiles.GetActive(pr)) return pr.weeklyLossLimitPct; return InpWeeklyLossLimit; }
double EffMonthlyLossLimit(){ MM_ProfileRecord pr; if(g_profiles.GetActive(pr)) return pr.monthlyLossLimitPct; return InpMonthlyLossLimit; }
double EffMaxDrawdown(){ MM_ProfileRecord pr; if(g_profiles.GetActive(pr)) return pr.maxDrawdownPct; return InpMaxDrawdown; }
int    EffMaxTradesPerDay(){ MM_ProfileRecord pr; if(g_profiles.GetActive(pr)) return (pr.maxTradesPerDay>0?pr.maxTradesPerDay:InpMaxTradesPerDay); return InpMaxTradesPerDay; }
int    EffMaxConsecLoss(){ MM_ProfileRecord pr; if(g_profiles.GetActive(pr)) return (pr.maxConsecLoss>0?pr.maxConsecLoss:InpMaxConsecLoss); return InpMaxConsecLoss; }
int    EffCooldownMinutes(){ MM_ProfileRecord pr; if(g_profiles.GetActive(pr)) return (pr.cooldownMinutes>0?pr.cooldownMinutes:InpCooldownMinutes); return InpCooldownMinutes; }
double EffMaxSpread(){ MM_ProfileRecord pr; if(g_profiles.GetActive(pr) && pr.maxSpreadPoints>0) return pr.maxSpreadPoints; return InpMaxSpreadPoints; }
bool   EffNewsEnabled(){ MM_ProfileRecord pr; if(g_profiles.GetActive(pr)) return pr.newsEnabled; return InpNewsEnabled; }
bool   EffNewsBlackout(){ MM_ProfileRecord pr; if(g_profiles.GetActive(pr)) return (pr.newsBlackoutHigh || InpNewsBlackout); return InpNewsBlackout; }
bool   EffNewsOfflineBlock(){ MM_ProfileRecord pr; if(g_profiles.GetActive(pr)) return (pr.newsOfflineBlock || InpNewsOfflineBlock); return InpNewsOfflineBlock; }
int    EffNewsMinutesBefore(){ MM_ProfileRecord pr; if(g_profiles.GetActive(pr) && pr.newsBeforeMin>0) return pr.newsBeforeMin; return InpNewsMinutesBefore; }
int    EffNewsMinutesAfter(){ MM_ProfileRecord pr; if(g_profiles.GetActive(pr) && pr.newsAfterMin>0) return pr.newsAfterMin; return InpNewsMinutesAfter; }

bool StoreReadyForRiskIncreasing()
{
   return g_store.IsOperational() && !g_recovery.RiskIncreasingBlocked();
}

void RefreshRiskContext()
{
   ENUM_MM_ACCOUNT_MODE mode = EffectiveAccountMode();
   bool propMode = PropExplicitEnabled();
   // Phase 7/8: Personal/default uses equity/balance basis unless explicitly overridden; prop mode may use AllowedDD.
   ENUM_MM_RISK_BASIS basis = (propMode && mode==ACCOUNT_PROP) ? MM_BASIS_ALLOWED_DD : MM_BASIS_EQUITY;
   MM_ProfileRecord pr; bool hasProf = g_profiles.GetActive(pr);
   if(hasProf)
   {
      if(pr.profile.riskBasis=="AllowedDD") basis = MM_BASIS_ALLOWED_DD;
      else if(pr.profile.riskBasis=="Balance") basis = MM_BASIS_BALANCE_DAY;
      else if(pr.profile.riskBasis=="Equity") basis = MM_BASIS_EQUITY;
   }
   // Keep prop-firm specific basis inactive for personal mode unless prop is explicitly configured.
   if(!(propMode && mode==ACCOUNT_PROP) && basis==MM_BASIS_ALLOWED_DD) basis = MM_BASIS_EQUITY;

   double bal=AccountInfoDouble(ACCOUNT_BALANCE);
   double eq =AccountInfoDouble(ACCOUNT_EQUITY);
   datetime srv=TimeTradeServer(); if(srv==0) srv=TimeCurrent();
   g_prot.SyncPeriods(srv);
   g_prot.UpdateCooldown(srv);
   double dayStartBal = g_prot.DayStartBalance(); if(dayStartBal<=0) dayStartBal=bal;
   double dayStartEq  = g_prot.DayStartEquity();  if(dayStartEq<=0)  dayStartEq=eq;
   g_prot.SyncPeaks();

   double remDaily=0, remMax=0;
   double dailyLossMoney = g_prot.DailyLoss();
   double dLim = EffDailyLossLimit();
   double mLim = EffMaxDrawdown();

   if(propMode && g_prop.IsEnabled() && mode==ACCOUNT_PROP)
   {
      g_prop.SyncBaseline(g_prot.StartBalance(), g_prot.PeakEquity(), g_prot.PeakBalance());
      SPropFirmRules r=g_prop.GetRules();
      remDaily = g_prop.RemainingDailyDDMoney(dailyLossMoney, dayStartBal, dayStartEq);
      remMax   = g_prop.RemainingMaxDDMoney(eq, g_prot.PeakEquity(), g_prot.StartBalance());
      if(r.maxDailyLoss<=0 && dLim>0) remDaily = g_prot.RemainingDailyDDMoney(dLim);
      if(r.maxTotalDD<=0 && mLim>0) remMax = g_prot.RemainingMaxDDMoney(mLim, (r.ddReference==DD_FROM_EQUITY));
   }
   else
   {
      if(dLim>0) remDaily = g_prot.RemainingDailyDDMoney(dLim);
      if(mLim>0) remMax = g_prot.RemainingMaxDDMoney(mLim, true);
   }

   double minRisk = InpMinRiskPercent;
   double maxRisk = InpMaxRiskPercent;
   if(hasProf){ if(pr.profile.minRiskPercent>0) minRisk=pr.profile.minRiskPercent; if(pr.profile.maxRiskPercent>0) maxRisk=pr.profile.maxRiskPercent; }

   g_risk.BuildContext(g_riskCtx, mode, basis,
                       dayStartBal, remDaily, remMax,
                       0, 0, false, minRisk, maxRisk, 0,
                       0, "");
   // Authoritative aggregate open-risk protection for new risk-increasing sizing/preflight (no duplicate formulas).
   g_riskCtx.openRiskMoney = g_stats.CalcOpenRiskMoney(InpMagic, "");
}

void RefreshGuardConfig()
{
   g_guardCfg.Reset();
   datetime srv=TimeTradeServer(); if(srv==0) srv=TimeCurrent();
   g_prot.SyncPeriods(srv);
   g_prot.UpdateCooldown(srv);

   ENUM_MM_ACCOUNT_MODE mode = EffectiveAccountMode();
   bool propExplicit = PropExplicitEnabled();

   g_guardCfg.accountMode = mode;
   g_guardCfg.protectionEnabled = true;
   g_guardCfg.dailyLossLimitPct = EffDailyLossLimit();
   g_guardCfg.dailyProfitLimitPct = EffDailyProfitLimit();
   g_guardCfg.weeklyLossLimitPct = EffWeeklyLossLimit();
   g_guardCfg.monthlyLossLimitPct = EffMonthlyLossLimit();
   g_guardCfg.maxDrawdownPct = EffMaxDrawdown();
   g_guardCfg.maxTradesPerDay = EffMaxTradesPerDay();
   g_guardCfg.maxConsecLoss = EffMaxConsecLoss();
   g_guardCfg.cooldownMinutes = EffCooldownMinutes();

   double dayStartBal = g_prot.DayStartBalance(); if(dayStartBal<=0) dayStartBal=AccountInfoDouble(ACCOUNT_BALANCE);
   double dayStartEq  = g_prot.DayStartEquity();  if(dayStartEq<=0)  dayStartEq =AccountInfoDouble(ACCOUNT_EQUITY);
   g_prot.SyncPeaks();

   // Period loss % from realized completed-trade accounting (server-time boundaries), DD from equity peak (consistent with CProtection).
   g_guardCfg.dailyLossPct = g_prot.DailyLossPct(dayStartBal);
   g_guardCfg.dailyProfitPct = g_prot.DailyProfitPct(dayStartBal);
   g_guardCfg.weeklyLossPct = g_prot.WeeklyLossPct();
   g_guardCfg.monthlyLossPct = g_prot.MonthlyLossPct();
   g_guardCfg.currentDrawdownPct = g_prot.CurrentDrawdownPct();
   g_guardCfg.tradesToday = g_prot.TradesToday();
   g_guardCfg.consecLosses = g_prot.ConsecutiveLosses();
   g_guardCfg.inCooldown = !g_prot.CheckCooldown();

   // Phase 7/8: prop constraints are not implicitly enforced in Personal mode/default.
   g_guardCfg.propEnabled = propExplicit;
   if(g_guardCfg.propEnabled && g_prop.IsEnabled() && mode==ACCOUNT_PROP)
   {
      // keep baselines/peaks aligned to configured DD references for accurate used/remaining reporting
      g_prop.SyncBaseline(g_prot.StartBalance(), g_prot.PeakEquity(), g_prot.PeakBalance());
      SPropFirmRules r=g_prop.GetRules();
      g_guardCfg.propDailyLossLimitPct = r.maxDailyLoss;
      g_guardCfg.propMaxTotalDDPct = r.maxTotalDD;
      g_guardCfg.propDailyLossUsedPct = g_prop.DailyLossUsedPct(g_prot.DailyLoss(), dayStartBal, dayStartEq);
      g_guardCfg.propTotalDDUsedPct = g_prop.TotalDDUsedPct(AccountInfoDouble(ACCOUNT_EQUITY), g_prot.PeakEquity(), g_prot.StartBalance());
      g_guardCfg.propMaxPositionSizePct = r.maxPositionSize;
      // Consistency/min-trading-days require persisted multi-day history; not persisted -> do not enforce falsely.
      g_guardCfg.propConsistencyEnabled = (r.consistencyPercent>0 && g_prop.ConsistencyEnforcementReliable());
      g_guardCfg.propConsistencyPct = r.consistencyPercent;
      double todayProfitPct = (dayStartBal>0)?(g_prot.DailyProfit()/dayStartBal*100.0):0.0;
      g_guardCfg.propTodayProfitPct = todayProfitPct;
      g_guardCfg.propWeekendClose = r.weekendClose;
      g_guardCfg.propMaxTradesPerDay = (r.maxDailyLoss>=0 ? EffMaxTradesPerDay() : EffMaxTradesPerDay()); // trades cap driven by configured effective limit
      if(EffMaxTradesPerDay()>0) g_guardCfg.propMaxTradesPerDay = EffMaxTradesPerDay();
      // best-effort runtime snapshot only (unverified across restart)
      g_prop.RecordDaySnapshot(srv, g_prot.DailyProfit(), g_prot.TradesToday()>0);
   }

   bool newsEnabled = EffNewsEnabled();
   int nb = EffNewsMinutesBefore(); if(nb < 0) nb = 0;
   int na = EffNewsMinutesAfter(); if(na < 0) na = 0;
   // Blackout evaluated against known events only; stale/unavailable handled explicitly by guards (warn/block per config).
   bool inBlackout = (newsEnabled && g_news.IsNewsBlackout(_Symbol, nb, na, 3));
   g_guardCfg.newsEnabled = newsEnabled;
   g_guardCfg.newsBlackoutOnHigh = EffNewsBlackout();
   g_guardCfg.newsOfflineBlock = EffNewsOfflineBlock();
   g_guardCfg.newsDataAvailable = g_news.HasData();
   g_guardCfg.newsIsStale = g_news.IsStale();
   g_guardCfg.newsInBlackout = inBlackout;
   g_guardCfg.newsUpcomingWarn = false;

   g_guardCfg.sessionFilterEnabled = InpSessionFilter;
   g_guardCfg.sessionAllowed = g_session.IsAllowed(InpSessionFilter);
   g_guardCfg.spreadCheckEnabled = (EffMaxSpread()>0 || InpSpreadWarnPoints>0);
   g_guardCfg.maxSpreadPoints = EffMaxSpread();
   g_guardCfg.spreadWarnPoints = InpSpreadWarnPoints;

   MM_TradePlan p; p.Reset(); p.symbol=_Symbol;
   g_guards.FillLiveConfig(p, g_guardCfg);
   g_guards.ApplyNewsState(g_guardCfg, g_news.HasData(), g_news.IsStale(), inBlackout);

   if(inBlackout && !g_lastNewsBlackout)
   {
      g_alerts.AlertNews(_Symbol, "News blackout window active");
      g_mmLog.Warn("NEWS_BLACKOUT", _Symbol+" blackout active src="+g_news.SourceTag());
   }
   g_lastNewsBlackout = inBlackout;

   g_prot.SyncPeaks();
}

void CheckConnectionAlert()
{
   bool conn = (bool)TerminalInfoInteger(TERMINAL_CONNECTED);
   if(!conn && g_lastConnected){ g_alerts.AlertConnectionLost(); g_mmLog.Warn("CONNECTION","lost"); }
   if(conn && !g_lastConnected){ g_alerts.AlertConnectionRestored(); g_mmLog.Info("CONNECTION","restored"); }
   g_lastConnected = conn;
}

void UpdateStoreStatusUi()
{
   if(!StoreReadyForRiskIncreasing())
   {
      string why = g_store.StatusReason();
      if(why=="") why="explicit_resolution_required";
      g_ui.SetStoreBlockedState(true, why);
   }
   else
   {
      g_ui.SetStoreBlockedState(false, "");
   }
}

void SyncPropBaselineFromRuntime()
{
   // Phase 7: keep prop engine/rules inactive unless prop is explicitly configured.
   if(PropExplicitEnabled())
   {
      SPropFirmRules r; g_prop.Init(); g_prop.LoadPreset(InpPropPreset,r); r.mode=InpPropMode; g_prop.Enable(r);
      g_prop.SyncBaseline(g_prot.StartBalance(), g_prot.PeakEquity());
   }
   else g_prop.Init();
}

// Explicit, user-confirmed initialization of a NEW protective state from current MT5 metrics.
// - Never called automatically on restart/continuity uncertainty/switch detection.
// - Preserves previous persisted evidence in StateStore; replaces protective baselines/counters only after confirmation+persist.
// - Risk-increasing actions remain blocked unless/until this succeeds.
bool RequestExplicitNewProtectiveInit(const string reason)
{
   CUiStrings *ui = g_ui.Strings();
   string msg = ui.Msg_ConfirmNewInit() + "\n\nReason: " + reason +
                "\nState: " + g_store.StatusReason();
   int r = MessageBox(msg, "MoneyManager - Explicit protective initialization", MB_YESNO|MB_ICONWARNING|MB_DEFBUTTON2);
   if(r != IDYES)
   {
      g_ui.status.Info("STATE", "Explicit initialization cancelled; risk-increasing actions remain blocked");
      UpdateStoreStatusUi();
      return false;
   }

   g_prot.Init();
   SyncPropBaselineFromRuntime();
   double peakEq = g_prot.PeakEquity(); if(peakEq<=0) peakEq=AccountInfoDouble(ACCOUNT_EQUITY);
   double peakBal= g_prot.PeakBalance(); if(peakBal<=0) peakBal=AccountInfoDouble(ACCOUNT_BALANCE);

   MM_ProfileRecord pr; string activeProfile="";
   if(g_profiles.GetActive(pr)) activeProfile = pr.profile.id;

   bool ok = g_store.InitializeNewProtectiveStateFromCurrent(g_prot.DayStartBalance(), g_prot.DayStartEquity(),
                                                              peakEq, peakBal, InpAccountMode, activeProfile, true);
   if(ok)
   {
      g_mmLog.Info("STATE_EXPLICIT_INIT_OK","reason="+reason);
      g_ui.status.Info("STATE", ui.Msg_InitDone() + " ("+reason+")");
      g_alerts.Fire("State: Explicit protective initialization completed");
   }
   else
   {
      g_mmLog.Error("STATE_EXPLICIT_INIT_FAIL","reason="+reason+" store_reason="+g_store.StatusReason());
      g_ui.status.Warn("STATE", ui.Msg_InitFailed());
      g_alerts.Fire("State: Explicit protective initialization failed; risk-increasing actions remain blocked");
   }
   UpdateStoreStatusUi();
   return ok;
}

// Runtime account-switch handling (in-session best-effort).
// Never auto-resets/rebases persisted protective state; blocks new risk-increasing actions until explicit resolution.
void HandleRuntimeAccountSwitchIfDetected(const int reason)
{
   long marker = AccountInfoInteger(ACCOUNT_LOGIN);
   if(marker <= 0) return;

   bool switchByReason = (reason == REASON_ACCOUNT);
   if(!g_rtMarkerInitialized)
   {
      g_rtAccountMarker = marker;
      g_rtMarkerInitialized = true;
      if(!switchByReason) return;
   }

   bool switchByMarker = (marker != g_rtAccountMarker);
   if(!switchByReason && !switchByMarker) return;

   g_rtAccountMarker = marker;
   g_rtMarkerInitialized = true;

   g_mmLog.Warn("ACCOUNT_SWITCH","Runtime account change detected; blocking risk-increasing actions pending explicit resolution");
   g_ui.status.Warn("STATE","Account change detected: previous protective state not auto-applied/reset; explicit resolution required");
   g_alerts.Fire("Account: change detected; explicit resolution required before new risk-increasing actions");

   g_profiles.SetActiveByMode(InpAccountMode);
   g_stats.SetAccountMode(InpAccountMode);
   g_prot.Init();
   SyncPropBaselineFromRuntime();

   g_store.BlockPendingExplicitResolution("runtime_account_switch_explicit_resolution_required", true);
   UpdateStoreStatusUi();
}

void HandleStoreResolveRequest();

int OnInit()
{
   // Privacy: no account identifiers in logs or persisted state.
   g_mmLog.Init("mm");
   g_mmLog.Info("INIT","MoneyManager Phase7 init start "+_Symbol);

   bool storeInit = g_store.Init();
   if(!storeInit)
      g_mmLog.Warn("STATE_INIT_FAIL","StateStore init returned false (unsafe/blocked); reason="+g_store.StatusReason());

   // Persistence & Recovery Engine: evaluate restart recovery, never auto re-base.
   g_recovery.SetStore(g_store);
   g_recovery.RecoverOnRestart();
   if(!g_recovery.IsOperational())
      g_mmLog.Warn("RECOVERY_NOT_OPERATIONAL", g_recovery.ReportText());

   g_alerts.Init();
   g_ui.status.SetAlerts(GetPointer(g_alerts));
   g_guards.Init(GetPointer(g_ui.status), true);
   g_router.Init(GetPointer(g_store), GetPointer(g_ui.status), InpMagic, GetPointer(g_guards));

   g_profiles.Init();
   g_profiles.SetActiveByMode(InpAccountMode);
   g_positions.Init(); g_positions.SetMagic(InpMagic);
   g_prot.Init();
   g_posTrackCount=0; g_seenDealCount=0;
   g_news.Init();
   g_session.Init();
   g_stats.Init("MoneyManager_trades.csv");
   g_stats.SetAccountMode(InpAccountMode);
   g_lifecycle.AddListener(GetPointer(g_stats));

   SyncPropBaselineFromRuntime();

   g_policy.Reset(); g_policy.maxSlippagePoints=InpSlippage;

   g_drag.Init(0,_Symbol,"MM_D_");
   g_drag.SetSizingMode(InpSizingMode);
   g_drag.SetRiskValue(InpSizingMode==SIZING_AUTO_RISK?InpRiskPercent:InpManualLot);
   g_drag.SetSlippage(InpSlippage);
   g_posDrag.Init(0,InpMagic,"MM_PD_");

   g_ui.Init(0,_Symbol,10,50);
   g_ui.SetLang(InpUILangFA);
   g_ui.SetStats(g_stats);
   g_ui.SetProfiles(g_profiles);
   g_ui.SetAccountMode(InpAccountMode);
   g_ui.SetStoreResolutionHandler(HandleStoreResolveRequest);
   g_ui.Create();

   // Runtime-only account marker (never persisted).
   g_rtAccountMarker = AccountInfoInteger(ACCOUNT_LOGIN);
   g_rtMarkerInitialized = (g_rtAccountMarker > 0);

   // Conservative continuity: do NOT auto-reset/rebase protective state.
   if(!StoreReadyForRiskIncreasing())
   {
      g_mmLog.Warn("STATE_RESOLUTION_REQUIRED","Risk-increasing actions blocked pending explicit resolution; reason="+g_store.StatusReason());
      g_ui.status.Warn("STATE", g_ui.Strings().Msg_StateBlocked());
      g_alerts.Fire("State: Risk-increasing actions blocked until explicit resolution");
   }
   else
   {
      g_mmLog.Info("STATE_READY","Store operational");
   }
   g_ui.SetAccountMode(EffectiveAccountMode());
   UpdateStoreStatusUi();

   g_lastConnected = (bool)TerminalInfoInteger(TERMINAL_CONNECTED);
   g_lastNewsBlackout=false;
   EventSetTimer(1);
   g_mmLog.Info("INIT_OK","Money Manager Phase7 initialized mode="+(string)EffectiveAccountMode()+" propExplicit="+(string)PropExplicitEnabled()+" magic="+(string)InpMagic);
   Print("Money Manager EA Phase7 initialized. Risk-increasing actions: " + (StoreReadyForRiskIncreasing()?"READY":"BLOCKED (explicit resolution required)"));
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   // REASON_ACCOUNT: runtime/account change lifecycle signal (in-memory handling only)
   if(reason == REASON_ACCOUNT)
      HandleRuntimeAccountSwitchIfDetected(reason);

   g_drag.Deactivate();
   g_posDrag.Clear();
   g_ui.Destroy();
   g_profiles.SaveAll();
   // Persist only if store is operational/safe.
   if(StoreReadyForRiskIncreasing()) g_store.Save();
   g_stats.CloseCSV();
   g_mmLog.Info("DEINIT","reason="+(string)reason);
}

void HandleStoreResolveRequest()
{
   // Explicit user-triggered resolution entry point from UI.
   if(StoreReadyForRiskIncreasing())
   {
      g_ui.status.Info("STATE","Store already operational");
      return;
   }

   string reason = g_store.StatusReason();
   if(reason=="") reason="explicit_resolution_requested";
   bool ok = RequestExplicitNewProtectiveInit(reason);
   if(!ok && g_store.HasRestoredProtectiveState() && !g_store.IsContinuityCertain())
   {
      g_ui.status.Warn("STATE", g_ui.Strings().Msg_RestoreDenied());
   }
   UpdateStoreStatusUi();
}

void OnTick()
{
   HandleRuntimeAccountSwitchIfDetected(0);

   g_session.Update();
   datetime srv=TimeTradeServer(); if(srv==0) srv=TimeCurrent();
   // Server-time daily/weekly/monthly boundary sync and cooldown expiry (no historical invention).
   g_prot.SyncPeriods(srv);
   g_prot.UpdateCooldown(srv);
   CheckConnectionAlert();
   g_prot.SyncPeaks();

   // Risk-reducing/existing-position management remains active where possible, even when store/limits block new risk-increasing entries.
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i); if(ticket==0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if((int)PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      if(InpBEMode!=BE_NONE)
      {
         string sym=PositionGetString(POSITION_SYMBOL);
         double point=SymbolInfoDouble(sym,SYMBOL_POINT); if(point<=0) continue;
         double slPts=PriceToPoints(sym,MathAbs(PositionGetDouble(POSITION_PRICE_OPEN)-PositionGetDouble(POSITION_SL)));
         if(slPts>0 && MathAbs(PositionGetDouble(POSITION_PRICE_CURRENT)-PositionGetDouble(POSITION_PRICE_OPEN))/point >= slPts)
            g_positions.MoveToBreakEven(ticket,InpBEMode,InpBEPoints);
      }
      if(InpTrailMode!=TRAIL_NONE) g_positions.TrailStop(ticket,InpTrailMode,InpTrailValue);
      if(InpMaxMinutesInTrade>0) g_positions.TimeBasedExit(ticket,InpMaxMinutesInTrade);
   }

   g_drag.OnTickUpdate();
   g_posDrag.OnTick();
   RefreshRiskContext();
   RefreshGuardConfig();
   g_ui.SetAccountMode(EffectiveAccountMode());
   UpdateStoreStatusUi();
   g_ui.Update(g_session, g_news, g_drag, g_risk, g_stops, g_guards, g_riskCtx, g_guardCfg);
}

void OnTimer()
{
   HandleRuntimeAccountSwitchIfDetected(0);
   datetime srv=TimeTradeServer(); if(srv==0) srv=TimeCurrent();
   g_prot.SyncPeriods(srv);
   g_prot.UpdateCooldown(srv);
   CheckConnectionAlert();
   RefreshRiskContext();
   RefreshGuardConfig();
   g_ui.SetAccountMode(EffectiveAccountMode());
   UpdateStoreStatusUi();
}

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if(id==CHARTEVENT_KEYDOWN && (int)lparam==84)
   {
      if(!g_tplSaved && g_drag.Active()){ g_tpl=g_drag.CaptureTemplate("tpl1"); g_tplSaved=true; g_ui.status.Info("TPL","Template saved"); }
      else if(g_tplSaved){ g_drag.ApplyTemplate(g_tpl, g_drag.Active()?g_drag.Entry():SymbolInfoDouble(_Symbol,SYMBOL_ASK)); g_ui.status.Info("TPL","Template applied"); }
   }
   if(id==CHARTEVENT_KEYDOWN && (int)lparam==82)
   {
      ENUM_MM_SIZING_MODE m = (g_drag.SizingMode()==SIZING_AUTO_RISK)?SIZING_MANUAL_LOT:SIZING_AUTO_RISK;
      g_drag.SetSizingMode(m);
      g_drag.SetRiskValue(m==SIZING_AUTO_RISK?InpRiskPercent:InpManualLot);
      g_ui.status.Info("RISK", m==SIZING_AUTO_RISK?"Auto risk%":"Manual lot");
   }
   g_ui.OnChartEvent(id,lparam,dparam,sparam, g_drag, g_router, g_riskCtx, g_guardCfg, g_policy, g_posDrag);
}

void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   g_lifecycle.OnTradeTransaction(trans,request,result);

   // Phase 2.3 protection accounting (authoritative, deduped):
   // - Exposure (daily trade limit): count on DEAL_ENTRY_IN and on netting reversal opening exposure
   //   (DEAL_ENTRY_INOUT leaving opposite position open), deduped by order ticket (pending only when filled).
   // - Completed directional trade outcome: aggregate realized net per logical lifecycle =
   //   sum(profit + commission + swap + fee) from DEAL_ENTRY_IN (entry costs, when applicable) + all DEAL_ENTRY_OUT
   //   + DEAL_ENTRY_INOUT closing portions + position-linked broker adjustments, each deal included exactly once.
   //   Partial closes aggregate but do not finalize. Full close or netting reversal boundary finalizes once.
   // - DEAL_ENTRY_INOUT (netting reversal): closes previous directional exposure and opens opposite exposure while
   //   POSITION_IDENTIFIER may be preserved (POSITION_TICKET may change). Previous/new logical lifecycles must not merge.
   //   Reversal deal profit is for closed portion; commission/swap/fee may be inseparable close vs open -> attributed
   //   conservatively to closed lifecycle (no split invention). If separation is not reliable, no invented allocation.
   //   Hedging: separate identifiers/lifecycles handled independently. Balance/credit excluded.
   //   Late-posted adjustments after finalization cannot be re-accounted (no invention).
   if(trans.type==TRADE_TRANSACTION_DEAL_ADD && HistoryDealSelect(trans.deal))
   {
      ulong dealTicket = trans.deal;
      if(IsDealSeen(dealTicket)) return; // avoid duplicate processing of transaction events

      ENUM_DEAL_TYPE dt=(ENUM_DEAL_TYPE)HistoryDealGetInteger(trans.deal, DEAL_TYPE);
      long posId=(long)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
      if(posId==0) posId=(long)trans.position;
      string sym=trans.symbol; if(sym=="") sym=(string)HistoryDealGetString(trans.deal, DEAL_SYMBOL);
      double profit=HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
      double comm=HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
      double swap=HistoryDealGetDouble(trans.deal, DEAL_SWAP);
      double fee=HistoryDealGetDouble(trans.deal, DEAL_FEE);
      double dealNet = profit + comm + swap + fee;
      double vol=HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
      ulong orderTicket=(ulong)HistoryDealGetInteger(trans.deal, DEAL_ORDER);
      datetime evTime=(datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);
      if(evTime==0){ evTime=TimeTradeServer(); if(evTime==0) evTime=TimeCurrent(); }

      if(dt!=DEAL_TYPE_BUY && dt!=DEAL_TYPE_SELL)
      {
         // Broker-specific posting: position-linked commission/fee/correction deals aggregated into active lifecycle net if not yet finalized.
         // Exclude balance/credit (not trade P/L). Do not invent or re-open finalized accounting.
         if(posId>0 && dt!=DEAL_TYPE_BALANCE && dt!=DEAL_TYPE_CREDIT)
         {
            int ti=FindActivePosTrack(posId);
            if(ti>=0)
            {
               g_posTrack[ti].netRealized += dealNet;
               if(sym!="") g_posTrack[ti].symbol=sym;
               g_posTrack[ti].lastEventTime=evTime;
            }
         }
         MarkDealSeen(dealTicket);
         return;
      }

      ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
      MarkDealSeen(dealTicket);

      if(entry==DEAL_ENTRY_IN)
      {
         // Actual exposure created (market or filled pending). Count once per entry order (partial fills same order do not increment).
         // Include entry deal net (profit/commission/swap/fee, e.g. entry commission or fee when applicable) in lifecycle aggregation.
         if(posId>0)
         {
            int ti=AllocPosTrack(posId,sym);
            if(ti>=0)
            {
               g_posTrack[ti].seenEntry=true;
               if(sym!="") g_posTrack[ti].symbol=sym;
               g_posTrack[ti].lastEventTime=evTime;
               g_posTrack[ti].netRealized += dealNet;
            }
         }
         bool counted = g_prot.RegisterExposureOrder(orderTicket, dealTicket);
         if(counted)
            g_mmLog.Info("EXPOSURE_COUNT","order="+(string)orderTicket+" pos="+(string)posId+" tradesToday="+(string)g_prot.TradesToday());
      }
      else if(entry==DEAL_ENTRY_OUT)
      {
         if(posId<=0) return; // cannot aggregate reliably; do not guess
         int ti=FindActivePosTrack(posId);
         if(ti<0) ti=AllocPosTrack(posId,sym);
         if(ti<0) return;
         g_posTrack[ti].netRealized += dealNet;
         g_posTrack[ti].closedVolume += vol;
         if(sym!="") g_posTrack[ti].symbol=sym;
          g_posTrack[ti].lastEventTime = evTime;
          ENUM_POSITION_TYPE expSide = (dt==DEAL_TYPE_BUY)?POSITION_TYPE_SELL:POSITION_TYPE_BUY;
          bool stillOpen = PositionStillOpen(posId, g_posTrack[ti].symbol, expSide);
          if(!stillOpen)
             FinalizeCompletedLifecycle(ti, evTime); // completed directional lifecycle -> single accounting update
         // Partial close: aggregated, no streak update, no exposure count increment.
      }
      else if(entry==DEAL_ENTRY_INOUT)
      {
         if(posId<=0) return; // cannot aggregate reliably; do not guess
         int ti=FindActivePosTrack(posId);
         if(ti<0) ti=AllocPosTrack(posId,sym);
         if(ti<0) return;

         // INOUT: add full deal financials (profit+commission+swap+fee) to current directional lifecycle.
         // Profit belongs to closed portion; commission/swap/fee may not be separable close vs open -> conservative attribution to closed lifecycle, no invented split.
         g_posTrack[ti].netRealized += dealNet;
         g_posTrack[ti].closedVolume += vol;
         if(sym!="") g_posTrack[ti].symbol=sym;
          g_posTrack[ti].lastEventTime = evTime;

          ENUM_POSITION_TYPE expSide = (dt==DEAL_TYPE_BUY)?POSITION_TYPE_SELL:POSITION_TYPE_BUY;
          bool stillOpen = PositionStillOpen(posId, g_posTrack[ti].symbol, expSide);
          if(stillOpen)
         {
            // Netting reversal: previous directional trade closed, opposite exposure remains open under preserved POSITION_IDENTIFIER (ticket may change).
            // Finalize previous lifecycle once; start new logical lifecycle for opposite exposure without merging/carryover (no split invention).
            FinalizeCompletedLifecycle(ti, evTime);
            int ni=AllocPosTrack(posId, sym);
            if(ni>=0)
            {
               g_posTrack[ni].seenEntry=true;
               if(sym!="") g_posTrack[ni].symbol=sym;
               g_posTrack[ni].lastEventTime=evTime;
               g_posTrack[ni].netRealized=0.0;
               g_posTrack[ni].closedVolume=0.0;
               g_posTrack[ni].finalized=false;
            }
            bool counted = g_prot.RegisterExposureOrder(orderTicket, dealTicket);
            if(counted)
               g_mmLog.Info("EXPOSURE_COUNT","order="+(string)orderTicket+" pos="+(string)posId+" tradesToday="+(string)g_prot.TradesToday()+" reason=netting_reversal");
         }
         else
         {
            // Fully closed by this deal (no remaining opposite exposure).
            FinalizeCompletedLifecycle(ti, evTime);
         }
      }
   }
}
//+------------------------------------------------------------------+
