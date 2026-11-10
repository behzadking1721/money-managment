//+------------------------------------------------------------------+
//|                                                     Common.mqh   |
//|                   Money Manager - Common definitions & utilities  |
//+------------------------------------------------------------------+
#ifndef COMMON_MQH
#define COMMON_MQH

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>
#include <Trade/SymbolInfo.mqh>
#include <Trade/AccountInfo.mqh>

enum ENUM_LOT_METHOD { LOT_FIXED, LOT_RISK_PERCENT, LOT_RISK_MONEY, LOT_ATR_BASED, LOT_KELLY };
enum ENUM_SL_METHOD { SL_FIXED_POINTS, SL_ATR, SL_SWING, SL_STRUCTURE, SL_PERCENT };
enum ENUM_TP_METHOD { TP_FIXED_POINTS, TP_ATR, TP_RR, TP_STRUCTURE };
enum ENUM_TRAILING_MODE { TRAIL_NONE, TRAIL_FIXED, TRAIL_ATR, TRAIL_CANDLE };
enum ENUM_BE_MODE { BE_NONE, BE_AT_BREAKEVEN, BE_PLUS_SPREAD, BE_PLUS_POINTS };
enum ENUM_PANEL_THEME { THEME_DARK, THEME_LIGHT, THEME_AUTO };
enum ENUM_PANEL_SIZE { PANEL_COMPACT, PANEL_NORMAL, PANEL_LARGE };
enum ENUM_FONT_SIZE { FONT_SMALL, FONT_MEDIUM, FONT_LARGE };
enum ENUM_ACCOUNT_TYPE { ACC_DEMO, ACC_REAL, ACC_CONTEST };
enum ENUM_PROP_MODE { PROP_CHALLENGE, PROP_FUNDED };
enum ENUM_DD_REFERENCE { DD_FROM_EQUITY, DD_FROM_BALANCE };
enum ENUM_SESSION { SESSION_OFF, SESSION_SYDNEY, SESSION_TOKYO, SESSION_LONDON, SESSION_NEWYORK, SESSION_OVERLAP };
enum ENUM_ORDER_TYPE_EXT { OT_MARKET, OT_LIMIT, OT_STOP, OT_STOP_LIMIT, OT_OCO };
enum ENUM_ALERT_TYPE { ALERT_SOUND, ALERT_PUSH, ALERT_EMAIL, ALERT_POPUP };

struct STradeParams
{
   string symbol; ENUM_ORDER_TYPE orderType; double lot; double entryPrice;
   double stopLoss; double takeProfit1; double takeProfit2; double takeProfit3;
   int tpCount; int magic; string comment; int slippage; bool usePartialClose;
};
struct SPositionInfo
{
   ulong ticket; string symbol; ENUM_POSITION_TYPE type; double volume;
   double openPrice; double currentPrice; double sl; double tp; double profit;
   double swap; datetime openTime; int magic;
};
struct SAccountSnapshot { double balance; double equity; double margin; double freeMargin; double profit; double drawdown; datetime time; };
struct SProfile
{
   string name; ENUM_LOT_METHOD lotMethod; double lotValue; ENUM_SL_METHOD slMethod; double slValue;
   ENUM_TP_METHOD tpMethod; double tpValue; int magic; double maxRiskPercent; double minRiskPercent;
   bool useCommission; bool useSlippage; int maxSlippage; int retries;
};
struct SPropFirmRules
{
   string name; ENUM_PROP_MODE mode; ENUM_DD_REFERENCE ddReference; double maxDailyLoss; double maxTotalDD;
   double profitTarget; int minTradingDays; double consistencyPercent; double maxPositionSize;
   bool newsBlackout; bool weekendClose;
};
struct SSessionColors { color background; color text; color accent; };
struct SPanelSettings
{
   ENUM_FONT_SIZE fontSize; ENUM_PANEL_SIZE panelSize; int opacity; int defaultX; int defaultY;
   bool draggable; bool rememberPosition; ENUM_PANEL_THEME theme; bool hideHotkey;
};

#define MM_VERSION "1.0.0"
#define MM_PANEL_NAME "MoneyManagerPanel"
#define MM_MAGIC_DEFAULT 20240101
#define MM_MAX_RETRIES 5
#define MM_SLIPPAGE_DEFAULT 3
#define MM_MAX_TP 3
#define MM_MAX_PARTIAL 3

double NormalizeLot(string symbol, double lot)
{
   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0) step = 0.01;
   lot = MathMax(minLot, MathMin(maxLot, lot));
   lot = MathRound(lot / step) * step;
   int digits = (int)MathCeil(-MathLog10(step));
   if(digits < 0) digits = 2;
   return NormalizeDouble(lot, digits);
}
double PointsToPrice(string symbol, double points) { return points * SymbolInfoDouble(symbol, SYMBOL_POINT); }
double PriceToPoints(string symbol, double priceDiff) { double point = SymbolInfoDouble(symbol, SYMBOL_POINT); if(point <= 0) return 0; return priceDiff / point; }
string AccountCurrency() { return AccountInfoString(ACCOUNT_CURRENCY); }
ENUM_ACCOUNT_TYPE DetectAccountType()
{
   long tradeMode = AccountInfoInteger(ACCOUNT_TRADE_MODE);
   if(tradeMode == ACCOUNT_TRADE_MODE_DEMO) return ACC_DEMO;
   if(tradeMode == ACCOUNT_TRADE_MODE_REAL) return ACC_REAL;
   return ACC_CONTEST;
}
string DetectSymbolSuffix(string symbol)
{
   string suffixes[] = {".m",".r",".pro",".ecn",".std",".c",".i",".a",".b"};
   for(int i = 0; i < ArraySize(suffixes); i++)
   {
      int len = StringLen(suffixes[i]); int slen = StringLen(symbol);
      if(slen > len) { string tail = StringSubstr(symbol, slen - len); if(tail == suffixes[i]) return suffixes[i]; }
   }
   return "";
}
string StripSuffix(string symbol)
{
   string suf = DetectSymbolSuffix(symbol);
   if(suf == "") return symbol;
   return StringSubstr(symbol, 0, StringLen(symbol) - StringLen(suf));
}
bool IsHedgingAccount() { return (AccountInfoInteger(ACCOUNT_MARGIN_MODE) == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING); }
double GetATR(string symbol, ENUM_TIMEFRAMES tf, int period, int shift = 0)
{
   int handle = iATR(symbol, tf, period);
   if(handle == INVALID_HANDLE) return 0;
   double buf[]; ArraySetAsSeries(buf, true);
   if(CopyBuffer(handle, 0, shift, 1, buf) <= 0) { IndicatorRelease(handle); return 0; }
   double v = buf[0]; IndicatorRelease(handle); return v;
}
double GetSpreadPoints(string symbol)
{
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK); double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT); if(point <= 0) return 0;
   return (ask - bid) / point;
}
bool IsMarketOpen(string symbol) { return SymbolInfoDouble(symbol, SYMBOL_BID) > 0; }

#endif // COMMON_MQH
