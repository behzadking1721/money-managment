//+------------------------------------------------------------------+
//|                                                      Logger.mqh  |
//|                  File logger with rotation (Phase 7)             |
//+------------------------------------------------------------------+
#ifndef MM_LOGGER_MQH
#define MM_LOGGER_MQH

class CMMLogger
{
private:
   string   m_dir;
   string   m_base;
   string   m_path;
   int      m_maxBytes;
   int      m_maxFiles;
   bool     m_ready;

   void EnsureDir(){ if(m_dir!="" && !FileIsExist(m_dir, FILE_COMMON)) FolderCreate(m_dir, FILE_COMMON); }

   void RotateIfNeeded()
   {
      if(!m_ready) return;
      int h=FileOpen(m_path, FILE_READ|FILE_BIN|FILE_COMMON|FILE_SHARE_READ);
      if(h==INVALID_HANDLE) return;
      ulong sz=FileSize(h);
      FileClose(h);
      if(sz < (ulong)m_maxBytes) return;
      // shift old files: base.(max-1) deleted, ..., base.1 -> base.2, base -> base.1
      string p0=m_path;
      string pN=m_path+"."+(string)m_maxFiles;
      if(FileIsExist(pN, FILE_COMMON)) FileDelete(pN, FILE_COMMON);
      for(int i=m_maxFiles-1;i>=1;i--)
      {
         string a=m_path+"."+(string)i;
         string b=m_path+"."+(string)(i+1);
         if(FileIsExist(a, FILE_COMMON)) FileMove(a, FILE_COMMON, b, FILE_COMMON);
      }
      if(FileIsExist(p0, FILE_COMMON)) FileMove(p0, FILE_COMMON, m_path+".1", FILE_COMMON);
      CleanupOld();
   }

   void CleanupOld()
   {
      // ensure no files beyond maxFiles remain
      for(int i=m_maxFiles+1;i<=m_maxFiles+10;i++)
      {
         string p=m_path+"."+(string)i;
         if(FileIsExist(p, FILE_COMMON)) FileDelete(p, FILE_COMMON);
      }
   }

public:
   CMMLogger(){ m_dir="MoneyManager\\logs"; m_base="mm"; m_path="MoneyManager\\logs\\mm.log"; m_maxBytes=256*1024; m_maxFiles=5; m_ready=false; }

   void Init(const string baseName="mm", int maxBytes=262144, int maxFiles=5)
   {
      m_dir="MoneyManager\\logs"; m_base=baseName; m_path=m_dir+"\\"+m_base+".log";
      m_maxBytes=(maxBytes<32768)?32768:maxBytes; m_maxFiles=(maxFiles<1)?1:maxFiles;
      EnsureDir(); CleanupOld(); m_ready=true;
   }

   void Log(const string level,const string code,const string msg)
   {
      string line=TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS)+" ["+level+"] "+code+" "+msg;
      Print("MMLOG ",line);
      if(!m_ready) return;
      RotateIfNeeded();
      int h=FileOpen(m_path, FILE_READ|FILE_WRITE|FILE_TXT|FILE_COMMON|FILE_ANSI);
      if(h==INVALID_HANDLE) h=FileOpen(m_path, FILE_WRITE|FILE_TXT|FILE_COMMON|FILE_ANSI);
      if(h==INVALID_HANDLE) return;
      FileSeek(h,0,SEEK_END);
      FileWriteString(h,line+"\r\n");
      FileClose(h);
   }

   void Info(const string code,const string msg){ Log("INFO",code,msg); }
   void Warn(const string code,const string msg){ Log("WARN",code,msg); }
   void Error(const string code,const string msg){ Log("ERROR",code,msg); }
};

CMMLogger g_mmLog;

#endif // MM_LOGGER_MQH
