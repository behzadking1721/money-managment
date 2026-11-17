//+------------------------------------------------------------------+
//|                                              ProtectionGuard.mqh |
//|          Daily/weekly/monthly, DD, cooldown, trades (Phase 3)    |
//+------------------------------------------------------------------+
#ifndef MM_PROTECTION_GUARD_MQH
#define MM_PROTECTION_GUARD_MQH

#include "IGuard.mqh"

class CProtectionGuard : public IGuard
{
public:
   virtual string Id(){ return "Protection"; }
   virtual int Priority(){ return 30; }

   virtual void Evaluate(const MM_TradePlan &plan, const MM_GuardConfig &cfg, MM_GuardResult &out)
   {
      out.Reset(); out.guardId=Id(); out.priority=Priority(); out.decision=GUARD_ALLOW;
      if(!cfg.protectionEnabled) return;

      if(cfg.dailyLossLimitPct>0 && cfg.dailyLossPct >= cfg.dailyLossLimitPct)
      { out.decision=GUARD_BLOCK; out.reasonCode="DAILY_LOSS_LIMIT"; out.messageEN="Daily loss limit reached"; out.messageFA="سقف ضرر روزانه"; return; }

      if(cfg.weeklyLossLimitPct>0 && cfg.weeklyLossPct >= cfg.weeklyLossLimitPct)
      { out.decision=GUARD_BLOCK; out.reasonCode="WEEKLY_LOSS_LIMIT"; out.messageEN="Weekly loss limit reached"; out.messageFA="سقف ضرر هفتگی"; return; }

      if(cfg.monthlyLossLimitPct>0 && cfg.monthlyLossPct >= cfg.monthlyLossLimitPct)
      { out.decision=GUARD_BLOCK; out.reasonCode="MONTHLY_LOSS_LIMIT"; out.messageEN="Monthly loss limit reached"; out.messageFA="سقف ضرر ماهانه"; return; }

      if(cfg.dailyProfitLimitPct>0 && cfg.dailyProfitPct >= cfg.dailyProfitLimitPct)
      { out.decision=GUARD_BLOCK; out.reasonCode="DAILY_PROFIT_LOCK"; out.messageEN="Daily profit target/lock reached"; out.messageFA="قفل/هدف سود روزانه"; return; }

      if(cfg.maxDrawdownPct>0 && cfg.currentDrawdownPct >= cfg.maxDrawdownPct)
      { out.decision=GUARD_BLOCK; out.reasonCode="MAX_DRAWDOWN"; out.messageEN="Max drawdown limit reached"; out.messageFA="سقف افت سرمایه"; return; }

      if(cfg.maxTradesPerDay>0 && cfg.tradesToday >= cfg.maxTradesPerDay)
      { out.decision=GUARD_BLOCK; out.reasonCode="MAX_TRADES_DAY"; out.messageEN="Max trades per day reached"; out.messageFA="سقف تعداد معاملات روزانه"; return; }

      if(cfg.inCooldown)
      { out.decision=GUARD_BLOCK; out.reasonCode="COOLDOWN"; out.messageEN="Cooldown active after losses"; out.messageFA="دوره توقف پس از ضرر فعال است"; return; }

      if(cfg.maxConsecLoss>0 && cfg.consecLosses >= cfg.maxConsecLoss)
      { out.decision=GUARD_BLOCK; out.reasonCode="CONSEC_LOSS_LIMIT"; out.messageEN="Consecutive loss limit reached"; out.messageFA="سقف ضررهای متوالی"; return; }
   }
};

#endif // MM_PROTECTION_GUARD_MQH
