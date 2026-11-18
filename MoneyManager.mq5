//+------------------------------------------------------------------+
//|                                                MoneyManager.mq5  |
//|               Phase 6: UI/Guards/Stats/Profiles/Alerts wiring    |
//+------------------------------------------------------------------+
#property copyright "Money Manager"
#property version   "1.60"
#property strict

#include "Include/Utils/Common.mqh"
#include "Include/Core/Contracts.mqh"
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

void RefreshRiskContext()
{
   ENUM_MM_RISK_BASIS basis = (InpAccountMode==ACCOUNT_PROP)?MM_BASIS_ALLOWED_DD:MM_BASIS_EQUITY;
   double remDaily=0, remMax=0;
   if(InpAccountMode==ACCOUNT_PROP)
   {
      double bal=AccountInfoDouble(ACCOUNT_BALANCE);
      SPropFirmRules r=g_prop.GetRules();
      if(r.maxDailyLoss>0) remDaily = MathMax(0.0, bal*(r.maxDailyLoss/100.0) - g_prot.DailyLoss());
      if(r.maxTotalDD>0)
      {
         double ref = (r.ddReference==DD_FROM_EQUITY)? AccountInfoDouble(ACCOUNT_EQUITY) : bal;
         remMax = MathMax(0.0, ref*(r.maxTotalDD/100.0));
      }
   }
   g_risk.BuildContext(g_riskCtx, InpAccountMode, basis,
                       AccountInfoDouble(ACCOUNT_BALANCE), remDaily, remMax,
                       0, 0, false, InpMinRiskPercent, InpMaxRiskPercent, 0,
                       InpMagic, "");
}

void RefreshGuardConfig()
{
   g_guardCfg.Reset();
   g_guardCfg.accountMode = InpAccountMode;
   g_guardCfg.protectionEnabled = true;
   g_guardCfg.dailyLossLimitPct = InpDailyLossLimit;
   g_guardCfg.dailyProfitLimitPct = InpDailyProfitLimit;
   g_guardCfg.weeklyLossLimitPct = InpWeeklyLossLimit;
   g_guardCfg.monthlyLossLimitPct = InpMonthlyLossLimit;
   g_guardCfg.maxDrawdownPct = InpMaxDrawdown;
   g_guardCfg.maxTradesPerDay = InpMaxTradesPerDay;
   g_guardCfg.maxConsecLoss = InpMaxConsecLoss;
   g_guardCfg.cooldownMinutes = InpCooldownMinutes;
   double bal=AccountInfoDouble(ACCOUNT_BALANCE); if(bal<=0) bal=1;
   g_guardCfg.dailyLossPct = g_prot.DailyLoss()/bal*100.0;
   g_guardCfg.dailyProfitPct = g_prot.DailyProfit()/bal*100.0;
   g_guardCfg.tradesToday = g_prot.TradesToday();
   g_guardCfg.consecLosses = g_prot.ConsecutiveLosses();
   g_guardCfg.inCooldown = !g_prot.CheckCooldown();
   g_guardCfg.propEnabled = InpPropFirmEnabled;
   if(InpPropFirmEnabled)
   {
      SPropFirmRules r=g_prop.GetRules();
      g_guardCfg.propDailyLossLimitPct = r.maxDailyLoss;
      g_guardCfg.propMaxTotalDDPct = r.maxTotalDD;
      g_guardCfg.propDailyLossUsedPct = g_guardCfg.dailyLossPct;
      g_guardCfg.propMaxPositionSizePct = r.maxPositionSize;
      g_guardCfg.propConsistencyEnabled = (r.consistencyPercent>0);
      g_guardCfg.propConsistencyPct = r.consistencyPercent;
      g_guardCfg.propWeekendClose = r.weekendClose;
      g_guardCfg.propMaxTradesPerDay = InpMaxTradesPerDay;
   }
   g_guardCfg.newsEnabled = InpNewsEnabled;
   bool inBlackout = (InpNewsEnabled && g_news.IsNewsBlackout(_Symbol,InpNewsMinutesBefore,InpNewsMinutesAfter));
   g_guardCfg.newsInBlackout = inBlackout;
   g_guardCfg.newsBlackoutOnHigh = InpNewsBlackout;
   g_guardCfg.newsOfflineBlock = InpNewsOfflineBlock;
   g_guardCfg.newsDataAvailable = (g_news.EventCount()>0);
   g_guardCfg.newsIsStale = !g_guardCfg.newsDataAvailable;
   g_guardCfg.newsUpcomingWarn = false;
   g_guardCfg.sessionFilterEnabled = InpSessionFilter;
   g_guardCfg.sessionAllowed = true;
   g_guardCfg.spreadCheckEnabled = (InpMaxSpreadPoints>0 || InpSpreadWarnPoints>0);
   g_guardCfg.maxSpreadPoints = InpMaxSpreadPoints;
   g_guardCfg.spreadWarnPoints = InpSpreadWarnPoints;
   MM_TradePlan p; p.Reset(); p.symbol=_Symbol;
   g_guards.FillLiveConfig(p, g_guardCfg);

   if(inBlackout && !g_lastNewsBlackout)
      g_alerts.AlertNews(_Symbol, "News blackout window active");
   g_lastNewsBlackout = inBlackout;
}

void CheckConnectionAlert()
{
   bool conn = (bool)TerminalInfoInteger(TERMINAL_CONNECTED);
   if(!conn && g_lastConnected) g_alerts.AlertConnectionLost();
   if(conn && !g_lastConnected) g_alerts.AlertConnectionRestored();
   g_lastConnected = conn;
}

int OnInit()
{
   if(!g_store.Init()) Print("WARN: StateStore init failed");
   g_alerts.Init();
   g_ui.status.SetAlerts(GetPointer(g_alerts));
   g_guards.Init(GetPointer(g_ui.status), true);
   g_router.Init(GetPointer(g_store), GetPointer(g_ui.status), InpMagic, GetPointer(g_guards));

   g_profiles.Init();
   g_profiles.SetActiveByMode(InpAccountMode);
   g_positions.Init(); g_positions.SetMagic(InpMagic);
   g_prot.Init();
   g_news.Init();
   g_session.Init();
   g_stats.Init("MoneyManager_trades.csv");
   g_stats.SetAccountMode(InpAccountMode);
   g_lifecycle.AddListener(GetPointer(g_stats));

   if(InpPropFirmEnabled){SPropFirmRules r;g_prop.Init();g_prop.LoadPreset(InpPropPreset,r);r.mode=InpPropMode;g_prop.Enable(r);}else g_prop.Init();

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

   g_lastConnected = (bool)TerminalInfoInteger(TERMINAL_CONNECTED);
   g_lastNewsBlackout=false;
   EventSetTimer(1);
   Print("Money Manager EA Phase6 initialized.");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   g_drag.Deactivate();
   g_posDrag.Clear();
   g_ui.Destroy();
   g_profiles.SaveAll();
   g_store.Save();
   g_stats.CloseCSV();
}

void OnTick()
{
   g_session.Update();
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   if(dt.day!=g_lastDay){ g_prot.NewDay(); g_lastDay=dt.day; }
   CheckConnectionAlert();
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i); if(ticket==0) continue;
      if((int)PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      if(InpBEMode!=BE_NONE)
      {
         string sym=PositionGetString(POSITION_SYMBOL);
         double point=SymbolInfoDouble(sym,SYMBOL_POINT);
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
}
//+------------------------------------------------------------------+
