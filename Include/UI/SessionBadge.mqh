//+------------------------------------------------------------------+
//|                                                 SessionBadge.mqh |
//|                     Session indicator badge (Phase 4)            |
//+------------------------------------------------------------------+
#ifndef MM_SESSION_BADGE_MQH
#define MM_SESSION_BADGE_MQH

#include "UiStrings.mqh"
#include "../Session/SessionManager.mqh"

class CSessionBadge
{
private:
   long m_chart; string m_name; int m_x,m_y;
   void Ensure()
   {
      if(ObjectFind(m_chart,m_name)<0)
      {
         ObjectCreate(m_chart,m_name,OBJ_LABEL,0,0,0);
         ObjectSetInteger(m_chart,m_name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
         ObjectSetInteger(m_chart,m_name,OBJPROP_SELECTABLE,false);
         ObjectSetInteger(m_chart,m_name,OBJPROP_HIDDEN,true);
      }
   }
public:
   CSessionBadge(){ m_chart=0; m_name="MM_SessionBadge"; m_x=10; m_y=28; }
   void Init(long chart,const string name,int x,int y){ m_chart=chart; m_name=name; m_x=x; m_y=y; }
   void Update(CSessionManager &sess,CUiStrings &ui)
   {
      Ensure();
      string txt = ui.S_Session()+": "+sess.SessionName();
      ObjectSetInteger(m_chart,m_name,OBJPROP_XDISTANCE,m_x);
      ObjectSetInteger(m_chart,m_name,OBJPROP_YDISTANCE,m_y);
      ObjectSetInteger(m_chart,m_name,OBJPROP_BGCOLOR,sess.SessionColor());
      ObjectSetInteger(m_chart,m_name,OBJPROP_COLOR,clrBlack);
      ObjectSetInteger(m_chart,m_name,OBJPROP_FONTSIZE,9);
      ObjectSetString(m_chart,m_name,OBJPROP_TEXT,"  "+txt+"  ");
      ObjectSetString(m_chart,m_name,OBJPROP_FONT,"Arial");
   }
   color Color(CSessionManager &sess){ return sess.SessionColor(); }
   void Destroy(){ if(ObjectFind(m_chart,m_name)>=0) ObjectDelete(m_chart,m_name); }
};

#endif // MM_SESSION_BADGE_MQH
