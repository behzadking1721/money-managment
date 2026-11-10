//+------------------------------------------------------------------+
//|                                                MoneyManager.mq5  |
//+------------------------------------------------------------------+
#property copyright "Money Manager"
#property version   "1.00"
#property strict

#include "Include/Utils/Common.mqh"
#include "Include/Core/LotSizing.mqh"
#include "Include/Core/StopLoss.mqh"
#include "Include/Core/TakeProfit.mqh"
#include "Include/Core/OrderManager.mqh"
#include "Include/Core/PositionManager.mqh"
#include "Include/Protection/Protection.mqh"
#include "Include/PropFirm/PropFirm.mqh"
#include "Include/News/NewsManager.mqh"
#include "Include/Session/SessionManager.mqh"
#include "Include/Profiles/Profiles.mqh"
#include "Include/Alerts/Alerts.mqh"
#include "Include/Statistics/Statistics.mqh"
#include "Include/UI/Panel.mqh"

input group "=== Core ==="
input ENUM_LOT_METHOD InpLotMethod = LOT_RISK_PERCENT;
input double InpLotValue = 1.0;
input ENUM_SL_METHOD InpSLMethod = SL_ATR;
input double InpSLValue = 1.5;
input ENUM_TP_METHOD InpTPMethod = TP_RR;
input double InpTPValue = 2.0;
input int InpMagic = MM_MAGIC_DEFAULT;
input int InpSlippage = MM_SLIPPAGE_DEFAULT;
input int InpRetries = 3;

input group "=== Risk ==="
input double InpMaxRiskPercent = 2.0;
input double InpMinRiskPercent = 0.25;
input double InpDailyLossLimit = 5.0;
input double InpDailyProfitLimit = 0.0;
input double InpMaxDrawdown = 10.0;
input int InpMaxTradesPerDay = 0;
input int InpMaxConsecLoss = 3;
input int InpCooldownMinutes = 60;
input int InpMaxMinutesInTrade = 0;
input group "=== Trailing / BE ==="
input ENUM_BE_MODE InpBEMode = BE_PLUS_POINTS;
input double InpBEPoints = 10;
input ENUM_TRAILING_MODE InpTrailMode = TRAIL_NONE;
input double InpTrailValue = 20;
input bool InpUsePartialClose = true;

input group "=== Prop Firm ==="
input bool InpPropFirmEnabled = false;
input string InpPropPreset = "FTMO";
input ENUM_PROP_MODE InpPropMode = PROP_CHALLENGE;

input group "=== News ==="
input bool InpNewsBlackout = true;
input int InpNewsMinutesBefore = 15;
input int InpNewsMinutesAfter = 15;

input group "=== UI ==="
input ENUM_FONT_SIZE InpFontSize = FONT_MEDIUM;
input ENUM_PANEL_SIZE InpPanelSize = PANEL_NORMAL;
input int InpOpacity = 90;
input ENUM_PANEL_THEME InpTheme = THEME_AUTO;
input bool InpDraggable = true;

input group "=== Alerts ==="
input bool InpAlertSound = true;
input bool InpAlertPush = false;
input bool InpAlertEmail = false;
input bool InpAlertPopup = true;

CLotSizing g_lot; CStopLoss g_sl; CTakeProfit g_tp; COrderManager g_orders;
CPositionManager g_positions; CProtection g_prot; CPropFirm g_prop; CNewsManager g_news;
CSessionManager g_session; CProfileManager g_profiles; CAlertManager g_alerts;
CStatistics g_stats; CMoneyPanel g_panel;
SProfile g_profile; SPanelSettings g_panelSettings;

int OnInit()
{
   g_profiles.Init();
   g_profile = g_profiles.GetPreset(1);
   g_profile.lotMethod = InpLotMethod; g_profile.lotValue = InpLotValue;
   g_profile.slMethod = InpSLMethod; g_profile.slValue = InpSLValue;
   g_profile.tpMethod = InpTPMethod; g_profile.tpValue = InpTPValue;
   g_profile.magic = InpMagic; g_profile.maxRiskPercent = InpMaxRiskPercent;
   g_profile.minRiskPercent = InpMinRiskPercent;
   g_lot.Init(g_profile,true,0);
   g_orders.Init(); g_orders.SetMagic(InpMagic);
   g_positions.Init(); g_positions.SetMagic(InpMagic);
   g_prot.Init();
   g_news.Init();
   g_session.Init();
   g_alerts.Init(); g_alerts.Configure(InpAlertSound,InpAlertPush,InpAlertEmail,InpAlertPopup);
   g_stats.Init("MoneyManager_trades.csv");
   if(InpPropFirmEnabled){SPropFirmRules r;g_prop.Init();g_prop.LoadPreset(InpPropPreset,r);r.mode=InpPropMode;g_prop.Enable(r);}else g_prop.Init();
   g_panelSettings.fontSize=InpFontSize;g_panelSettings.panelSize=InpPanelSize;g_panelSettings.opacity=InpOpacity;
   g_panelSettings.defaultX=20;g_panelSettings.defaultY=20;g_panelSettings.draggable=InpDraggable;
   g_panelSettings.rememberPosition=true;g_panelSettings.theme=InpTheme;g_panelSettings.hideHotkey=true;
   g_panel.Init(g_panelSettings);
   g_panel.Create(0,MM_PANEL_NAME);
   EventSetTimer(1);
   Print("Money Manager EA initialized. Version ",MM_VERSION);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason){EventKillTimer();g_panel.Destroy();g_stats.CloseCSV();}

void OnTick()
{
   g_session.Update();
   MqlDateTime dt;TimeToStruct(TimeCurrent(),dt);static int lastDay=-1;
   if(dt.day!=lastDay){g_prot.NewDay();lastDay=dt.day;}
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);if(ticket==0)continue;
      if((int)PositionGetInteger(POSITION_MAGIC)!=InpMagic)continue;
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
   string sym=_Symbol;
   g_panel.Update("Spread: "+DoubleToString(GetSpreadPoints(sym),1),"Server: "+TimeToString(TimeCurrent(),TIME_MINUTES),(DetectAccountType()==ACC_DEMO)?"Demo":"Real","Session: "+g_session.SessionName(),"Last: "+g_stats.LastSymbol()+" "+DoubleToString(g_stats.LastProfit(),2),"RR: "+DoubleToString(g_stats.ProfitFactor(),2));
}

void OnTimer(){if(!IsMarketOpen(_Symbol)) g_alerts.AlertConnectionLost();}
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam){if(id==CHARTEVENT_KEYDOWN && (int)lparam==72) g_panel.ToggleHide(); g_panel.OnEvent(id,lparam,dparam,sparam);}

bool CanTrade()
{
   if(!g_prot.CheckDailyLossLimit(InpDailyLossLimit)){g_alerts.AlertDailyLimit();return false;}
   if(InpDailyProfitLimit>0&&!g_prot.CheckDailyProfitLimit(InpDailyProfitLimit))return false;
   if(!g_prot.CheckMaxDrawdown(InpMaxDrawdown)){g_alerts.AlertDrawdown();return false;}
   if(!g_prot.CheckMaxTradesPerDay(InpMaxTradesPerDay))return false;
   if(!g_prot.CheckConsecutiveLoss(InpMaxConsecLoss,InpCooldownMinutes))return false;
   if(!g_prot.CheckCooldown())return false;
   if(InpPropFirmEnabled){SPropFirmRules r=g_prop.GetRules();if(r.newsBlackout && g_news.IsNewsBlackout(_Symbol,InpNewsMinutesBefore,InpNewsMinutesAfter)){g_alerts.AlertNews();return false;}if(r.weekendClose && g_prot.IsWeekendCloseTime())return false;}
   if(InpNewsBlackout && g_news.IsNewsBlackout(_Symbol,InpNewsMinutesBefore,InpNewsMinutesAfter)){g_alerts.AlertNews();return false;}
   return true;
}

bool OpenTrade(bool isBuy,double lotOverride=0)
{
   if(!CanTrade())return false;
   string sym=_Symbol;
   double entry=isBuy?SymbolInfoDouble(sym,SYMBOL_ASK):SymbolInfoDouble(sym,SYMBOL_BID);
   double sl=g_sl.CalculateSL(sym,g_profile.slMethod,g_profile.slValue,entry,isBuy);
   double tp1,tp2,tp3;int cnt;g_tp.CalculateTPs(sym,g_profile.tpMethod,g_profile.tpValue,entry,sl,isBuy,tp1,tp2,tp3,cnt);
   double slPts=PriceToPoints(sym,MathAbs(entry-sl));
   double atr=GetATR(sym,PERIOD_H1,14);
   double ddFactor=g_prot.DDRecoveryFactor(g_prot.DailyLoss()/AccountInfoDouble(ACCOUNT_BALANCE)*100.0);
   double lot=(lotOverride>0)?lotOverride:g_lot.CalculateLot(sym,g_profile.lotMethod,g_profile.lotValue,slPts,atr,ddFactor);
   lot*=g_prot.LotReductionFactor(g_prot.ConsecutiveLosses());
   lot=NormalizeLot(sym,lot);
   if(lot<=0)return false;
   ENUM_ORDER_TYPE ot=isBuy?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   bool ok=g_orders.RetryMarketOrder(sym,ot,lot,sl,tp1,"",InpMagic,InpRetries);
   if(ok){g_alerts.AlertTradeOpened(sym,lot,entry);g_stats.LogTrade(sym,isBuy?POSITION_TYPE_BUY:POSITION_TYPE_SELL,lot,entry,entry,sl,tp1,0,TimeCurrent());}
   return ok;
}

void XAll(){g_positions.CloseAll(InpMagic);g_alerts.Fire("Closed all positions");}
void XProfit(){g_positions.CloseProfit(InpMagic);}
void XLoss(){g_positions.CloseLoss(InpMagic);}
void BEAll(){for(int i=0;i<PositionsTotal();i++){ulong t=PositionGetTicket(i);if(t==0)continue;if((int)PositionGetInteger(POSITION_MAGIC)!=InpMagic)continue;g_positions.MoveToBreakEven(t,InpBEMode,InpBEPoints);}}
void PartialAll(double pct){for(int i=0;i<PositionsTotal();i++){ulong t=PositionGetTicket(i);if(t==0)continue;if((int)PositionGetInteger(POSITION_MAGIC)!=InpMagic)continue;g_positions.PartialClose(t,pct);}}
//+------------------------------------------------------------------+

