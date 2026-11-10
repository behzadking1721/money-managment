#ifndef SESSION_MANAGER_MQH
#define SESSION_MANAGER_MQH
#include "../Utils/Common.mqh"
class CSessionManager
{
private:
   bool m_dstAuto; ENUM_SESSION m_current;
   color m_sessionColors[6];
public:
   void Init(){m_dstAuto=true;m_current=SESSION_OFF;
      m_sessionColors[SESSION_OFF]=clrGray;m_sessionColors[SESSION_SYDNEY]=clrDodgerBlue;
      m_sessionColors[SESSION_TOKYO]=clrOrange;m_sessionColors[SESSION_LONDON]=clrLimeGreen;
      m_sessionColors[SESSION_NEWYORK]=clrRed;m_sessionColors[SESSION_OVERLAP]=clrGold;}
   // DST detection (simple: US DST second Sunday March - first Sunday Nov; EU last Sunday March - last Sunday Oct)
   bool IsDST_US(datetime t){MqlDateTime dt;TimeToStruct(t,dt);return (dt.mon>3&&dt.mon<11)||(dt.mon==3&&dt.day>=8)||(dt.mon==11&&dt.day<=7);}
   bool IsDST_EU(datetime t){MqlDateTime dt;TimeToStruct(t,dt);return (dt.mon>3&&dt.mon<10)||(dt.mon==3&&dt.day>=25)||(dt.mon==10&&dt.day<=31);}
   // determine session by UTC hour
   ENUM_SESSION GetCurrentSession(datetime t=0)
   {
      if(t==0)t=TimeGMT();
      MqlDateTime dt;TimeToStruct(t,dt);int h=dt.hour;
      // Sydney 22-7, Tokyo 0-9, London 8-17, NY 13-22 (UTC approx)
      bool syd=(h>=22||h<7);bool tok=(h>=0&&h<9);bool lon=(h>=8&&h<17);bool ny=(h>=13&&h<22);
      int cnt=(syd?1:0)+(tok?1:0)+(lon?1:0)+(ny?1:0);
      if(cnt>=2)return SESSION_OVERLAP;
      if(ny)return SESSION_NEWYORK;
      if(lon)return SESSION_LONDON;
      if(tok)return SESSION_TOKYO;
      if(syd)return SESSION_SYDNEY;
      return SESSION_OFF;
   }
   void Update(){m_current=GetCurrentSession();}
   ENUM_SESSION Current(){return m_current;}
   color SessionColor(){return m_sessionColors[m_current];}
   string SessionName(){string n[]={"OFF","Sydney","Tokyo","London","New York","Overlap"};return n[m_current];}
};
#endif
