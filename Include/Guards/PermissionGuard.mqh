//+------------------------------------------------------------------+
//|                                              PermissionGuard.mqh |
//|               Connection, terminal & trade permissions (Phase 3) |
//+------------------------------------------------------------------+
#ifndef MM_PERMISSION_GUARD_MQH
#define MM_PERMISSION_GUARD_MQH

#include "IGuard.mqh"

class CPermissionGuard : public IGuard
{
public:
   virtual string Id(){ return "Permission"; }
   virtual int Priority(){ return 10; }

   virtual void Evaluate(const MM_TradePlan &plan, const MM_GuardConfig &cfg, MM_GuardResult &out)
   {
      out.Reset(); out.guardId=Id(); out.priority=Priority(); out.decision=GUARD_ALLOW;
      out.messageEN=""; out.messageFA="";

      if(cfg.requireTerminalConnected && !TerminalInfoInteger(TERMINAL_CONNECTED))
      { out.decision=GUARD_BLOCK; out.reasonCode="NO_CONNECTION"; out.messageEN="Terminal not connected"; out.messageFA="اتصال ترمینال برقرار نیست"; return; }
      if(cfg.requireExpertEnabled && !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      { out.decision=GUARD_BLOCK; out.reasonCode="AUTO_TRADING_DISABLED"; out.messageEN="Auto trading disabled in terminal"; out.messageFA="معامله خودکار در ترمینال غیرفعال است"; return; }
      if(cfg.requireAccountTradeAllowed && !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
      { out.decision=GUARD_BLOCK; out.reasonCode="TRADE_NOT_ALLOWED"; out.messageEN="Trading not allowed for account"; out.messageFA="معامله برای حساب مجاز نیست"; return; }
      if(cfg.requireTradeAllowed && !MQLInfoInteger(MQL_TRADE_ALLOWED))
      { out.decision=GUARD_BLOCK; out.reasonCode="EA_TRADE_DISABLED"; out.messageEN="Trading not allowed for EA"; out.messageFA="معامله برای اکسپرت مجاز نیست"; return; }
      // symbol tradable
      long tmode=SymbolInfoInteger(plan.symbol, SYMBOL_TRADE_MODE);
      if(tmode==SYMBOL_TRADE_MODE_DISABLED)
      { out.decision=GUARD_BLOCK; out.reasonCode="SYMBOL_DISABLED"; out.messageEN="Trading disabled for symbol"; out.messageFA="معامله برای نماد غیرفعال است"; return; }
      if(tmode==SYMBOL_TRADE_MODE_CLOSEONLY)
      { out.decision=GUARD_BLOCK; out.reasonCode="SYMBOL_CLOSEONLY"; out.messageEN="Symbol in close-only mode"; out.messageFA="نماد فقط مجاز به بستن است"; return; }
   }
};

#endif // MM_PERMISSION_GUARD_MQH
