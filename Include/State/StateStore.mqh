#ifndef MM_STATE_STORE_MQH
#define MM_STATE_STORE_MQH

#include "../Core/Contracts.mqh"
#include "../Core/SimpleJson.mqh"
#include "../Core/Logger.mqh"

struct MM_SymbolState
{
   string symbol;
   ENUM_MM_SIZING_MODE sizingMode;
   double riskValue;
   string templateId;
   void Reset(){symbol="";sizingMode=SIZING_AUTO_RISK;riskValue=1.0;templateId="";}
};

struct MM_UIState
{
   int  panelX;
   int  panelY;
   bool mini;
   bool hidden;
   void Reset(){panelX=20;panelY=20;mini=false;hidden=false;}
};

class CStateStore
{
private:
   string          m_dir;
   string          m_statePath;
   string          m_lockPath;
   string          m_bakPath;
   string          m_tmpPath;
   long            m_login;
   bool            m_locked;
   int             m_version;
   ENUM_MM_ACCOUNT_MODE m_mode;
   string          m_activeProfileId;
   string          m_activeTemplateId;
   // counters
   int             m_tradesDay;
   int             m_tradesWeek;
   int             m_tradesMonth;
   int             m_dayKey;      // yyyymmdd server
   int             m_weekKey;
   int             m_monthKey;
   datetime        m_lastResetServer;
   bool            m_timeFallback;
   bool            m_operational;
   // day/peak baselines
   double          m_dayStartBalance;
   double          m_dayStartEquity;
   double          m_peakEquity;
   double          m_peakBalance;
   // per-symbol (simple fixed arrays Phase 1)
   MM_SymbolState  m_symbols[64];
   int             m_symbolCount;
   MM_UIState      m_ui;

   int DayKey(datetime srv){ MqlDateTime dt; TimeToStruct(srv,dt); return dt.year*10000+dt.mon*100+dt.day; }
   int MonthKey(datetime srv){ MqlDateTime dt; TimeToStruct(srv,dt); return dt.year*100+dt.mon; }
   int WeekKey(datetime srv){ MqlDateTime dt; TimeToStruct(srv,dt); int d=dt.day_of_year; return dt.year*100 + (d/7); }

   datetime EffectiveServerTime()
   {
      datetime srv=TimeTradeServer();
      if(srv==0){ m_timeFallback=true; return TimeCurrent(); }
      m_timeFallback=false; return srv;
   }

   bool EnsureDir(){ return true; }

   int FindSymbol(const string symbol)
   {
      for(int i=0;i<m_symbolCount;i++) if(m_symbols[i].symbol==symbol) return i;
      return -1;
   }

   bool ReadLockOwner(string &owner,long &ts)
   {
      owner=""; ts=0;
      int h=FileOpen(m_dir+"\\"+m_lockPath, FILE_READ|FILE_TXT|FILE_COMMON|FILE_SHARE_READ|FILE_ANSI);
      if(h==INVALID_HANDLE) return false;
      string s=""; while(!FileIsEnding(h)) s+=FileReadString(h);
      FileClose(h);
      int p=StringFind(s,"owner="); if(p>=0){ int e=StringFind(s,";",p); owner=(e>p)?StringSubstr(s,p+6,e-(p+6)):StringSubstr(s,p+6); }
      int t=StringFind(s,"ts="); if(t>=0){ int e=StringFind(s,";",t); string v=(e>t)?StringSubstr(s,t+3,e-(t+3)):StringSubstr(s,t+3); ts=StringToInteger(v); }
      return true;
   }

   void EnsureBaselines()
   {
      double bal=AccountInfoDouble(ACCOUNT_BALANCE); double eq=AccountInfoDouble(ACCOUNT_EQUITY);
      if(m_dayStartBalance<=0) m_dayStartBalance=bal;
      if(m_dayStartEquity<=0) m_dayStartEquity=eq;
      if(m_peakEquity<=0) m_peakEquity=eq;
      if(m_peakBalance<=0) m_peakBalance=bal;
      if(eq>m_peakEquity) m_peakEquity=eq;
      if(bal>m_peakBalance) m_peakBalance=bal;
   }

public:
   CStateStore(){ m_login=0; m_locked=false; m_version=MM_CONTRACT_VERSION; m_mode=ACCOUNT_PERSONAL; m_symbolCount=0; m_tradesDay=0;m_tradesWeek=0;m_tradesMonth=0;m_dayKey=0;m_weekKey=0;m_monthKey=0;m_lastResetServer=0; m_timeFallback=false; m_operational=true; m_ui.Reset(); m_activeProfileId=""; m_activeTemplateId=""; m_dayStartBalance=0; m_dayStartEquity=0; m_peakEquity=0; m_peakBalance=0; }

   bool Init(long login=-1)
   {
      if(login<0) login=AccountInfoInteger(ACCOUNT_LOGIN);
      m_login=login;
      m_dir="MoneyManager";
      string base="state_"+(string)m_login;
      m_statePath = base+".json";
      m_lockPath  = base+".lock";
      m_bakPath   = base+".bak";
      m_tmpPath   = base+".tmp";
      EnsureDir();
      return Load();
   }

   bool AcquireLock(int maxRetries=20,int sleepMs=100,int staleSec=30)
   {
      for(int r=0;r<maxRetries;r++)
      {
         if(!FileIsExist(m_dir+"\\"+m_lockPath, FILE_COMMON))
         {
            int h=FileOpen(m_dir+"\\"+m_lockPath, FILE_WRITE|FILE_TXT|FILE_COMMON);
            if(h!=INVALID_HANDLE)
            {
               datetime srv=EffectiveServerTime();
               long pid=0;
               FileWriteString(h,"owner="+(string)ChartID()+";ts="+(string)TimeLocal()+";srv="+(string)srv+";pid="+(string)pid);
               FileClose(h);
               m_locked=true; return true;
            }
         }
         else
         {
            string owner=""; long ts=0; ReadLockOwner(owner,ts);
            if(ts>0 && (long)TimeLocal() - ts > staleSec)
            {
               g_mmLog.Warn("LOCK_STALE","age="+(string)((int)((long)TimeLocal()-ts))+" owner="+owner);
               PrintFormat("MoneyManager.StateStore: stale lock takeover (age=%ds, owner=%s, staleSec=%d)", (int)((long)TimeLocal()-ts), owner, staleSec);
               FileDelete(m_dir+"\\"+m_lockPath, FILE_COMMON);
               continue;
            }
         }
         Sleep(sleepMs);
      }
      g_mmLog.Error("LOCK_FAIL","failed to acquire state lock");
      Print("MoneyManager.StateStore: ERROR failed to acquire state lock");
      return false;
   }
   void ReleaseLock()
   {
      if(!m_locked) return;
      FileDelete(m_dir+"\\"+m_lockPath, FILE_COMMON);
      m_locked=false;
   }

   bool Backup()
   {
      string src=m_dir+"\\"+m_statePath;
      string dst=m_dir+"\\"+m_bakPath;
      int in=FileOpen(src, FILE_READ|FILE_BIN|FILE_COMMON);
      if(in==INVALID_HANDLE) return true;
      int size=(int)FileSize(in);
      uchar buf[]; ArrayResize(buf,size>0?size:0);
      if(size>0) FileReadArray(in,buf,0,size);
      FileClose(in);
      int out=FileOpen(dst, FILE_WRITE|FILE_BIN|FILE_COMMON);
      if(out==INVALID_HANDLE){ g_mmLog.Error("BACKUP_FAIL",dst); Print("MoneyManager.StateStore: ERROR failed to write backup ",dst); return false; }
      if(size>0) FileWriteArray(out,buf,0,size);
      FileClose(out);
      return true;
   }

   bool Save()
   {
      if(!m_operational){ g_mmLog.Warn("STATE_SAVE_BLOCKED","store not operational"); Print("MoneyManager.StateStore: BLOCKED save - store not operational (fail-safe)"); return false; }
      if(!AcquireLock()) return false;
      bool backed=Backup();
      if(!backed){ Print("MoneyManager.StateStore: WARN backup not written; continuing with caution"); }
      datetime srv=EffectiveServerTime();
      if(m_timeFallback) Print("MoneyManager.StateStore: WARN server time unavailable, using local time for resets/counters (prop risk)");
      int dk=DayKey(srv), wk=WeekKey(srv), mk=MonthKey(srv);
      if(m_dayKey!=0 && dk!=m_dayKey){ m_tradesDay=0; m_dayStartBalance=AccountInfoDouble(ACCOUNT_BALANCE); m_dayStartEquity=AccountInfoDouble(ACCOUNT_EQUITY); g_mmLog.Info("STATE_DAY_RESET","new day key"); }
      if(m_weekKey!=0 && wk!=m_weekKey){ m_tradesWeek=0; }
      if(m_monthKey!=0 && mk!=m_monthKey){ m_tradesMonth=0; }
      m_dayKey=dk; m_weekKey=wk; m_monthKey=mk; m_lastResetServer=srv;
      EnsureBaselines();

      CJsonBuilder jb; jb.Reset(); jb.ObjStart();
      jb.Key("version", (int)m_version);
      jb.Key("login", (long)m_login);
      jb.Key("accountMode", (int)m_mode);
      jb.Key("activeProfileId", m_activeProfileId);
      jb.Key("activeTemplateId", m_activeTemplateId);
      jb.Key("tradesDay", m_tradesDay);
      jb.Key("tradesWeek", m_tradesWeek);
      jb.Key("tradesMonth", m_tradesMonth);
      jb.Key("dayKey", m_dayKey);
      jb.Key("weekKey", m_weekKey);
      jb.Key("monthKey", m_monthKey);
      jb.Key("lastResetServer", (long)m_lastResetServer);
      jb.KeyBool("timeFallback", m_timeFallback);
      jb.Key("dayStartBalance", m_dayStartBalance, 2);
      jb.Key("dayStartEquity", m_dayStartEquity, 2);
      jb.Key("peakEquity", m_peakEquity, 2);
      jb.Key("peakBalance", m_peakBalance, 2);
      jb.Key("ui.x", m_ui.panelX); jb.Key("ui.y", m_ui.panelY);
      jb.KeyBool("ui.mini", m_ui.mini); jb.KeyBool("ui.hidden", m_ui.hidden);
      jb.Key("symbolCount", m_symbolCount);
      for(int i=0;i<m_symbolCount;i++)
      {
         string p="sym."+m_symbols[i].symbol+".";
         jb.Key(p+"mode", (int)m_symbols[i].sizingMode);
         jb.Key(p+"risk", m_symbols[i].riskValue, 6);
         jb.Key(p+"tpl", m_symbols[i].templateId);
      }
      jb.ObjEnd();

      string tmpFull=m_dir+"\\"+m_tmpPath;
      string dstFull=m_dir+"\\"+m_statePath;
      int h=FileOpen(tmpFull, FILE_WRITE|FILE_TXT|FILE_COMMON|FILE_ANSI);
      bool ok=false;
      if(h!=INVALID_HANDLE){
         FileWriteString(h,jb.Str());
         FileClose(h);
         FileDelete(dstFull, FILE_COMMON);
         ok=FileMove(tmpFull, FILE_COMMON, dstFull, FILE_COMMON);
         if(!ok){
            g_mmLog.Warn("STATE_MOVE_FAIL","fallback direct write");
            Print("MoneyManager.StateStore: WARN atomic move failed, using direct write fallback (.bak exists)");
            int h2=FileOpen(dstFull, FILE_WRITE|FILE_TXT|FILE_COMMON|FILE_ANSI);
            if(h2!=INVALID_HANDLE){ FileWriteString(h2,jb.Str()); FileClose(h2); ok=true; }
            else { g_mmLog.Error("STATE_WRITE_FAIL",dstFull); Print("MoneyManager.StateStore: ERROR direct write failed"); ok=false; }
            FileDelete(tmpFull, FILE_COMMON);
         }
      }
      ReleaseLock();
      return ok;
   }

   bool Load()
   {
      m_operational=true;
      int h=FileOpen(m_dir+"\\"+m_statePath, FILE_READ|FILE_TXT|FILE_COMMON|FILE_ANSI|FILE_SHARE_READ);
      if(h==INVALID_HANDLE)
      {
         m_version=MM_CONTRACT_VERSION; m_mode=ACCOUNT_PERSONAL; m_symbolCount=0;
         m_ui.Reset(); m_tradesDay=m_tradesWeek=m_tradesMonth=0; m_dayKey=m_weekKey=m_monthKey=0;
         m_dayStartBalance=AccountInfoDouble(ACCOUNT_BALANCE); m_dayStartEquity=AccountInfoDouble(ACCOUNT_EQUITY);
         m_peakBalance=m_dayStartBalance; m_peakEquity=m_dayStartEquity;
         bool ok=Save();
         m_operational=ok;
         return ok;
      }
      string content="";
      while(!FileIsEnding(h)) content+=FileReadString(h);
      FileClose(h);
      CJsonReader jr; jr.Load(content);
      int ver=(int)jr.GetLong("version",0);
      if(ver<=0) ver=1;
      if(ver<MM_CONTRACT_VERSION){
         PrintFormat("MoneyManager.StateStore: migrating state version %d -> %d", ver, MM_CONTRACT_VERSION);
         g_mmLog.Info("STATE_MIGRATE","from="+(string)ver+" to="+(string)MM_CONTRACT_VERSION);
         ver=MM_CONTRACT_VERSION;
      }
      if(ver>MM_CONTRACT_VERSION){
         m_operational=false;
         g_mmLog.Error("STATE_VERSION_FUTURE","ver="+(string)ver);
         PrintFormat("MoneyManager.StateStore: FAIL-SAFE state version %d > supported %d; trading must remain disabled", ver, MM_CONTRACT_VERSION);
         return false;
      }
      m_version=ver;
      m_mode=(ENUM_MM_ACCOUNT_MODE)(int)jr.GetLong("accountMode", ACCOUNT_PERSONAL);
      m_activeProfileId=jr.GetString("activeProfileId","");
      m_activeTemplateId=jr.GetString("activeTemplateId","");
      m_tradesDay=(int)jr.GetLong("tradesDay",0);
      m_tradesWeek=(int)jr.GetLong("tradesWeek",0);
      m_tradesMonth=(int)jr.GetLong("tradesMonth",0);
      m_dayKey=(int)jr.GetLong("dayKey",0);
      m_weekKey=(int)jr.GetLong("weekKey",0);
      m_monthKey=(int)jr.GetLong("monthKey",0);
      m_lastResetServer=(datetime)jr.GetLong("lastResetServer",0);
      m_timeFallback=jr.GetBool("timeFallback",false);
      m_dayStartBalance=jr.GetDouble("dayStartBalance",0);
      m_dayStartEquity=jr.GetDouble("dayStartEquity",0);
      m_peakEquity=jr.GetDouble("peakEquity",0);
      m_peakBalance=jr.GetDouble("peakBalance",0);
      m_ui.panelX=(int)jr.GetLong("ui.x",20); m_ui.panelY=(int)jr.GetLong("ui.y",20);
      m_ui.mini=jr.GetBool("ui.mini",false); m_ui.hidden=jr.GetBool("ui.hidden",false);
      m_symbolCount=0;
      datetime srv=EffectiveServerTime();
      if(m_timeFallback) Print("MoneyManager.StateStore: WARN loaded with timeFallback=true (server time was unavailable)");
      int dk=DayKey(srv), wk=WeekKey(srv), mk=MonthKey(srv);
      if(m_dayKey!=0 && dk!=m_dayKey){ m_tradesDay=0; m_dayStartBalance=AccountInfoDouble(ACCOUNT_BALANCE); m_dayStartEquity=AccountInfoDouble(ACCOUNT_EQUITY); }
      if(m_weekKey!=0 && wk!=m_weekKey) m_tradesWeek=0;
      if(m_monthKey!=0 && mk!=m_monthKey) m_tradesMonth=0;
      m_dayKey=dk; m_weekKey=wk; m_monthKey=mk;
      EnsureBaselines();
      m_operational=true;
      return true;
   }

   ENUM_MM_ACCOUNT_MODE AccountMode(){ return m_mode; }
   void SetAccountMode(ENUM_MM_ACCOUNT_MODE m){ m_mode=m; }
   MM_UIState UI(){ return m_ui; }
   void SetUI(const MM_UIState &ui){ m_ui=ui; }

   void GetSymbolState(const string symbol, MM_SymbolState &out)
   {
      int idx=FindSymbol(symbol);
      if(idx>=0){ out=m_symbols[idx]; return; }
      out.Reset(); out.symbol=symbol;
      int h=FileOpen(m_dir+"\\"+m_statePath, FILE_READ|FILE_TXT|FILE_COMMON|FILE_ANSI|FILE_SHARE_READ);
      if(h!=INVALID_HANDLE){
         string content=""; while(!FileIsEnding(h)) content+=FileReadString(h); FileClose(h);
         CJsonReader jr; jr.Load(content);
         string p="sym."+symbol+".";
         if(jr.Has(p+"mode")){ out.sizingMode=(ENUM_MM_SIZING_MODE)(int)jr.GetLong(p+"mode",0); out.riskValue=jr.GetDouble(p+"risk",1.0); out.templateId=jr.GetString(p+"tpl",""); }
      }
   }
   void SetSymbolState(const MM_SymbolState &in)
   {
      int idx=FindSymbol(in.symbol);
      if(idx<0 && m_symbolCount<64){ idx=m_symbolCount++; m_symbols[idx].Reset(); m_symbols[idx].symbol=in.symbol; }
      if(idx>=0){ m_symbols[idx]=in; }
   }

   void IncTrade(){ m_tradesDay++; m_tradesWeek++; m_tradesMonth++; }
   int TradesDay(){ return m_tradesDay; }
   bool TimeFallbackActive(){ return m_timeFallback; }
   bool IsOperational(){ return m_operational; }
   string StatePath(){ return m_dir+"\\"+m_statePath; }

   double DayStartBalance(){ if(m_dayStartBalance<=0) m_dayStartBalance=AccountInfoDouble(ACCOUNT_BALANCE); return m_dayStartBalance; }
   double DayStartEquity(){ if(m_dayStartEquity<=0) m_dayStartEquity=AccountInfoDouble(ACCOUNT_EQUITY); return m_dayStartEquity; }
   double PeakEquity(){ EnsureBaselines(); return m_peakEquity; }
   double PeakBalance(){ EnsureBaselines(); return m_peakBalance; }
   void SyncPeaks(){ EnsureBaselines(); }
};

#endif // MM_STATE_STORE_MQH
