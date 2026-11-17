//+------------------------------------------------------------------+
//|                                                   NewsGuard.mqh  |
//|                           News blackout/warn guard (Phase 3)     |
//+------------------------------------------------------------------+
#ifndef MM_NEWS_GUARD_MQH
#define MM_NEWS_GUARD_MQH

#include "IGuard.mqh"

class CNewsGuard : public IGuard
{
public:
   virtual string Id(){ return "News"; }
   virtual int Priority(){ return 40; }

   virtual void Evaluate(const MM_TradePlan &plan, const MM_GuardConfig &cfg, MM_GuardResult &out)
   {
      out.Reset(); out.guardId=Id(); out.priority=Priority(); out.decision=GUARD_ALLOW;
      if(!cfg.newsEnabled) return;

      // Offline/stale handling: default WARN, optional BLOCK
      if(!cfg.newsDataAvailable || cfg.newsIsStale)
      {
         if(cfg.newsOfflineBlock)
         { out.decision=GUARD_BLOCK; out.reasonCode="NEWS_STALE_BLOCK"; out.messageEN="News data unavailable/stale (blackout mode)"; out.messageFA="داده اخبار نامعتبر/قدیمی (حالت بلاک)"; return; }
         out.decision=GUARD_WARN; out.reasonCode="NEWS_STALE_WARN"; out.messageEN="News data unavailable/stale"; out.messageFA="داده اخبار نامعتبر/قدیمی";
         // continue to allow unless blackout also applies and we can confirm; stale+unknown => warn only here
         if(!cfg.newsInBlackout) return;
      }

      if(cfg.newsInBlackout && cfg.newsBlackoutOnHigh)
      { out.decision=GUARD_BLOCK; out.reasonCode="NEWS_BLACKOUT"; out.messageEN="News blackout window active"; out.messageFA="بازه زمانی منع معامله اخبار"; return; }

      if(cfg.newsInBlackout && !cfg.newsBlackoutOnHigh)
      { out.decision=GUARD_WARN; out.reasonCode="NEWS_BLACKOUT_WARN"; out.messageEN="High-impact news window active"; out.messageFA="بازه خبری مهم فعال است"; return; }

      if(cfg.newsUpcomingWarn)
      { out.decision=GUARD_WARN; out.reasonCode="NEWS_UPCOMING"; out.messageEN="Upcoming news event"; out.messageFA="خبر نزدیک در تقویم"; return; }
   }
};

#endif // MM_NEWS_GUARD_MQH
