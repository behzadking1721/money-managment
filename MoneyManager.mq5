//+------------------------------------------------------------------+
//|                                                MoneyManager.mq5  |
//|       Phase 7: hardening wiring (risk/DD/news/logger/guards)     |
//+------------------------------------------------------------------+
#property copyright "Money Manager"
#property version   "1.70"
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
CPanelShell g_ui; CDragTool g_drag; CPositionDragTool g_posDrag;

MM_RiskContext g_riskCtx; MM_GuardConfig g_guardCfg; MM_ExecPolicy g_policy;
MM_DragTemplate g_tpl; bool g_tplSaved=false;
int g_lastDay=-1;
bool g_lastConnected=true;
bool g_lastNewsBlackout=false;

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

void RefreshRiskContext()
{
   ENUM_MM_ACCOUNT_MODE mode = InpAccountMode;
   bool propMode = (InpPropFirmEnabled || mode==ACCOUNT_PROP);
   ENUM_MM_RISK_BASIS basis = propMode ? MM_BASIS_ALLOWED_DD : MM_BASIS_EQUITY;
   MM_ProfileRecord pr; bool hasProf = g_profiles.GetActive(pr);
   if(hasProf)
   {
      if(pr.profile.riskBasis=="AllowedDD") basis = MM_BASIS_ALLOWED_DD;
      else if(pr.profile.riskBasis=="Balance") basis = MM_BASIS_BALANCE_DAY;
      else if(pr.profile.riskBasis=="Equity") basis = MM_BASIS_EQUITY;
   }

   double bal=AccountInfoDouble(ACCOUNT_BALANCE);
   double eq =AccountInfoDouble(ACCOUNT_EQUITY);
   double dayStartBal = g_prot.DayStartBalance(); if(dayStartBal<=0) dayStartBal=g_store.DayStartBalance();
   double dayStartEq  = g_prot.DayStartEquity();  if(dayStartEq<=0)  dayStartEq =g_store.DayStartEquity();
   g_prot.SyncPeaks(); g_store.SyncPeaks();

   double remDaily=0, remMax=0;
   double dailyLossMoney = g_prot.DailyLoss();
   double dLim = EffDailyLossLimit();
   double mLim = EffMaxDrawdown();

   if(propMode && g_prop.IsEnabled())
   {
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
   // real aggregate open risk including partial-close aware tracking
   g_riskCtx.openRiskMoney = g_stats.CalcOpenRiskMoney(InpMagic, "");
}

void RefreshGuardConfig()
{
   g_guardCfg.Reset();
   g_guardCfg.accountMode = InpAccountMode;
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
   g_guardCfg.dailyLossPct = g_prot.DailyLossPct(dayStartBal);
   g_guardCfg.dailyProfitPct = g_prot.DailyProfitPct(dayStartBal);
   g_guardCfg.currentDrawdownPct = g_prot.CurrentDrawdownPct();
   g_guardCfg.tradesToday = g_prot.TradesToday();
   g_guardCfg.consecLosses = g_prot.ConsecutiveLosses();
   g_guardCfg.inCooldown = !g_prot.CheckCooldown();

   g_guardCfg.propEnabled = (InpPropFirmEnabled || InpAccountMode==ACCOUNT_PROP);
   if(g_guardCfg.propEnabled && g_prop.IsEnabled())
   {
      SPropFirmRules r=g_prop.GetRules();
      g_guardCfg.propDailyLossLimitPct = r.maxDailyLoss;
      g_guardCfg.propMaxTotalDDPct = r.maxTotalDD;
      g_guardCfg.propDailyLossUsedPct = g_prop.DailyLossUsedPct(g_prot.DailyLoss(), dayStartBal, dayStartEq);
      g_guardCfg.propTotalDDUsedPct = g_prop.TotalDDUsedPct(AccountInfoDouble(ACCOUNT_EQUITY), g_prot.PeakEquity(), g_prot.StartBalance());
      g_guardCfg.propMaxPositionSizePct = r.maxPositionSize;
      g_guardCfg.propConsistencyEnabled = (r.consistencyPercent>0);
      g_guardCfg.propConsistencyPct = r.consistencyPercent;
      double todayProfitPct = (dayStartBal>0)?(g_prot.DailyProfit()/dayStartBal*100.0):0.0;
      g_guardCfg.propTodayProfitPct = todayProfitPct;
      g_guardCfg.propWeekendClose = r.weekendClose;
      g_guardCfg.propMaxTradesPerDay = (r.mode==PROP_CHALLENGE && EffMaxTradesPerDay()>0)?EffMaxTradesPerDay():EffMaxTradesPerDay();
   }

   bool newsEnabled = EffNewsEnabled();
   bool inBlackout = (newsEnabled && g_news.IsNewsBlackout(_Symbol,InpNewsMinutesBefore,InpNewsMinutesAfter));
   g_guardCfg.newsEnabled = newsEnabled;
   g_guardCfg.newsBlackoutOnHigh = EffNewsBlackout();
   g_guardCfg.newsOfflineBlock = EffNewsOfflineBlock();
   g_guardCfg.newsDataAvailable = g_news.HasData();
   g_guardCfg.newsIsStale = g_news.IsStale();
   g_guardCfg.newsInBlackout = inBlackout;
   g_guardCfg.newsUpcomingWarn = false;

   g_guardCfg.sessionFilterEnabled = InpSessionFilter;
   g_guardCfg.sessionAllowed = !InpSessionFilter || (g_session.Current()!=SESSION_OFF);
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

   // sync key state
   g_store.SyncPeaks();
}

void CheckConnectionAlert()
{
   bool conn = (bool)TerminalInfoInteger(TERMINAL_CONNECTED);
   if(!conn && g_lastConnected){ g_alerts.AlertConnectionLost(); g_mmLog.Warn("CONNECTION","lost"); }
   if(conn && !g_lastConnected){ g_alerts.AlertConnectionRestored(); g_mmLog.Info("CONNECTION","restored"); }
   g_lastConnected = conn;
}

int OnInit()
{
   g_mmLog.Init("mm_"+(string)AccountInfoInteger(ACCOUNT_LOGIN));
   g_mmLog.Info("INIT","MoneyManager Phase7 init start "+_Symbol);
   if(!g_store.Init()) { Print("WARN: StateStore init failed"); g_mmLog.Warn("STATE_INIT_FAIL","StateStore init failed"); }

   g_alerts.Init();
   g_ui.status.SetAlerts(GetPointer(g_alerts));
   g_guards.Init(GetPointer(g_ui.status), true);
   g_router.Init(GetPointer(g_store), GetPointer(g_ui.status), InpMagic, GetPointer(g_guards));

   g_profiles.Init();
   g_profiles.SetActiveByMode(InpAccountMode);
   g_positions.Init(); g_positions.SetMagic(InpMagic);
   g_prot.Init();
   g_prot.SyncPeaks();
   g_store.SyncPeaks();
   g_news.Init();
   g_session.Init();
   g_stats.Init("MoneyManager_trades.csv");
   g_stats.SetAccountMode(InpAccountMode);
   g_lifecycle.AddListener(GetPointer(g_stats));

   if(InpPropFirmEnabled)
   {
      SPropFirmRules r; g_prop.Init(); g_prop.LoadPreset(InpPropPreset,r); r.mode=InpPropMode; g_prop.Enable(r);
      g_prop.SyncBaseline(g_prot.StartBalance(), g_prot.PeakEquity());
   }
   else g_prop.Init();

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
   g_ui.Create();

   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt); g_lastDay=dt.day;
   g_lastConnected = (bool)TerminalInfoInteger(TERMINAL_CONNECTED);
   g_lastNewsBlackout=false;
   EventSetTimer(1);
   g_mmLog.Info("INIT_OK","Money Manager Phase7 initialized magic="+(string)InpMagic);
   Print("Money Manager EA Phase7 initialized.");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   g_drag.Deactivate();
   g_posDrag.Clear();
   g_ui.Destroy();
   g_profiles.SaveAll();
   g_store.SyncPeaks();
   g_store.Save();
   g_stats.CloseCSV();
   g_mmLog.Info("DEINIT","reason="+(string)reason);
}

void OnTick()
{
   g_session.Update();
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   if(dt.day!=g_lastDay)
   {
      g_prot.NewDay();
      g_store.SyncPeaks();
      g_store.Save();
      g_lastDay=dt.day;
      g_mmLog.Info("DAY_RESET","New trading day");
   }
   CheckConnectionAlert();
   g_prot.SyncPeaks();
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
   g_ui.SetAccountMode(InpAccountMode);
   g_ui.Update(g_session, g_news, g_drag, g_risk, g_stops, g_guards, g_riskCtx, g_guardCfg);
}

void OnTimer()
{
   CheckConnectionAlert();
   RefreshRiskContext();
   RefreshGuardConfig();
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
   // keep protection/trade counters in sync with closed deals
   if(trans.type==TRADE_TRANSACTION_DEAL_ADD && HistoryDealSelect(trans.deal))
   {
      ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
      ENUM_DEAL_TYPE  dt=(ENUM_DEAL_TYPE)HistoryDealGetInteger(trans.deal, DEAL_TYPE);
      if((entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_INOUT) && (dt==DEAL_TYPE_BUY || dt==DEAL_TYPE_SELL))
      {
         double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)+HistoryDealGetDouble(trans.deal, DEAL_COMMISSION)+HistoryDealGetDouble(trans.deal, DEAL_SWAP);
         g_prot.RecordTrade(profit);
         if(InpPropFirmEnabled && g_prop.IsEnabled()) g_prop.RecordTradingDay(g_prot.DailyProfit());
         g_mmLog.Info("DEAL_CLOSE","profit="+DoubleToString(profit,2)+" dailyLoss="+DoubleToString(g_prot.DailyLoss(),2));
      }
      if(entry==DEAL_ENTRY_IN && (dt==DEAL_TYPE_BUY || dt==DEAL_TYPE_SELL))
      {
         g_store.SyncPeaks();
      }
   }
}
//+------------------------------------------------------------------+
