//+------------------------------------------------------------------+
//|                                                  NewsBanner.mqh  |
//|            News banner (title/time/source/bilingual) (Ph 4/7)    |
//+------------------------------------------------------------------+
#ifndef MM_NEWS_BANNER_MQH
#define MM_NEWS_BANNER_MQH

#include "UiStrings.mqh"
#include "../News/NewsManager.mqh"

class CNewsBanner
{
private:
   long   m_chart;
   string m_name;
   int    m_x,m_y,m_w,m_h;
   color  m_bg,m_fg;
   bool   m_visible;

   void EnsureLabel()
   {
      if(ObjectFind(m_chart,m_name)<0)
      {
         ObjectCreate(m_chart,m_name,OBJ_LABEL,0,0,0);
         ObjectSetInteger(m_chart,m_name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
         ObjectSetInteger(m_chart,m_name,OBJPROP_SELECTABLE,false);
         ObjectSetInteger(m_chart,m_name,OBJPROP_HIDDEN,true);
         ObjectSetInteger(m_chart,m_name,OBJPROP_BACK,false);
      }
   }
public:
   CNewsBanner(){ m_chart=0; m_name="MM_NewsBanner"; m_x=10; m_y=5; m_w=420; m_h=18; m_bg=clrDarkSlateGray; m_fg=clrWhite; m_visible=true; }
   void Init(long chart,const string name,int x,int y){ m_chart=chart; m_name=name; m_x=x; m_y=y; }
   void SetVisible(bool v){ m_visible=v; if(ObjectFind(m_chart,m_name)>=0) ObjectSetInteger(m_chart,m_name,OBJPROP_TIMEFRAMES, v?OBJ_ALL_PERIODS:OBJ_NO_PERIODS); }
   void Update(CNewsManager &news,CUiStrings &ui)
   {
      EnsureLabel();
      string text = ui.S_News()+": ";
      int cnt=news.EventCount();
      string src = news.SourceTag();
      if(cnt<=0){ text += ui.T("No upcoming events","No upcoming events")+" ("+src+")"; m_bg=clrDimGray; }
      else
      {
         SNewsEvent ev = news.GetEvent(0);
         long diff = (long)ev.time - (long)TimeCurrent();
         string when = (diff<=0)? ui.T("Now","Now") : (string)((int)(diff/60))+"m";
         color ic = (ev.impact>=3)?clrTomato:((ev.impact==2)?clrOrange:clrDodgerBlue);
         m_bg = ic;
         text += ev.currency+" "+ev.title+" ["+when+"] ("+src+")";
      }
      ObjectSetInteger(m_chart,m_name,OBJPROP_XDISTANCE,m_x);
      ObjectSetInteger(m_chart,m_name,OBJPROP_YDISTANCE,m_y);
      ObjectSetInteger(m_chart,m_name,OBJPROP_COLOR,m_fg);
      ObjectSetInteger(m_chart,m_name,OBJPROP_BGCOLOR,m_bg);
      ObjectSetInteger(m_chart,m_name,OBJPROP_FONTSIZE,9);
      ObjectSetString(m_chart,m_name,OBJPROP_TEXT,"  "+text+"  ");
      ObjectSetString(m_chart,m_name,OBJPROP_FONT,"Arial");
      SetVisible(m_visible);
   }
   void Destroy(){ if(ObjectFind(m_chart,m_name)>=0) ObjectDelete(m_chart,m_name); }
};

#endif // MM_NEWS_BANNER_MQH
