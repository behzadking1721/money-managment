#ifndef NEWS_MANAGER_MQH
#define NEWS_MANAGER_MQH
#include "../Utils/Common.mqh"
struct SNewsEvent { datetime time; string currency; string title; int impact; }; // impact 1=low 2=med 3=high
class CNewsManager
{
private:
   SNewsEvent m_events[]; int m_count; bool m_useFF; string m_ffUrl;
   bool m_newsBarVisible; int m_barPosition; // 0 bottom 1 top
public:
   void Init(){m_count=0;ArrayResize(m_events,0);m_useFF=true;m_ffUrl="https://nfs.faireconomy.media/ff_calendar_thisweek.json";m_newsBarVisible=true;m_barPosition=0;LoadLocalFallback();}
   void LoadLocalFallback()
   {
      // sample events
      AddEvent(TimeCurrent()+3600,"USD","NFP",3);
      AddEvent(TimeCurrent()+7200,"EUR","ECB Press Conf",3);
   }
   void AddEvent(datetime t,string cur,string title,int impact){int n=m_count++;ArrayResize(m_events,m_count);m_events[n].time=t;m_events[n].currency=cur;m_events[n].title=title;m_events[n].impact=impact;}
   bool FetchFFCalendar(){ /* network fetch not available in MQL5 directly without WebRequest; rely on local + manual */ return false; }
   // check if now is within blackout window of a high-impact event for given currency
   bool IsNewsBlackout(string symbol,int minutesBefore=15,int minutesAfter=15,int minImpact=3)
   {
      string base=StringSubstr(symbol,0,3);string quote=StringSubstr(symbol,3,3);
      datetime now=TimeCurrent();
      for(int i=0;i<m_count;i++){
         if(m_events[i].impact<minImpact)continue;
         if(m_events[i].currency!=base&&m_events[i].currency!=quote)continue;
         datetime s=m_events[i].time-minutesBefore*60;datetime e=m_events[i].time+minutesAfter*60;
         if(now>=s&&now<=e)return true;
      }return false;
   }
   // spread warning during news
   bool SpreadWarning(string symbol,double maxSpreadPoints){return GetSpreadPoints(symbol)>maxSpreadPoints;}
   int EventCount(){return m_count;}
   SNewsEvent GetEvent(int i){SNewsEvent e; if(i>=0&&i<m_count)e=m_events[i]; return e;}
   bool NewsBarVisible(){return m_newsBarVisible;}
   void SetNewsBar(bool v,int pos=0){m_newsBarVisible=v;m_barPosition=pos;}
};
#endif
