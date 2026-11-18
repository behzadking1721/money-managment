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
   string   m_sourceTag;   // live/cache/manual/stale
   int      m_staleAfterSec;
   bool     m_lastFetchOk;

public:
   void Init(){m_count=0;ArrayResize(m_events,0);m_useFF=true;m_ffUrl="https://nfs.faireconomy.media/ff_calendar_thisweek.json";m_newsBarVisible=true;m_barPosition=0;m_lastUpdate=0;m_sourceTag="manual";m_staleAfterSec=3600;m_lastFetchOk=false;LoadLocalFallback();}
   void LoadLocalFallback()
   {
      // sample/manual events
      AddEvent(TimeCurrent()+3600,"USD","NFP",3,"manual");
      AddEvent(TimeCurrent()+7200,"EUR","ECB Press Conf",3,"manual");
      m_lastUpdate=TimeCurrent();
      m_sourceTag="manual";
      m_lastFetchOk=false;
   }
   void AddEvent(datetime t,string cur,string title,int impact,string source="manual")
   {
      int n=m_count++;ArrayResize(m_events,m_count);
      m_events[n].time=t;m_events[n].currency=cur;m_events[n].title=title;m_events[n].impact=impact;m_events[n].source=source;
   }
   bool FetchFFCalendar()
   {
      // network fetch not available in MQL5 directly without WebRequest; rely on local + manual
      m_lastFetchOk=false;
      if(m_lastUpdate==0){ m_sourceTag="stale"; }
      g_mmLog.Warn("NEWS_FETCH","Live fetch unavailable; using local/manual cache");
      return false;
   }
   void MarkUpdated(const string sourceTag,bool ok=true)
   {
      m_lastUpdate=TimeCurrent(); m_sourceTag=sourceTag; m_lastFetchOk=ok;
   }
   bool HasData(){ return m_count>0; }
   bool IsStale()
   {
      if(m_lastUpdate==0) return true;
      if(!m_lastFetchOk && m_sourceTag!="live") return (TimeCurrent()-m_lastUpdate > m_staleAfterSec);
      return (TimeCurrent()-m_lastUpdate > m_staleAfterSec);
   }
   string SourceTag()
   {
      if(m_count<=0) return "stale";
      if(IsStale()) return "stale";
      return m_sourceTag;
   }
   datetime LastUpdate(){ return m_lastUpdate; }
   void SetStaleAfterSec(int sec){ m_staleAfterSec=(sec<60)?60:sec; }

   bool IsNewsBlackout(string symbol,int minutesBefore=15,int minutesAfter=15,int minImpact=3)
   {
      string base=StringSubstr(symbol,0,3);string quote=""; if(StringLen(symbol)>=6) quote=StringSubstr(symbol,3,3);
      datetime now=TimeCurrent();
      for(int i=0;i<m_count;i++){
         if(m_events[i].impact<minImpact)continue;
         if(m_events[i].currency!=base&&m_events[i].currency!=quote)continue;
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
