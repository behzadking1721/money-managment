//+------------------------------------------------------------------+
//|                                                 StateStore.mqh   |
//|           Phase 2.1 StateStore Foundation (corrected)            |
//+------------------------------------------------------------------+
#ifndef MM_STATE_STORE_MQH
#define MM_STATE_STORE_MQH

#include "../Core/Contracts.mqh"
#include "../Core/SimpleJson.mqh"
#include "../Core/Logger.mqh"

// Phase 2.1 (corrected): StateStore foundation hardening.
// - Persistence schema version is independent of MM_CONTRACT_VERSION.
// - No Account Login, Broker Server, credentials, personal identity, or Prop Firm identifiers persisted.
// - No persistent account identity registry.
// - Stores only minimum internal protective/config state; current MT5 account metrics stay runtime-only.
// - Does not calculate or invent historical financial values.
// - Conservative continuity: if continuity cannot be proven, block new risk-increasing actions until
//   explicitly resolved. Never auto-reset/rebase existing protective baselines when continuity uncertain.
// - Separate RestoreExistingState (continuity explicitly established only) vs
//   InitializeNewProtectiveState (explicit user confirmation required, from current MT5 values).
// Limitations:
// - Account continuity across terminal restart cannot be proven without persistent identity (forbidden).
//   Restart-loaded protective state is preserved but never auto-applied as operational continuity.
// - Runtime account change detection uses MT5 lifecycle/account data in memory only when available;
//   it cannot identify all restart-time account changes without forbidden persistent identity.
// - MQL5 file APIs do not guarantee fsync/power-loss durability.

#define MM_STATE_SCHEMA_VERSION 2

enum ENUM_MM_STORE_RESULT
{
   MM_STORE_OK = 0,
   MM_STORE_ERR_LOCK,
   MM_STORE_ERR_READ,
   MM_STORE_ERR_PARSE,
   MM_STORE_ERR_SCHEMA_INVALID,
   MM_STORE_ERR_SCHEMA_FUTURE,
   MM_STORE_ERR_INTEGRITY,
   MM_STORE_ERR_MIGRATION_UNSAFE,
   MM_STORE_ERR_TEMP_WRITE,
   MM_STORE_ERR_TEMP_VALIDATE,
   MM_STORE_ERR_BACKUP,
   MM_STORE_ERR_PROMOTE,
   MM_STORE_ERR_RECOVERY_FAILED,
   MM_STORE_ERR_MANUAL_REVIEW,
   MM_STORE_ERR_CONTINUITY_UNCERTAIN,
   MM_STORE_ERR_EXPLICIT_CONFIRM_REQUIRED,
   MM_STORE_ERR_RESTORE_NOT_ALLOWED
};

enum ENUM_MM_STORE_RECOVERY
{
   MM_RECOVERY_NONE = 0,
   MM_RECOVERY_PRIMARY,
   MM_RECOVERY_BACKUP,
   MM_RECOVERY_DEGRADED,
   MM_RECOVERY_BLOCKED
};

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

   bool            m_operational;
   bool            m_safeInitRequired;
   bool            m_manualReviewRequired;
   bool            m_degraded;
   ENUM_MM_STORE_RESULT   m_lastResult;
   ENUM_MM_STORE_RECOVERY m_recovery;
   string          m_statusReason;

   bool            m_loadedFromValidSource;
   bool            m_hasRestoredProtectiveState;     // valid prior state loaded into memory (may be continuity-uncertain)
   bool            m_continuityExplicitlyEstablished; // only set by explicit trusted resolution path
   bool            m_awaitingExplicitResolution;      // user must explicitly choose restore (if allowed) or init-new
   bool            m_hasLastKnownGoodPrimary;         // persisted primary known valid/trusted in this runtime
   string          m_lastKnownGoodContent;

   int             m_schemaVersion;
   ENUM_MM_ACCOUNT_MODE m_mode;
   string          m_activeProfileId;
   string          m_activeTemplateId;
   int             m_tradesDay;
   int             m_tradesWeek;
   int             m_tradesMonth;
   int             m_dayKey;
   int             m_weekKey;
   int             m_monthKey;
   datetime        m_lastResetServer;
   bool            m_timeFallback;
   double          m_dayStartBalance;
   double          m_dayStartEquity;
   double          m_peakEquity;
   double          m_peakBalance;
   MM_SymbolState  m_symbols[64];
   int             m_symbolCount;
   MM_UIState      m_ui;
   bool            m_locked;

   int DayKey(datetime srv){ MqlDateTime dt; TimeToStruct(srv,dt); return dt.year*10000+dt.mon*100+dt.day; }
   int MonthKey(datetime srv){ MqlDateTime dt; TimeToStruct(srv,dt); return dt.year*100+dt.mon; }
   int WeekKey(datetime srv){ MqlDateTime dt; TimeToStruct(srv,dt); int d=dt.day_of_year; return dt.year*100 + (d/7); }

   datetime EffectiveServerTime()
   {
      datetime srv=TimeTradeServer();
      if(srv==0){ m_timeFallback=true; return TimeCurrent(); }
      m_timeFallback=false; return srv;
   }

   void SetStatus(ENUM_MM_STORE_RESULT res, ENUM_MM_STORE_RECOVERY rec, const string reason, bool operational, bool safeInitReq, bool manualReview, bool degraded)
   {
      m_lastResult=res; m_recovery=rec; m_statusReason=reason;
      m_operational=operational; m_safeInitRequired=safeInitReq;
      m_manualReviewRequired=manualReview; m_degraded=degraded;
   }

   void ResetToSafeDefaultsMemoryOnly()
   {
      m_schemaVersion = MM_STATE_SCHEMA_VERSION;
      m_mode = ACCOUNT_PERSONAL;
      m_activeProfileId = "";
      m_activeTemplateId = "";
      m_tradesDay=0; m_tradesWeek=0; m_tradesMonth=0;
      m_dayKey=0; m_weekKey=0; m_monthKey=0;
      m_lastResetServer=0; m_timeFallback=false;
      m_dayStartBalance=0; m_dayStartEquity=0; m_peakEquity=0; m_peakBalance=0;
      m_symbolCount=0;
      m_ui.Reset();
   }

   int FindSymbol(const string symbol)
   {
      for(int i=0;i<m_symbolCount;i++) if(m_symbols[i].symbol==symbol) return i;
      return -1;
   }

   void EnsureDir(){ if(!FileIsExist(m_dir, FILE_COMMON)) FolderCreate(m_dir, FILE_COMMON); }
   string FullPath(const string name){ return m_dir+"\\"+name; }

   bool ReadTextFile(const string fullPath, string &out)
   {
      out="";
      int h=FileOpen(fullPath, FILE_READ|FILE_TXT|FILE_COMMON|FILE_ANSI|FILE_SHARE_READ);
      if(h==INVALID_HANDLE) return false;
      while(!FileIsEnding(h)) out+=FileReadString(h);
      FileClose(h);
      return true;
   }

   bool WriteTextFile(const string fullPath, const string content)
   {
      int h=FileOpen(fullPath, FILE_WRITE|FILE_TXT|FILE_COMMON|FILE_ANSI);
      if(h==INVALID_HANDLE) return false;
      FileWriteString(h,content);
      FileClose(h);
      return true;
   }

   bool CopyFileCommon(const string srcFull, const string dstFull)
   {
      int in=FileOpen(srcFull, FILE_READ|FILE_BIN|FILE_COMMON|FILE_SHARE_READ);
      if(in==INVALID_HANDLE) return false;
      int size=(int)FileSize(in);
      uchar buf[]; ArrayResize(buf,size>0?size:0);
      if(size>0) FileReadArray(in,buf,0,size);
      FileClose(in);
      int out=FileOpen(dstFull, FILE_WRITE|FILE_BIN|FILE_COMMON);
      if(out==INVALID_HANDLE) return false;
      if(size>0) FileWriteArray(out,buf,0,size);
      FileClose(out);
      return true;
   }

   bool ReadLockOwner(string &owner,long &ts)
   {
      owner=""; ts=0;
      string content="";
      if(!ReadTextFile(FullPath(m_lockPath), content)) return false;
      int p=StringFind(content,"owner="); if(p>=0){ int e=StringFind(content,";",p); owner=(e>p)?StringSubstr(content,p+6,e-(p+6)):StringSubstr(content,p+6); }
      int t=StringFind(content,"ts="); if(t>=0){ int e=StringFind(content,";",t); string v=(e>t)?StringSubstr(content,t+3,e-(t+3)):StringSubstr(content,t+3); ts=StringToInteger(v); }
      return true;
   }

   bool AcquireLock(int maxRetries=20,int sleepMs=100,int staleSec=30)
   {
      EnsureDir();
      for(int r=0;r<maxRetries;r++)
      {
         if(!FileIsExist(FullPath(m_lockPath), FILE_COMMON))
         {
            int h=FileOpen(FullPath(m_lockPath), FILE_WRITE|FILE_TXT|FILE_COMMON);
            if(h!=INVALID_HANDLE)
            {
               datetime srv=EffectiveServerTime();
               FileWriteString(h,"owner="+(string)ChartID()+";ts="+(string)TimeLocal()+";srv="+(string)srv+";pid=0");
               FileClose(h);
               m_locked=true; return true;
            }
         }
         else
         {
            string owner=""; long ts=0; ReadLockOwner(owner,ts);
            if(ts>0 && (long)TimeLocal() - ts > staleSec)
            {
               g_mmLog.Warn("LOCK_STALE","age="+(string)((int)((long)TimeLocal()-ts)));
               FileDelete(FullPath(m_lockPath), FILE_COMMON);
               continue;
            }
         }
         Sleep(sleepMs);
      }
      g_mmLog.Error("LOCK_FAIL","failed to acquire state lock");
      return false;
   }

   void ReleaseLock()
   {
      if(!m_locked) return;
      FileDelete(FullPath(m_lockPath), FILE_COMMON);
      m_locked=false;
   }

   string SerializeCurrent() const
   {
      CJsonBuilder jb; jb.Reset(); jb.ObjStart();
      jb.Key("schemaVersion", (int)MM_STATE_SCHEMA_VERSION);
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
         jb.Key("symName."+IntegerToString(i), m_symbols[i].symbol);
         string p="sym."+m_symbols[i].symbol+".";
         jb.Key(p+"mode", (int)m_symbols[i].sizingMode);
         jb.Key(p+"risk", m_symbols[i].riskValue, 6);
         jb.Key(p+"tpl", m_symbols[i].templateId);
      }
      jb.ObjEnd();
      return jb.Str();
   }

   bool IsFiniteNonNeg(double v){ return (v==v) && (v <= 1e300) && (v >= -1e300) && (v >= 0.0); }
   bool IsPlausiblePayload(const string &content)
   {
      if(StringLen(content) < 2) return false;
      int lb = StringFind(content,"{");
      int rb = StringFind(content,"}");
      if(lb < 0 || rb <= lb) return false;
      if(StringFind(content,"schemaVersion") < 0 && StringFind(content,"version") < 0) return false;
      return true;
   }

   bool ValidateSemantics(CJsonReader &jr, int schemaVersion, bool legacy, string &reason)
   {
      reason="";
      if(!legacy)
      {
         if(!jr.Has("schemaVersion")) { reason="missing_schemaVersion"; return false; }
         if(schemaVersion != MM_STATE_SCHEMA_VERSION) { reason="schema_mismatch"; return false; }
      }
      if(!jr.Has("accountMode")) { reason="missing_accountMode"; return false; }
      int am = (int)jr.GetLong("accountMode", -1);
      if(am < (int)ACCOUNT_PERSONAL || am > (int)ACCOUNT_CRYPTO) { reason="invalid_accountMode"; return false; }
      if(jr.Has("tradesDay") && jr.GetLong("tradesDay",0) < 0) { reason="invalid_tradesDay"; return false; }
      if(jr.Has("tradesWeek") && jr.GetLong("tradesWeek",0) < 0) { reason="invalid_tradesWeek"; return false; }
      if(jr.Has("tradesMonth") && jr.GetLong("tradesMonth",0) < 0) { reason="invalid_tradesMonth"; return false; }
      if(jr.Has("dayKey") && jr.GetLong("dayKey",0) < 0) { reason="invalid_dayKey"; return false; }
      if(jr.Has("weekKey") && jr.GetLong("weekKey",0) < 0) { reason="invalid_weekKey"; return false; }
      if(jr.Has("monthKey") && jr.GetLong("monthKey",0) < 0) { reason="invalid_monthKey"; return false; }
      if(jr.Has("lastResetServer") && jr.GetLong("lastResetServer",0) < 0) { reason="invalid_lastResetServer"; return false; }
      if(jr.Has("dayStartBalance") && !IsFiniteNonNeg(jr.GetDouble("dayStartBalance",0))) { reason="invalid_dayStartBalance"; return false; }
      if(jr.Has("dayStartEquity")  && !IsFiniteNonNeg(jr.GetDouble("dayStartEquity",0)))  { reason="invalid_dayStartEquity"; return false; }
      if(jr.Has("peakEquity")      && !IsFiniteNonNeg(jr.GetDouble("peakEquity",0)))      { reason="invalid_peakEquity"; return false; }
      if(jr.Has("peakBalance")     && !IsFiniteNonNeg(jr.GetDouble("peakBalance",0)))     { reason="invalid_peakBalance"; return false; }
      if(jr.Has("symbolCount"))
      {
         long sc = jr.GetLong("symbolCount",0);
         if(sc < 0 || sc > 64) { reason="invalid_symbolCount"; return false; }
      }
      if(!legacy)
      {
         if(jr.Has("login") || jr.Has("accountLogin") || jr.Has("AccountLogin") || jr.Has("broker") || jr.Has("Broker") || jr.Has("server") || jr.Has("Server"))
         { reason="forbidden_identity_field"; return false; }
      }
      return true;
   }

   void ApplyReader(CJsonReader &jr, const string &content)
   {
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
      int sc = (int)jr.GetLong("symbolCount", 0);
      if(sc < 0) sc = 0; if(sc > 64) sc = 64;
      for(int i=0;i<sc && m_symbolCount<64;i++)
      {
         string name = jr.GetString("symName."+IntegerToString(i), "");
         if(name=="") continue;
         MM_SymbolState st; st.Reset(); st.symbol=name;
         string p="sym."+name+".";
         st.sizingMode=(ENUM_MM_SIZING_MODE)(int)jr.GetLong(p+"mode", (int)SIZING_AUTO_RISK);
         st.riskValue=jr.GetDouble(p+"risk", 1.0);
         if(!IsFiniteNonNeg(st.riskValue)) st.riskValue=1.0;
         st.templateId=jr.GetString(p+"tpl", "");
         m_symbols[m_symbolCount++] = st;
      }
      if(m_symbolCount==0)
      {
         int pos=0;
         while(m_symbolCount < 64)
         {
            int p = StringFind(content, "\"sym.", pos);
            if(p < 0) break;
            int dot = StringFind(content, ".mode\"", p);
            int nameStart = p + 5;
            if(dot > nameStart)
            {
               string name = StringSubstr(content, nameStart, dot - nameStart);
               if(name!="" && StringFind(name,"\\")==-1 && StringFind(name,"\"")==-1 && FindSymbol(name)<0)
               {
                  MM_SymbolState st; st.Reset(); st.symbol=name;
                  string pr="sym."+name+".";
                  st.sizingMode=(ENUM_MM_SIZING_MODE)(int)jr.GetLong(pr+"mode", (int)SIZING_AUTO_RISK);
                  st.riskValue=jr.GetDouble(pr+"risk", 1.0);
                  if(!IsFiniteNonNeg(st.riskValue)) st.riskValue=1.0;
                  st.templateId=jr.GetString(pr+"tpl", "");
                  m_symbols[m_symbolCount++] = st;
               }
            }
            pos = p + 5;
         }
      }
   }

   bool TryLoadCandidate(const string content, bool allowLegacy, int &outSchema, bool &outLegacy, string &outReason)
   {
      outSchema=0; outLegacy=false; outReason="";
      if(!IsPlausiblePayload(content)){ outReason="payload_not_plausible"; return false; }
      CJsonReader jr; jr.Load(content);
      bool hasSchema = (StringFind(content,"\"schemaVersion\"")>=0) || jr.Has("schemaVersion");
      bool hasLegacy = (StringFind(content,"\"version\"")>=0) || jr.Has("version");
      if(hasSchema)
      {
         outSchema = (int)jr.GetLong("schemaVersion", 0);
         if(outSchema<=0){ outReason="schema_missing_or_invalid"; return false; }
         if(outSchema > MM_STATE_SCHEMA_VERSION){ outReason="schema_future"; return false; }
         if(!ValidateSemantics(jr, outSchema, false, outReason)) return false;
         return true;
      }
      if(hasLegacy && allowLegacy)
      {
         int lv = (int)jr.GetLong("version", 0);
         if(lv<=0) lv=1;
         if(lv > 1){ outReason="legacy_version_unsupported"; return false; }
         outSchema = lv; outLegacy = true;
         string sem="";
         ValidateSemantics(jr, lv, true, sem);
         return true;
      }
      outReason="no_supported_schema_marker";
      return false;
   }

   void PreserveEvidence(const string srcFull, const string suffix)
   {
      if(!FileIsExist(srcFull, FILE_COMMON)) return;
      string dst = srcFull + suffix;
      if(FileIsExist(dst, FILE_COMMON)) dst = srcFull + suffix + "." + (string)(long)TimeLocal();
      CopyFileCommon(srcFull, dst);
   }

   bool CommitValidatedContent(const string content, ENUM_MM_STORE_RECOVERY rec, bool fromLegacy, bool continuityExplicitlyEstablished)
   {
      CJsonReader jr; jr.Load(content);
      ApplyReader(jr, content);
      m_schemaVersion = MM_STATE_SCHEMA_VERSION;
      m_loadedFromValidSource = true;
      m_hasRestoredProtectiveState = true;
      m_continuityExplicitlyEstablished = continuityExplicitlyEstablished;

      if(m_continuityExplicitlyEstablished)
      {
         m_awaitingExplicitResolution = false;
         m_safeInitRequired = false;
         m_manualReviewRequired = false;
         m_degraded = (rec==MM_RECOVERY_BACKUP || fromLegacy);
         m_operational = true;
         m_lastResult = MM_STORE_OK;
         m_recovery = rec;
         m_statusReason = (rec==MM_RECOVERY_BACKUP ? "restored_backup_explicit_continuity" : "restored_primary_explicit_continuity");
         m_hasLastKnownGoodPrimary = !fromLegacy && (rec==MM_RECOVERY_PRIMARY);
         m_lastKnownGoodContent = SerializeCurrent();
         return true;
      }

      // Conservative: continuity cannot be proven. Preserve loaded state in memory but never authorize
      // risk-increasing actions and never overwrite on disk automatically.
      m_operational = false;
      m_safeInitRequired = false;
      m_manualReviewRequired = true;
      m_awaitingExplicitResolution = true;
      m_degraded = (rec==MM_RECOVERY_BACKUP || rec==MM_RECOVERY_DEGRADED || fromLegacy);
      m_lastResult = MM_STORE_ERR_CONTINUITY_UNCERTAIN;
      m_recovery = rec;
      m_statusReason = fromLegacy ? "legacy_loaded_continuity_uncertain_explicit_resolution_required" :
                       (rec==MM_RECOVERY_BACKUP ? "backup_loaded_continuity_uncertain_explicit_resolution_required"
                                                : "persisted_state_continuity_uncertain_explicit_resolution_required");
      m_hasLastKnownGoodPrimary = false;
      return true;
   }

   bool FailBlocked(const string reason, ENUM_MM_STORE_RESULT res, bool preserveManualReview=true)
   {
      ResetToSafeDefaultsMemoryOnly();
      m_loadedFromValidSource = false;
      m_hasRestoredProtectiveState = false;
      m_continuityExplicitlyEstablished = false;
      m_awaitingExplicitResolution = true;
      m_hasLastKnownGoodPrimary = false;
      m_lastKnownGoodContent = "";
      SetStatus(res, MM_RECOVERY_BLOCKED, reason, false, false, preserveManualReview, true);
      return false;
   }

   void PreserveAllEvidenceForNewInit()
   {
      EnsureDir();
      string dstFull = FullPath(m_statePath);
      string bakFull = FullPath(m_bakPath);
      string stamp = (string)(long)TimeLocal();
      if(FileIsExist(dstFull, FILE_COMMON)) PreserveEvidence(dstFull, ".pre_init." + stamp);
      if(FileIsExist(bakFull, FILE_COMMON)) PreserveEvidence(bakFull, ".pre_init." + stamp);
   }

public:
   CStateStore()
   {
      m_dir="MoneyManager";
      m_statePath="state.json"; m_lockPath="state.lock"; m_bakPath="state.bak"; m_tmpPath="state.tmp";
      m_operational=false; m_safeInitRequired=true; m_manualReviewRequired=false; m_degraded=false;
      m_lastResult=MM_STORE_OK; m_recovery=MM_RECOVERY_NONE; m_statusReason="";
      m_loadedFromValidSource=false; m_hasRestoredProtectiveState=false;
      m_continuityExplicitlyEstablished=false; m_awaitingExplicitResolution=false;
      m_hasLastKnownGoodPrimary=false; m_lastKnownGoodContent="";
      m_schemaVersion=MM_STATE_SCHEMA_VERSION; m_locked=false;
      ResetToSafeDefaultsMemoryOnly();
   }

   // login parameter accepted for backward compatibility; never persisted/used for storage identity.
   bool Init(long login=-1)
   {
      EnsureDir();
      bool ok = LoadInternal();
      if(!ok)
      {
         g_mmLog.Warn("STATE_INIT_UNSAFE","result="+(string)m_lastResult+" reason="+m_statusReason);
         return false;
      }
      g_mmLog.Info("STATE_INIT","result="+(string)m_lastResult+" recovery="+(string)m_recovery+" operational="+(m_operational?"1":"0")+" awaiting_resolution="+(m_awaitingExplicitResolution?"1":"0"));
      return true;
   }

   bool IsOperational(){ return m_operational && !m_safeInitRequired && !m_manualReviewRequired && !m_awaitingExplicitResolution; }
   bool RequiresSafeInit(){ return m_safeInitRequired; }
   bool RequiresManualReview(){ return m_manualReviewRequired; }
   bool RequiresExplicitResolution(){ return m_awaitingExplicitResolution; }
   bool IsContinuityCertain(){ return m_continuityExplicitlyEstablished && m_operational; }
   bool HasRestoredProtectiveState(){ return m_hasRestoredProtectiveState; }
   ENUM_MM_STORE_RESULT LastResult(){ return m_lastResult; }
   ENUM_MM_STORE_RECOVERY LastRecovery(){ return m_recovery; }
   string StatusReason(){ return m_statusReason; }
   string StatePath(){ return FullPath(m_statePath); }

   // Restore existing persisted protective state only when continuity is explicitly established.
   // Never auto-called. Never allowed when continuity is uncertain/unproven.
   bool RestoreExistingState(bool continuityExplicitlyEstablished, bool explicitUserConfirmed)
   {
      if(!m_hasRestoredProtectiveState || !m_loadedFromValidSource)
      {
         SetStatus(MM_STORE_ERR_RESTORE_NOT_ALLOWED, m_recovery, "no_restorable_persisted_state", false, false, true, true);
         g_mmLog.Warn("STATE_RESTORE_DENIED","no_restorable_persisted_state");
         return false;
      }
      if(!continuityExplicitlyEstablished)
      {
         SetStatus(MM_STORE_ERR_RESTORE_NOT_ALLOWED, m_recovery, "restore_requires_explicitly_established_continuity", false, false, true, m_degraded);
         m_awaitingExplicitResolution = true;
         m_operational = false;
         g_mmLog.Warn("STATE_RESTORE_DENIED","continuity_not_explicitly_established");
         return false;
      }
      if(!explicitUserConfirmed)
      {
         SetStatus(MM_STORE_ERR_EXPLICIT_CONFIRM_REQUIRED, m_recovery, "restore_requires_explicit_confirmation", false, false, true, m_degraded);
         m_awaitingExplicitResolution = true;
         m_operational = false;
         g_mmLog.Warn("STATE_RESTORE_DENIED","explicit_confirmation_required");
         return false;
      }

      m_continuityExplicitlyEstablished = true;
      m_awaitingExplicitResolution = false;
      m_safeInitRequired = false;
      m_manualReviewRequired = false;
      m_operational = true;
      m_statusReason = "restored_existing_state_explicit";
      m_lastResult = MM_STORE_OK;
      m_schemaVersion = MM_STATE_SCHEMA_VERSION;

      bool saved = SaveInternal(true, true);
      if(!saved)
      {
         m_operational = false;
         m_manualReviewRequired = true;
         m_awaitingExplicitResolution = true;
         m_continuityExplicitlyEstablished = false;
         g_mmLog.Error("STATE_RESTORE_PERSIST_FAIL", m_statusReason);
         return false;
      }
      g_mmLog.Info("STATE_RESTORE_OK","existing_protective_state_restored_with_explicit_confirmation");
      return true;
   }

   // Initialize new protective state from explicitly provided current MT5 values.
   // - Requires explicit user confirmation. Never auto-called on uncertain continuity.
   // - Preserves previous persisted state/evidence before replacement.
   // - Replaces protective baselines/counters with provided current runtime values (no invention).
   // - Preserves minimal non-protective config already in memory (UI/symbol/profile/template/mode) where available.
   bool InitializeNewProtectiveStateFromCurrent(double dayStartBalance, double dayStartEquity, double peakEquity, double peakBalance,
                                                ENUM_MM_ACCOUNT_MODE mode, const string activeProfileId, bool explicitUserConfirmed)
   {
      if(!explicitUserConfirmed)
      {
         SetStatus(MM_STORE_ERR_EXPLICIT_CONFIRM_REQUIRED, m_recovery, "new_protective_init_requires_explicit_confirmation", false, false, m_manualReviewRequired, m_degraded);
         m_operational = false;
         m_awaitingExplicitResolution = true;
         g_mmLog.Warn("STATE_INIT_DENIED","explicit_confirmation_required");
         return false;
      }

      PreserveAllEvidenceForNewInit();

      m_mode = mode;
      if(activeProfileId!="") m_activeProfileId = activeProfileId;
      m_tradesDay=0; m_tradesWeek=0; m_tradesMonth=0;
      m_dayKey=0; m_weekKey=0; m_monthKey=0;
      m_lastResetServer=0; m_timeFallback=false;
      m_dayStartBalance = (dayStartBalance>0)?dayStartBalance:0;
      m_dayStartEquity  = (dayStartEquity>0)?dayStartEquity:0;
      m_peakEquity      = (peakEquity>0)?peakEquity:0;
      m_peakBalance     = (peakBalance>0)?peakBalance:0;
      m_schemaVersion = MM_STATE_SCHEMA_VERSION;

      m_continuityExplicitlyEstablished = true; // for this newly initialized context
      m_hasRestoredProtectiveState = false;
      m_awaitingExplicitResolution = false;
      m_safeInitRequired = false;
      m_manualReviewRequired = false;
      m_degraded = false;
      m_recovery = MM_RECOVERY_NONE;
      m_lastResult = MM_STORE_OK;
      m_statusReason = "new_protective_state_initialized_explicit";
      m_operational = true;

      bool saved = SaveInternal(true, true);
      if(!saved)
      {
         m_operational = false;
         m_continuityExplicitlyEstablished = false;
         m_awaitingExplicitResolution = true;
         m_manualReviewRequired = true;
         if(m_lastResult==MM_STORE_OK) m_lastResult = MM_STORE_ERR_PROMOTE;
         m_statusReason = "new_protective_init_persist_failed";
         g_mmLog.Error("STATE_INIT_PERSIST_FAIL", m_statusReason);
         return false;
      }
      g_mmLog.Info("STATE_INIT_NEW_OK","explicit_new_protective_state_from_current_mt5");
      return true;
   }

   // Backward-compatible name: implicit/auto call is rejected to prevent F-01 style rebase.
   bool BeginSafeInitFromCurrent(double dayStartBalance, double dayStartEquity, double peakEquity, double peakBalance,
                                 ENUM_MM_ACCOUNT_MODE mode, const string activeProfileId)
   {
      return InitializeNewProtectiveStateFromCurrent(dayStartBalance, dayStartEquity, peakEquity, peakBalance, mode, activeProfileId, false);
   }

   bool BeginSafeInitFromCurrentConfirmed(double dayStartBalance, double dayStartEquity, double peakEquity, double peakBalance,
                                          ENUM_MM_ACCOUNT_MODE mode, const string activeProfileId)
   {
      return InitializeNewProtectiveStateFromCurrent(dayStartBalance, dayStartEquity, peakEquity, peakBalance, mode, activeProfileId, true);
   }

   // Mark store as blocked pending explicit resolution (e.g. runtime account switch detected).
   void BlockPendingExplicitResolution(const string reason, bool manualReview)
   {
      m_operational = false;
      m_safeInitRequired = false;
      m_continuityExplicitlyEstablished = false;
      m_manualReviewRequired = manualReview;
      m_awaitingExplicitResolution = true;
      m_degraded = true;
      if(m_lastResult==MM_STORE_OK) m_lastResult = MM_STORE_ERR_CONTINUITY_UNCERTAIN;
      m_statusReason = reason;
      g_mmLog.Warn("STATE_BLOCKED", reason);
   }

   bool Save(){ return SaveInternal(false, false); }

private:
   bool SaveInternal(bool allowDuringResolution, bool trustedOperationalWrite)
   {
      EnsureDir();
      if(!allowDuringResolution)
      {
         if(m_safeInitRequired || m_manualReviewRequired || m_awaitingExplicitResolution || !m_operational)
         {
            SetStatus(MM_STORE_ERR_CONTINUITY_UNCERTAIN, m_recovery, "save_blocked_resolution_required", false, m_safeInitRequired, m_manualReviewRequired || m_awaitingExplicitResolution, true);
            g_mmLog.Warn("STATE_SAVE_BLOCKED","resolution_or_review_required");
            return false;
         }
      }
      if(allowDuringResolution && !trustedOperationalWrite)
      {
         SetStatus(MM_STORE_ERR_EXPLICIT_CONFIRM_REQUIRED, m_recovery, "untrusted_resolution_save", false, m_safeInitRequired, true, true);
         return false;
      }

      string content = SerializeCurrent();
      if(!IsPlausiblePayload(content))
      {
         SetStatus(MM_STORE_ERR_TEMP_VALIDATE, m_recovery, "serialize_invalid", false, m_safeInitRequired, m_manualReviewRequired || m_awaitingExplicitResolution, true);
         return false;
      }
      {
         CJsonReader jr; jr.Load(content);
         int sv=(int)jr.GetLong("schemaVersion",0); string sem="";
         if(!ValidateSemantics(jr, sv, false, sem))
         {
            SetStatus(MM_STORE_ERR_TEMP_VALIDATE, m_recovery, "serialize_semantic_invalid:"+sem, false, m_safeInitRequired, m_manualReviewRequired || m_awaitingExplicitResolution, true);
            return false;
         }
      }

      if(!AcquireLock())
      {
         SetStatus(MM_STORE_ERR_LOCK, m_recovery, "lock_failed", IsOperational(), m_safeInitRequired, m_manualReviewRequired || m_awaitingExplicitResolution, m_degraded);
         return false;
      }

      string tmpFull = FullPath(m_tmpPath);
      string dstFull = FullPath(m_statePath);
      string bakFull = FullPath(m_bakPath);

      if(FileIsExist(tmpFull, FILE_COMMON)) FileDelete(tmpFull, FILE_COMMON);
      if(!WriteTextFile(tmpFull, content))
      {
         SetStatus(MM_STORE_ERR_TEMP_WRITE, m_recovery, "temp_write_failed", false, m_safeInitRequired, m_manualReviewRequired || m_awaitingExplicitResolution, true);
         ReleaseLock();
         return false;
      }

      // Validate temp
      string tmpRead="";
      int schema=0; bool legacy=false; string reason="";
      if(!ReadTextFile(tmpFull, tmpRead) || !TryLoadCandidate(tmpRead, false, schema, legacy, reason) || schema!=MM_STATE_SCHEMA_VERSION)
      {
         PreserveEvidence(tmpFull, ".invalid");
         FileDelete(tmpFull, FILE_COMMON);
         SetStatus(MM_STORE_ERR_TEMP_VALIDATE, m_recovery, "temp_validate_failed:"+reason, false, m_safeInitRequired, m_manualReviewRequired || m_awaitingExplicitResolution, true);
         ReleaseLock();
         return false;
      }

      // Backup handling (F-03): never replace backup with unvalidated/invalid/parseable-regressed candidate.
      // Rotate primary->backup only if current primary is fully valid current-schema and trusted/known-good.
      bool backupOk = true;
      string cur="";
      if(FileIsExist(dstFull, FILE_COMMON) && ReadTextFile(dstFull, cur))
      {
         int cs=0; bool cl=false; string cr="";
         if(TryLoadCandidate(cur, false, cs, cl, cr) && cs==MM_STATE_SCHEMA_VERSION && !cl)
         {
            bool primaryValidTrusted = (m_hasLastKnownGoodPrimary || IsOperational());
            if(primaryValidTrusted)
               backupOk = CopyFileCommon(dstFull, bakFull);
            else
               backupOk = true; // preserve existing backup
         }
         else
         {
            PreserveEvidence(dstFull, ".corrupt");
            backupOk = FileIsExist(bakFull, FILE_COMMON) || !FileIsExist(dstFull, FILE_COMMON);
         }
      }
      if(!backupOk)
      {
         PreserveEvidence(tmpFull, ".nobackup");
         FileDelete(tmpFull, FILE_COMMON);
         SetStatus(MM_STORE_ERR_BACKUP, m_recovery, "backup_preserve_failed", false, m_safeInitRequired, true, true);
         m_operational = false; m_awaitingExplicitResolution = true;
         ReleaseLock();
         return false;
      }

      // Promote validated temp
      bool promoted = FileMove(tmpFull, FILE_COMMON, dstFull, FILE_COMMON);
      if(!promoted)
      {
         bool wroteFallback = WriteTextFile(dstFull, tmpRead);
         if(FileIsExist(tmpFull, FILE_COMMON)) FileDelete(tmpFull, FILE_COMMON);
         if(!wroteFallback)
         {
            SetStatus(MM_STORE_ERR_PROMOTE, m_recovery, "promote_write_failed", false, m_safeInitRequired, true, true);
            m_operational = false; m_awaitingExplicitResolution = true; m_manualReviewRequired = true;
            ReleaseLock();
            return false;
         }
      }
      else
      {
         if(FileIsExist(tmpFull, FILE_COMMON)) FileDelete(tmpFull, FILE_COMMON);
      }

      // Post-promotion verification (F-05)
      string promotedContent="";
      int ps=0; bool pl=false; string pr="";
      bool verifyOk = ReadTextFile(dstFull, promotedContent) &&
                      TryLoadCandidate(promotedContent, false, ps, pl, pr) &&
                      ps==MM_STATE_SCHEMA_VERSION && !pl;
      if(!verifyOk)
      {
         SetStatus(MM_STORE_ERR_PROMOTE, m_recovery, "promote_verify_failed:"+pr, false, m_safeInitRequired, true, true);
         m_operational = false; m_awaitingExplicitResolution = true; m_manualReviewRequired = true;
         m_hasLastKnownGoodPrimary = false;
         g_mmLog.Error("STATE_SAVE_FAIL","promote_or_verify_failed");
         ReleaseLock();
         return false;
      }

      m_hasLastKnownGoodPrimary = true;
      m_lastKnownGoodContent = content;
      if(trustedOperationalWrite)
      {
         m_operational = true;
         m_safeInitRequired = false;
         m_manualReviewRequired = false;
         m_awaitingExplicitResolution = false;
         m_degraded = false;
         m_recovery = MM_RECOVERY_PRIMARY;
         m_lastResult = MM_STORE_OK;
         if(m_statusReason=="") m_statusReason="save_ok";
      }
      else
      {
         m_operational = IsOperational();
         m_recovery = MM_RECOVERY_PRIMARY;
         m_lastResult = MM_STORE_OK;
         m_statusReason = "save_ok";
      }

      ReleaseLock();
      return true;
   }

   bool LoadInternal()
   {
      EnsureDir();
      ResetToSafeDefaultsMemoryOnly();
      m_hasRestoredProtectiveState = false;
      m_continuityExplicitlyEstablished = false;
      m_awaitingExplicitResolution = false;
      m_hasLastKnownGoodPrimary = false;
      m_lastKnownGoodContent = "";

      string dstFull = FullPath(m_statePath);
      string bakFull = FullPath(m_bakPath);

      string primary="", backup="";
      bool hasPrimary = FileIsExist(dstFull, FILE_COMMON) && ReadTextFile(dstFull, primary);
      bool hasBackup  = FileIsExist(bakFull, FILE_COMMON) && ReadTextFile(bakFull, backup);

      if(hasPrimary)
      {
         int schema=0; bool legacy=false; string reason="";
         if(TryLoadCandidate(primary, true, schema, legacy, reason))
         {
            if(legacy) PreserveEvidence(dstFull, ".legacy");
            CommitValidatedContent(primary, MM_RECOVERY_PRIMARY, legacy, false);
            if(legacy) g_mmLog.Warn("STATE_LEGACY_MIGRATED","continuity uncertain; explicit resolution required");
            else g_mmLog.Warn("STATE_CONTINUITY_UNCERTAIN","persisted state found but account continuity cannot be proven; explicit resolution required");
            return true;
         }
         else
         {
            if(reason=="schema_future"){ PreserveEvidence(dstFull, ".future"); return FailBlocked("schema_future", MM_STORE_ERR_SCHEMA_FUTURE, true); }
            PreserveEvidence(dstFull, ".corrupt");
            g_mmLog.Warn("STATE_PRIMARY_INVALID", reason);
         }
      }

      if(hasBackup)
      {
         int schema=0; bool legacy=false; string reason="";
         if(TryLoadCandidate(backup, true, schema, legacy, reason))
         {
            if(legacy) PreserveEvidence(bakFull, ".legacy");
            CommitValidatedContent(backup, MM_RECOVERY_BACKUP, legacy, false);
            g_mmLog.Warn("STATE_RECOVERED_BACKUP","continuity uncertain; explicit resolution required");
            return true;
         }
         else
         {
            if(reason=="schema_future"){ PreserveEvidence(bakFull, ".future"); return FailBlocked("backup_schema_future", MM_STORE_ERR_SCHEMA_FUTURE, true); }
            PreserveEvidence(bakFull, ".corrupt");
            g_mmLog.Warn("STATE_BACKUP_INVALID", reason);
         }
      }

      if(!hasPrimary && !hasBackup)
      {
         ResetToSafeDefaultsMemoryOnly();
         m_loadedFromValidSource = false;
         m_hasRestoredProtectiveState = false;
         m_hasLastKnownGoodPrimary = false;
         m_lastKnownGoodContent = "";
         m_continuityExplicitlyEstablished = false;
         m_operational = false;
         m_safeInitRequired = false;
         m_manualReviewRequired = true;
         m_awaitingExplicitResolution = true;
         m_degraded = false;
         m_recovery = MM_RECOVERY_NONE;
         m_lastResult = MM_STORE_OK;
         m_statusReason = "no_persisted_state_explicit_init_required";
         g_mmLog.Info("STATE_FRESH","no persisted state; explicit initialization required");
         return true;
      }

      return FailBlocked("no_valid_state_artifact", MM_STORE_ERR_RECOVERY_FAILED, true);
   }

public:
   ENUM_MM_ACCOUNT_MODE AccountMode(){ return m_mode; }
   void SetAccountMode(ENUM_MM_ACCOUNT_MODE m){ m_mode=m; }
   MM_UIState UI(){ return m_ui; }
   void SetUI(const MM_UIState &ui){ m_ui=ui; }

   void GetSymbolState(const string symbol, MM_SymbolState &out)
   {
      int idx=FindSymbol(symbol);
      if(idx>=0){ out=m_symbols[idx]; return; }
      out.Reset(); out.symbol=symbol;
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

   // In-memory only (runtime/persisted state as loaded). No MT5 reads, no invention.
   double DayStartBalance(){ return m_dayStartBalance; }
   double DayStartEquity(){ return m_dayStartEquity; }
   double PeakEquity(){ return m_peakEquity; }
   double PeakBalance(){ return m_peakBalance; }
   int TradesDayCount(){ return m_tradesDay; }
   int TradesWeekCount(){ return m_tradesWeek; }
   int TradesMonthCount(){ return m_tradesMonth; }

   // Compatibility no-op: StateStore must not read MT5 or compute/invent financial values.
   void SyncPeaks(){ }

   bool Backup(){ return true; }
};

#endif // MM_STATE_STORE_MQH
