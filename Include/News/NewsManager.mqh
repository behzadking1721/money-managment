#ifndef NEWS_MANAGER_MQH
#define NEWS_MANAGER_MQH
#include "../Utils/Common.mqh"
#include "../Core/Logger.mqh"

struct SNewsEvent { datetime time; string currency; string title; int impact; string source; }; // impact 1=low 2=med 3=high

class CNewsManager
{
private:
   SNewsEvent m_events[]; int m_count; bool m_useFF; string m_ffUrl;
   bool m_newsBarVisible; int m_barPosition; // 0 bottom 1 top
   datetime m_lastUpdate;
   string   m_sourceTag;   // live/cache/manual/unavailable/stale
   int      m_staleAfterSec;
   bool     m_lastFetchOk;

   void SetStateNoFetch()
   {
      m_lastFetchOk=false;
      if(m_lastUpdate==0 || m_count<=0)
      {
         m_sourceTag="unavailable";
      }
      else
      {
         // preserve cached/manual data but do not claim live/fresh fetch
         if(m_sourceTag=="live" || m_sourceTag=="") m_sourceTag="cache";
      }
   }

public:
   void Init(){m_count=0;ArrayResize(m_events,0);m_useFF=true;m_ffUrl="https://nfs.faireconomy.media/ff_calendar_thisweek.json";m_newsBarVisible=true;m_barPosition=0;m_lastUpdate=0;m_sourceTag="unavailable";m_staleAfterSec=3600;m_lastFetchOk=false;LoadLocalFallback();}
   void LoadLocalFallback()
   {
      // Phase 10: no synthetic/sample events by default (avoid false blackouts/silent assumptions).
      // Manual/cache events must be added explicitly via AddEvent/MarkUpdated when known.
      m_count=0; ArrayResize(m_events,0);
      m_lastUpdate=0;
      m_sourceTag="unavailable";
      m_lastFetchOk=false;
   }
   void AddEvent(datetime t,string cur,string title,int impact,string source="manual")
   {
      int n=m_count++;ArrayResize(m_events,m_count);
      m_events[n].time=t;m_events[n].currency=cur;m_events[n].title=title;m_events[n].impact=impact;m_events[n].source=source;
      // adding explicit event implies known/manual (or caller-provided) data; caller may MarkUpdated for freshness/source
      if(m_lastUpdate==0){ m_lastUpdate=TimeCurrent(); m_sourceTag=source; }
   }
   bool FetchFFCalendar()
   {
      // network fetch not available/verified in this build without WebRequest integration; do not invent data.
      SetStateNoFetch();
      g_mmLog.Warn("NEWS_FETCH","Live fetch unavailable/unverified; using existing cache/manual state only (no silent assumptions)");
      return false;
   }
   void MarkUpdated(const string sourceTag,bool ok=true)
   {
      m_lastUpdate=TimeCurrent(); m_sourceTag=sourceTag; m_lastFetchOk=ok;
      if(m_sourceTag=="") m_sourceTag = ok?"manual":"unavailable";
   }
   void ClearEvents(){ m_count=0; ArrayResize(m_events,0); }
   bool HasData(){ return m_count>0; }
   bool IsStale()
   {
      if(m_lastUpdate==0) return true;
      if(m_count<=0) return true;
      return (TimeCurrent()-m_lastUpdate > m_staleAfterSec);
   }
   string SourceTag()
   {
      if(m_count<=0) return "unavailable";
      if(IsStale()) return "stale";
      if(m_sourceTag=="") return "manual";
      return m_sourceTag;
   }
   datetime LastUpdate(){ return m_lastUpdate; }
   void SetStaleAfterSec(int sec){ m_staleAfterSec=(sec<60)?60:sec; }

   bool IsNewsBlackout(string symbol,int minutesBefore=15,int minutesAfter=15,int minImpact=3)
   {
      // Only evaluate against known event data. Staleness/availability policy is enforced by guards/UI; do not assume.
      if(m_count<=0) return false;
      string base=StringSubstr(symbol,0,3);string quote=""; if(StringLen(symbol)>=6) quote=StringSubstr(symbol,3,3);
      datetime now=TimeCurrent();
      for(int i=0;i<m_count;i++){
         if(m_events[i].impact<minImpact)continue;
         bool matchCur=(m_events[i].currency==base || (quote!="" && m_events[i].currency==quote));
         // if currency empty, treat as global/high-level relevance unknown -> conservative no-match by symbol filter
         if(!matchCur) continue;
         datetime s=m_events[i].time-minutesBefore*60;datetime e=m_events[i].time+minutesAfter*60;
         if(now>=s&&now<=e)return true;
      }return false;
   }
   bool SpreadWarning(string symbol,double maxSpreadPoints){return GetSpreadPoints(symbol)>maxSpreadPoints;}
   int EventCount(){return m_count;}
   SNewsEvent GetEvent(int i){SNewsEvent e; e.time=0;e.currency="";e.title="";e.impact=0;e.source=""; if(i>=0&&i<m_count)e=m_events[i]; return e;}
   bool NewsBarVisible(){return m_newsBarVisible;}
   void SetNewsBar(bool v,int pos=0){m_newsBarVisible=v;m_barPosition=pos;}
};
#endif
