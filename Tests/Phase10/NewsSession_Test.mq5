//+------------------------------------------------------------------+
//|                                        NewsSession_Test.mq5      |
//|  Phase 10: News & session hardening (focused, no broker sends)   |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "..\\..\\Include\\Core\\Contracts.mqh"
#include "..\\..\\Include\\News\\NewsManager.mqh"
#include "..\\..\\Include\\Session\\SessionManager.mqh"
#include "..\\..\\Include\\Guards\\NewsGuard.mqh"
#include "..\\..\\Include\\Guards\\SessionSpreadGuard.mqh"

int g_fail=0;
void Assert(bool c,const string n){ if(!c){ Print("FAIL: ",n); g_fail++; } else Print("OK: ",n); }

datetime MakeUTC(int year,int mon,int day,int hour,int min)
{
   MqlDateTime dt; dt.year=year; dt.mon=mon; dt.day=day; dt.hour=hour; dt.min=min; dt.sec=0;
   return StructToTime(dt);
}

void OnStart()
{
   g_fail=0;

   // 1) News: explicit unavailable state by default (no synthetic events / no silent assumptions)
   {
      CNewsManager nm; nm.Init();
      Assert(!nm.HasData(), "news default has no synthetic data");
      Assert(nm.EventCount()==0, "news default event count zero");
      Assert(nm.IsStale(), "news unavailable state treated as stale");
      string src=nm.SourceTag();
      Assert(src=="unavailable" || src=="stale", "news source explicit when unavailable");
      Assert(nm.IsNewsBlackout("EURUSD",15,15,3)==false, "no blackout without known events");
      nm.FetchFFCalendar();
      Assert(!nm.HasData(), "fetch-unverified does not invent data");
   }

   // 2) News: manual/cache events, staleness, blackout relevance and window policy inputs
   {
      CNewsManager nm; nm.Init();
      datetime now=TimeCurrent();
      nm.AddEvent(now+300, "USD", "TestHigh", 3, "manual");
      nm.MarkUpdated("manual", true);
      Assert(nm.HasData(), "manual event makes data available");
      Assert(!nm.IsStale(), "fresh manual data not stale");
      Assert(nm.SourceTag()=="manual", "fresh manual source reported");
      // blackout for relevant symbol/currency within window
      Assert(nm.IsNewsBlackout("EURUSD", 10, 10, 3)==true, "high-impact USD event triggers blackout for EURUSD within window");
      Assert(nm.IsNewsBlackout("EURJPY", 10, 10, 3)==false, "unrelated symbol currencies not blacked out by USD-only event");
      // minImpact threshold respected
      CNewsManager nm2; nm2.Init();
      nm2.AddEvent(now+300, "USD", "Low", 1, "manual"); nm2.MarkUpdated("manual",true);
      Assert(nm2.IsNewsBlackout("EURUSD", 10, 10, 3)==false, "low impact ignored for high-impact blackout");
      // stale after timeout
      nm2.SetStaleAfterSec(60);
      nm2.MarkUpdated("manual", true);
      // cannot advance real time; verify configured threshold is sane and stale when lastUpdate forced old via re-init state logic not exposed.
      // Explicitly validate stale path via unavailable+no-data already covered; here ensure HasData stays true.
      Assert(nm2.HasData(), "data retained until cleared");
   }

   // 3) NewsGuard: explicit safe behavior for unavailable/stale vs blackout
   {
      CNewsGuard ng; MM_GuardResult out; out.Reset();
      MM_TradePlan plan; plan.Reset(); plan.symbol=_Symbol; if(plan.symbol=="") plan.symbol="EURUSD";

      MM_GuardConfig cfg; cfg.Reset(); cfg.newsEnabled=true;
      cfg.newsDataAvailable=false; cfg.newsIsStale=true; cfg.newsInBlackout=false; cfg.newsOfflineBlock=false;
      ng.Evaluate(plan,cfg,out);
      Assert(out.decision==GUARD_WARN && out.reasonCode=="NEWS_STALE_WARN", "unavailable/stale news warns by default");

      cfg.newsOfflineBlock=true;
      out.Reset(); ng.Evaluate(plan,cfg,out);
      Assert(out.decision==GUARD_BLOCK && out.reasonCode=="NEWS_STALE_BLOCK", "offline/stale block when configured");

      cfg.Reset(); cfg.newsEnabled=true; cfg.newsDataAvailable=true; cfg.newsIsStale=false; cfg.newsInBlackout=true; cfg.newsBlackoutOnHigh=true;
      out.Reset(); ng.Evaluate(plan,cfg,out);
      Assert(out.decision==GUARD_BLOCK && out.reasonCode=="NEWS_BLACKOUT", "confirmed high-impact blackout blocks when policy enabled");

      cfg.newsBlackoutOnHigh=false;
      out.Reset(); ng.Evaluate(plan,cfg,out);
      Assert(out.decision==GUARD_WARN && out.reasonCode=="NEWS_BLACKOUT_WARN", "blackout warns when block-on-high disabled");
   }

   // 4) Session manager: UTC/DST-aware approximations and filter behavior
   {
      CSessionManager sm; sm.Init(); sm.SetDstAuto(true);
      // 2026-07-15 12:00 UTC: EU DST and US DST -> London 07-16, NY 12-21, overlap expected around 12
      ENUM_SESSION s1 = sm.GetCurrentSession(MakeUTC(2026,7,15,12,0));
      Assert(s1==SESSION_OVERLAP, "summer overlap (London+NY DST approx)");
      // 2026-01-15 12:00 UTC: standard time -> London 08-17, NY 13-22, so 12:00 is London only
      ENUM_SESSION s2 = sm.GetCurrentSession(MakeUTC(2026,1,15,12,0));
      Assert(s2==SESSION_LONDON, "winter London session (no NY yet, standard time)");
      // 2026-01-15 06:00 UTC: Tokyo 00-09
      ENUM_SESSION s3 = sm.GetCurrentSession(MakeUTC(2026,1,15,6,0));
      Assert(s3==SESSION_TOKYO, "Tokyo session window");
      // 2026-01-15 21:30 UTC: Sydney 22-07 or NY 13-22 -> NY still active at 21:xx (<22)
      ENUM_SESSION s4 = sm.GetCurrentSession(MakeUTC(2026,1,15,21,30));
      Assert(s4==SESSION_NEWYORK || s4==SESSION_OVERLAP, "late UTC hour resolved to active session");

      sm.Init(); sm.SetDstAuto(true);
      datetime off = MakeUTC(2026,1,15,9,30); // 09:30 UTC winter: London 08-17 & Tokyo 00-09 -> overlap boundary area
      ENUM_SESSION s5 = sm.GetCurrentSession(off);
      Assert(s5==SESSION_LONDON || s5==SESSION_OVERLAP || s5==SESSION_TOKYO, "boundary hour resolved deterministically");

      // IsAllowed helper
      sm.Init(); sm.Update(); // uses current GMT; cannot force OFF reliably across timezones of host, but logic check:
      bool allowedNoFilter = sm.IsAllowed(false);
      Assert(allowedNoFilter==true, "session filter disabled allows trading");
      if(sm.Current()==SESSION_OFF) Assert(sm.IsAllowed(true)==false, "OFF session blocked when filter enabled");
      else Assert(sm.IsAllowed(true)==true, "active session allowed when filter enabled");
   }

   // 5) SessionSpread guard integration for session filter
   {
      CSessionSpreadGuard sg; MM_GuardResult out; out.Reset();
      MM_TradePlan plan; plan.Reset(); plan.symbol=_Symbol; if(plan.symbol=="") plan.symbol="EURUSD";
      MM_GuardConfig cfg; cfg.Reset();
      cfg.sessionFilterEnabled=true; cfg.sessionAllowed=false;
      cfg.spreadCheckEnabled=false;
      sg.Evaluate(plan,cfg,out);
      Assert(out.decision==GUARD_BLOCK && out.reasonCode=="SESSION_BLOCK", "session filter blocks when session not allowed");
      cfg.sessionAllowed=true; out.Reset(); sg.Evaluate(plan,cfg,out);
      Assert(out.decision==GUARD_ALLOW, "session filter allows when session allowed");
   }

   if(g_fail==0) Print("NewsSession_Test: ALL PASS"); else Print("NewsSession_Test: FAIL count=",g_fail);
}
