//+------------------------------------------------------------------+
//|                                                    PropGuard.mqh |
//|                     Prop firm rules & limits guard (Phase 3)     |
//+------------------------------------------------------------------+
#ifndef MM_PROP_GUARD_MQH
#define MM_PROP_GUARD_MQH

#include "IGuard.mqh"

class CPropGuard : public IGuard
{
public:
   virtual string Id(){ return "Prop"; }
   virtual int Priority(){ return 20; }

   virtual void Evaluate(const MM_TradePlan &plan, const MM_GuardConfig &cfg, MM_GuardResult &out)
   {
      out.Reset(); out.guardId=Id(); out.priority=Priority(); out.decision=GUARD_ALLOW;
      if(!cfg.propEnabled || cfg.accountMode!=ACCOUNT_PROP) return;

      if(cfg.propMaxTradesPerDay>0 && cfg.tradesToday >= cfg.propMaxTradesPerDay)
      { out.decision=GUARD_BLOCK; out.reasonCode="PROP_MAX_TRADES"; out.messageEN="Prop daily trade count limit reached"; out.messageFA="سقف تعداد معاملات روزانه پراپ"; return; }

      if(cfg.propDailyLossLimitPct>0 && cfg.propDailyLossUsedPct >= cfg.propDailyLossLimitPct)
      { out.decision=GUARD_BLOCK; out.reasonCode="PROP_DAILY_DD"; out.messageEN="Prop daily drawdown limit reached"; out.messageFA="سقف ضرر روزانه پراپ"; return; }

      if(cfg.propMaxTotalDDPct>0 && cfg.propTotalDDUsedPct >= cfg.propMaxTotalDDPct)
      { out.decision=GUARD_BLOCK; out.reasonCode="PROP_MAX_DD"; out.messageEN="Prop max drawdown limit reached"; out.messageFA="سقف ضرر کل پراپ"; return; }

      if(cfg.propMaxPositionSizePct>0)
      {
         double bal=AccountInfoDouble(ACCOUNT_BALANCE);
         double contract=SymbolInfoDouble(plan.symbol,SYMBOL_TRADE_CONTRACT_SIZE);
         double price=plan.entryPrice>0?plan.entryPrice:SymbolInfoDouble(plan.symbol,SYMBOL_BID);
         if(bal>0 && contract>0 && price>0)
         {
            double valPct=(plan.lot*contract*price)/bal*100.0;
            if(valPct > cfg.propMaxPositionSizePct)
            { out.decision=GUARD_BLOCK; out.reasonCode="PROP_MAX_POSITION"; out.messageEN="Prop max position size exceeded"; out.messageFA="سقف حجم/اندازه پوزیشن پراپ"; return; }
         }
      }

      if(cfg.propConsistencyEnabled && cfg.propConsistencyPct>0)
      {
         // block if today's profit share would exceed consistency threshold (caller supplies current pct context)
         if(cfg.propTodayProfitPct >= cfg.propConsistencyPct)
         { out.decision=GUARD_BLOCK; out.reasonCode="PROP_CONSISTENCY"; out.messageEN="Prop consistency rule limit reached"; out.messageFA="قانون سازگاری سود پراپ"; return; }
      }

      // weekend close: warn/block near weekend per policy (default warn)
      if(cfg.propWeekendClose)
      {
         MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
         if(dt.day_of_week==5 && dt.hour>=20)
         { out.decision=GUARD_WARN; out.reasonCode="PROP_WEEKEND"; out.messageEN="Prop weekend close window approaching"; out.messageFA="نزدیک به زمان بسته شدن آخر هفته"; }
      }
   }
};

#endif // MM_PROP_GUARD_MQH
