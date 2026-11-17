//+------------------------------------------------------------------+
//|                                         SessionSpreadGuard.mqh   |
//|                       Session and spread checks (Phase 3)        |
//+------------------------------------------------------------------+
#ifndef MM_SESSION_SPREAD_GUARD_MQH
#define MM_SESSION_SPREAD_GUARD_MQH

#include "IGuard.mqh"

class CSessionSpreadGuard : public IGuard
{
public:
   virtual string Id(){ return "SessionSpread"; }
   virtual int Priority(){ return 50; }

   virtual void Evaluate(const MM_TradePlan &plan, const MM_GuardConfig &cfg, MM_GuardResult &out)
   {
      out.Reset(); out.guardId=Id(); out.priority=Priority(); out.decision=GUARD_ALLOW;

      if(cfg.sessionFilterEnabled && !cfg.sessionAllowed)
      { out.decision=GUARD_BLOCK; out.reasonCode="SESSION_BLOCK"; out.messageEN="Trading not allowed in current session"; out.messageFA="معامله در سشن فعلی مجاز نیست"; return; }

      if(cfg.spreadCheckEnabled)
      {
         double sp = cfg.spreadPoints;
         if(sp<=0)
         {
            double ask=SymbolInfoDouble(plan.symbol,SYMBOL_ASK), bid=SymbolInfoDouble(plan.symbol,SYMBOL_BID);
            double pt=SymbolInfoDouble(plan.symbol,SYMBOL_POINT);
            if(pt>0) sp=(ask-bid)/pt;
         }
         if(cfg.maxSpreadPoints>0 && sp > cfg.maxSpreadPoints)
         { out.decision=GUARD_BLOCK; out.reasonCode="SPREAD_TOO_HIGH"; out.messageEN="Spread exceeds maximum allowed"; out.messageFA="اسپرد بیش از حد مجاز"; return; }
         if(cfg.spreadWarnPoints>0 && sp > cfg.spreadWarnPoints)
         { out.decision=GUARD_WARN; out.reasonCode="SPREAD_WARN"; out.messageEN="Spread is elevated"; out.messageFA="اسپرد بالا است"; return; }
      }
   }
};

#endif // MM_SESSION_SPREAD_GUARD_MQH
