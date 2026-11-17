//+------------------------------------------------------------------+
//|                                                   StatusLog.mqh  |
//|                        Status/reject log for UI (Phase 4)        |
//+------------------------------------------------------------------+
#ifndef MM_STATUS_LOG_MQH
#define MM_STATUS_LOG_MQH

#include "../Core/RejectSink.mqh"

#define MM_STATUS_MAX 20

struct MM_StatusEntry
{
   datetime time;
   string   level;   // INFO/WARN/BLOCK/ERROR
   string   code;
   string   message;
};

class CStatusLog : public IRejectSink
{
private:
   MM_StatusEntry m_items[MM_STATUS_MAX];
   int            m_count;
   int            m_head;
   void Push(const string level,const string code,const string msg)
   {
      int idx = (m_count < MM_STATUS_MAX) ? m_count++ : m_head;
      m_items[idx].time = TimeCurrent();
      m_items[idx].level=level; m_items[idx].code=code; m_items[idx].message=msg;
      if(m_count>=MM_STATUS_MAX) m_head=(m_head+1)%MM_STATUS_MAX;
   }
public:
   CStatusLog(){ m_count=0; m_head=0; }
   virtual void OnExecutionReject(const string symbol,const string reasonCode,const string messageEN,uint retcode,const string context)
   {
      string msg=reasonCode+": "+messageEN+" ["+(string)retcode+"] "+symbol;
      Push("ERROR",reasonCode,msg);
      Print("MM Reject(exec): ",msg," ctx=",context);
   }
   virtual void OnGuardReject(const MM_GuardResult &gr,const string symbol)
   {
      string lvl = (gr.decision==GUARD_BLOCK)?"BLOCK":"WARN";
      string msg=gr.guardId+"/"+gr.reasonCode+": "+gr.messageEN+" "+symbol;
      Push(lvl, gr.reasonCode, msg);
      Print("MM Guard(",lvl,"): ",msg);
   }
   void Info(const string code,const string msg){ Push("INFO",code,msg); Print("MM: ",msg); }
   void Warn(const string code,const string msg){ Push("WARN",code,msg); Print("MM WARN: ",msg); }
   int Count(){ return m_count; }
   bool Get(int index, MM_StatusEntry &out)
   {
      if(index<0 || index>=m_count) return false;
      int idx = (m_count < MM_STATUS_MAX) ? index : (m_head+index)%MM_STATUS_MAX;
      out=m_items[idx]; return true;
   }
   string LastLine()
   {
      if(m_count<=0) return "";
      MM_StatusEntry e; Get(m_count-1,e);
      return e.level+": "+e.message;
   }
   string RecentText(int n=3)
   {
      string s=""; int start=MathMax(0,m_count-n);
      for(int i=start;i<m_count;i++){ MM_StatusEntry e; if(Get(i,e)) { if(s!="") s+="\n"; s+=e.level+":"+e.code; } }
      return s;
   }
};

#endif // MM_STATUS_LOG_MQH
