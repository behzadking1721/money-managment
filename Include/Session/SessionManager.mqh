#ifndef SESSION_MANAGER_MQH
#define SESSION_MANAGER_MQH
#include "../Utils/Common.mqh"
class CSessionManager
{
private:
   bool m_dstAuto; ENUM_SESSION m_current;
   color m_sessionColors[6];

   int NormHour(int h){ while(h<0) h+=24; while(h>=24) h-=24; return h; }
   bool InRange(int h,int start,int end)
   {
      start=NormHour(start); end=NormHour(end); h=NormHour(h);
      if(start==end) return true;
      if(start < end) return (h>=start && h<end);
      return (h>=start || h<end);
   }

public:
   void Init(){m_dstAuto=true;m_current=SESSION_OFF;
      m_sessionColors[SESSION_OFF]=clrGray;m_sessionColors[SESSION_SYDNEY]=clrDodgerBlue;
      m_sessionColors[SESSION_TOKYO]=clrOrange;m_sessionColors[SESSION_LONDON]=clrLimeGreen;
      m_sessionColors[SESSION_NEWYORK]=clrRed;m_sessionColors[SESSION_OVERLAP]=clrGold;}
   void SetDstAuto(bool v){ m_dstAuto=v; }
   bool DstAuto(){ return m_dstAuto; }

   // Approx DST detection (heuristic, not exchange-calendar exact): US second Sun Mar - first Sun Nov; EU last Sun Mar - last Sun Oct
   bool IsDST_US(datetime t){MqlDateTime dt;TimeToStruct(t,dt);return (dt.mon>3&&dt.mon<11)||(dt.mon==3&&dt.day>=8)||(dt.mon==11&&dt.day<=7);}
   bool IsDST_EU(datetime t){MqlDateTime dt;TimeToStruct(t,dt);return (dt.mon>3&&dt.mon<10)||(dt.mon==3&&dt.day>=25)||(dt.mon==10&&dt.day<=31);}

   // Determine session by UTC/GMT hour with approximate DST-aware shifts when enabled.
   // London/NY shift by -1h in local DST periods (simplified). Tokyo/Sydney kept at common UTC approximations.
   ENUM_SESSION GetCurrentSession(datetime t=0)
   {
      if(t==0) t=TimeGMT();
      MqlDateTime dt;TimeToStruct(t,dt);int h=dt.hour;
      bool dstUS = m_dstAuto && IsDST_US(t);
      bool dstEU = m_dstAuto && IsDST_EU(t);

      int sydS=22,sydE=7;   // Sydney (approx, local seasonal shifts vary)
      int tokS=0, tokE=9;   // Tokyo (no DST)
      int lonS=8, lonE=17;  // London standard
      int nyS=13, nyE=22;   // New York standard
      if(dstEU){ lonS=7; lonE=16; }
      if(dstUS){ nyS=12; nyE=21; }

      bool syd=InRange(h,sydS,sydE);
      bool tok=InRange(h,tokS,tokE);
      bool lon=InRange(h,lonS,lonE);
      bool ny =InRange(h,nyS,nyE);
      int cnt=(syd?1:0)+(tok?1:0)+(lon?1:0)+(ny?1:0);
      if(cnt>=2) return SESSION_OVERLAP;
      if(ny) return SESSION_NEWYORK;
      if(lon) return SESSION_LONDON;
      if(tok) return SESSION_TOKYO;
      if(syd) return SESSION_SYDNEY;
      return SESSION_OFF;
   }

   void Update(){ m_current=GetCurrentSession(); }
   ENUM_SESSION Current(){ return m_current; }
   bool IsAllowed(bool filterEnabled){ return (!filterEnabled || m_current!=SESSION_OFF); }
   color SessionColor(){ return m_sessionColors[m_current]; }
   string SessionName(){ string n[]={"OFF","Sydney","Tokyo","London","New York","Overlap"}; return n[m_current]; }
};
#endif
