//+------------------------------------------------------------------+
//|                                         RecoveryEngine_Test.mq5  |
//| Phase 12 / TD-05 TD-17: Persistence & Recovery Engine focused    |
//| tests: restart, backup fallback, corrupt data, corrupt save,     |
//| state inconsistency, risk-increasing block, risk-reduction active|
//+------------------------------------------------------------------+
#property script_show_inputs
#include "..\\..\\Include\\State\\RecoveryEngine.mqh"

int g_fail=0;
void Assert(bool cond,const string name){ if(!cond){ Print("FAIL: ",name); g_fail++; } else Print("OK: ",name); }

string ReadAll(const string full)
{
   string s="";
   int h=FileOpen(full, FILE_READ|FILE_TXT|FILE_COMMON|FILE_ANSI|FILE_SHARE_READ);
   if(h==INVALID_HANDLE) return "";
   while(!FileIsEnding(h)) s+=FileReadString(h);
   FileClose(h);
   return s;
}

bool WriteAll(const string full,const string content)
{
   int h=FileOpen(full, FILE_WRITE|FILE_TXT|FILE_COMMON|FILE_ANSI);
   if(h==INVALID_HANDLE) return false;
   FileWriteString(h,content);
   FileClose(h);
   return true;
}

void CleanStateArtifacts()
{
   string files[28]={"state.json","state.bak","state.tmp","state.lock",
                     "state.json.legacy","state.json.corrupt","state.json.future",
                     "state.bak.legacy","state.bak.corrupt","state.bak.future",
                     "state.tmp.invalid","state.tmp.nobackup",
                     "state.json.pre_init.1","state.json.pre_init.2",
                     "state.bak.pre_init.1","state.bak.pre_init.2",
                     "state.json.invalid","state.json.prelegacy",
                     "state.json.persist_fail","state.bak.persist_fail",
                     "state.json.recovery_blocked","state.bak.recovery_blocked",
                     "state.json.explicit_init","state.bak.explicit_init",
                     "state.json.partial","state.bak.partial",
                     "state.json.zero_len","state.bak.zero_len"};
   for(int i=0;i<28;i++)
      if(FileIsExist("MoneyManager\\"+files[i], FILE_COMMON))
         FileDelete("MoneyManager\\"+files[i], FILE_COMMON);
}

void OnStart()
{
   g_fail=0;
   string dir="MoneyManager";
   string primary=dir+"\\state.json";
   string bak=dir+"\\state.bak";
   CleanStateArtifacts();

   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);

   //------------------------------------------------------------------
   // 1) Fresh init: no persisted state => not operational, risk-increasing blocked,
   //    risk-reduction active (invariant), explicit resolution required.
   //------------------------------------------------------------------
   CStateStore st; CRecoveryEngine rec; rec.SetStore(st);
   bool inited = st.Init();
   Assert(inited, "fresh init returns true");
   Assert(!st.IsOperational(), "fresh init not operational");
   Assert(st.RequiresExplicitResolution() || st.RequiresManualReview(), "fresh init requires resolution/review");
   bool recOk = rec.RecoverOnRestart();
   Assert(!recOk, "recovery not operational on fresh state");
   Assert(rec.RiskIncreasingBlocked(), "recovery blocks risk-increasing on fresh state");
   Assert(rec.RiskReductionActive(), "INVARIANT: risk-reduction active on fresh state");
   Assert(rec.RequiresExplicitResolution() || rec.RequiresManualReview(), "recovery requires explicit resolution/review");

   //------------------------------------------------------------------
   // 2) Explicit new protective initialization from current MT5 values
   //    => operational, risk-increasing allowed, risk-reduction active.
   //------------------------------------------------------------------
   bool confirmed = st.BeginSafeInitFromCurrentConfirmed(bal, eq, eq, bal, ACCOUNT_PERSONAL, "personal");
   Assert(confirmed, "explicit confirmed safe init persisted");
   Assert(st.IsOperational(), "operational after explicit confirmed init");
   rec.RecoverOnRestart();
   Assert(rec.IsOperational(), "recovery operational after explicit init");
   Assert(!rec.RiskIncreasingBlocked(), "recovery allows risk-increasing after explicit init");
   Assert(rec.RiskReductionActive(), "INVARIANT: risk-reduction active after explicit init");
   Assert(rec.Outcome()==MM_RECOVERY_OUTCOME_EXPLICIT_INIT_OK, "recovery outcome explicit init ok");

   //------------------------------------------------------------------
   // 3) Simulated restart: reload persisted state => continuity uncertain,
   //    not operational, risk-increasing blocked, risk-reduction active,
   //    non-protective config preserved, no auto rebase.
   //------------------------------------------------------------------
   st.SetAccountMode(ACCOUNT_PROP);
   MM_UIState ui=st.UI(); ui.panelX=99; ui.panelY=8; ui.mini=true; st.SetUI(ui);
   MM_SymbolState ss; ss.Reset(); ss.symbol=_Symbol; ss.sizingMode=SIZING_MANUAL_LOT; ss.riskValue=3.0; ss.templateId="tplR";
   st.SetSymbolState(ss);
   Assert(st.Save(),"save after changes before simulated restart");

   CleanStateArtifacts();
   // Re-write the saved primary+backup manually to simulate a persisted restart boundary.
   string saved=ReadAll(dir+"\\state.json");
   Assert(StringLen(saved)>0, "saved state non-empty");
   Assert(WriteAll(primary, saved), "rewrite primary for restart sim");
   Assert(WriteAll(bak, saved), "rewrite backup for restart sim");

   CStateStore st2; CRecoveryEngine rec2; rec2.SetStore(st2);
   bool inited2 = st2.Init();
   Assert(inited2, "restart reload init returns true");
   Assert(!st2.IsOperational(), "restart reload not operational before explicit resolution");
   Assert(st2.HasRestoredProtectiveState(), "restart reload preserves restored protective state in memory");
   Assert(st2.RequiresExplicitResolution() || st2.RequiresManualReview(), "restart reload requires explicit resolution/review");
   MM_UIState ui2=st2.UI(); Assert(ui2.panelX==99 && ui2.panelY==8, "restart preserves non-protective UI config");
   MM_SymbolState ss2; st2.GetSymbolState(_Symbol, ss2);
   Assert(ss2.sizingMode==SIZING_MANUAL_LOT && ss2.templateId=="tplR", "restart preserves symbol config");
   rec2.RecoverOnRestart();
   Assert(!rec2.IsOperational(), "recovery not operational on restart (continuity uncertain)");
   Assert(rec2.RiskIncreasingBlocked(), "recovery blocks risk-increasing on restart");
   Assert(rec2.RiskReductionActive(), "INVARIANT: risk-reduction active on restart");
   Assert(rec2.RequiresExplicitResolution() || rec2.RequiresManualReview(), "recovery requires resolution on restart");

   //------------------------------------------------------------------
   // 4) Corrupted primary + valid backup => backup fallback, blocked,
   //    risk-reduction active, original+backup preserved.
   //------------------------------------------------------------------
   CleanStateArtifacts();
   Assert(WriteAll(primary, "{corrupt_json"), "write corrupt primary");
   string good="{\"schemaVersion\":2,\"accountMode\":0,\"activeProfileId\":\"\",\"activeTemplateId\":\"\","
               "\"tradesDay\":0,\"tradesWeek\":0,\"tradesMonth\":0,\"dayKey\":0,\"weekKey\":0,\"monthKey\":0,"
               "\"lastResetServer\":0,\"timeFallback\":false,\"dayStartBalance\":1000,\"dayStartEquity\":1000,"
               "\"peakEquity\":1000,\"peakBalance\":1000,\"ui.x\":20,\"ui.y\":20,\"ui.mini\":false,\"ui.hidden\":false,"
               "\"symbolCount\":0}";
   Assert(WriteAll(bak, good), "write valid backup");
   CStateStore st4; CRecoveryEngine rec4; rec4.SetStore(st4);
   bool ok4 = st4.Init();
   Assert(ok4, "corrupt primary + valid backup init returns true");
   Assert(!st4.IsOperational(), "backup fallback not operational (continuity uncertain)");
   Assert(st4.LastRecovery()==MM_RECOVERY_BACKUP, "recovery from backup recorded");
   rec4.RecoverOnRestart();
   Assert(rec4.Outcome()==MM_RECOVERY_OUTCOME_BACKUP_FALLBACK, "recovery outcome backup fallback");
   Assert(rec4.RiskIncreasingBlocked(), "recovery blocks risk-increasing on backup fallback");
   Assert(rec4.RiskReductionActive(), "INVARIANT: risk-reduction active on backup fallback");
   Assert(FileIsExist(primary, FILE_COMMON), "original corrupt primary preserved");
   Assert(FileIsExist(bak, FILE_COMMON), "backup preserved after fallback");

   //------------------------------------------------------------------
   // 5) Corrupted primary + corrupted backup => blocked, manual review,
   //    risk-reduction active, no auto reset/rebase.
   //------------------------------------------------------------------
   CleanStateArtifacts();
   Assert(WriteAll(primary, "{corrupt"), "write corrupt primary");
   Assert(WriteAll(bak, "not-json"), "write corrupt backup");
   CStateStore st5; CRecoveryEngine rec5; rec5.SetStore(st5);
   bool ok5 = st5.Init();
   Assert(!ok5 || !st5.IsOperational(), "corrupt artifacts not operational");
   Assert(!st5.IsOperational(), "corrupt artifacts blocked");
   Assert(st5.RequiresManualReview() || st5.RequiresExplicitResolution(), "corrupt artifacts require review/resolution");
   rec5.RecoverOnRestart();
   Assert(!rec5.IsOperational(), "recovery not operational on corrupt artifacts");
   Assert(rec5.RiskIncreasingBlocked(), "recovery blocks risk-increasing on corrupt artifacts");
   Assert(rec5.RiskReductionActive(), "INVARIANT: risk-reduction active on corrupt artifacts");
   Assert(rec5.RequiresManualReview() || rec5.RequiresExplicitResolution(), "recovery requires review on corrupt artifacts");

   //------------------------------------------------------------------
   // 6) Future schema => blocked, no auto rebase, risk-reduction active.
   //------------------------------------------------------------------
   CleanStateArtifacts();
   string future="{\"schemaVersion\":99,\"accountMode\":0,\"activeProfileId\":\"\",\"activeTemplateId\":\"\","
                 "\"tradesDay\":0,\"tradesWeek\":0,\"tradesMonth\":0,\"dayKey\":0,\"weekKey\":0,\"monthKey\":0,"
                 "\"lastResetServer\":0,\"timeFallback\":false,\"dayStartBalance\":1000,\"dayStartEquity\":1000,"
                 "\"peakEquity\":1000,\"peakBalance\":1000,\"ui.x\":20,\"ui.y\":20,\"ui.mini\":false,\"ui.hidden\":false,"
                 "\"symbolCount\":0}";
   Assert(WriteAll(primary, future), "write future schema primary");
   CStateStore st6; CRecoveryEngine rec6; rec6.SetStore(st6);
   bool ok6 = st6.Init();
   Assert(!ok6 || !st6.IsOperational(), "future schema not operational");
   Assert(!st6.IsOperational(), "future schema blocked");
   rec6.RecoverOnRestart();
   Assert(!rec6.IsOperational(), "recovery not operational on future schema");
   Assert(rec6.RiskIncreasingBlocked(), "recovery blocks risk-increasing on future schema");
   Assert(rec6.RiskReductionActive(), "INVARIANT: risk-reduction active on future schema");
   Assert(FileIsExist(primary, FILE_COMMON), "future-schema primary preserved (no overwrite)");

   //------------------------------------------------------------------
   // 7) Privacy: persisted file must not contain account identity.
   //------------------------------------------------------------------
   CleanStateArtifacts();
   bool c7 = st.BeginSafeInitFromCurrentConfirmed(bal,eq,eq,bal,ACCOUNT_PROP,"prop");
   Assert(c7, "explicit init for privacy check");
   string content=ReadAll(primary);
   Assert(StringFind(content, "\"login\"") < 0, "no login persisted");
   Assert(StringFind(content, "AccountLogin") < 0, "no AccountLogin key");
   Assert(StringFind(content, "\"server\"") < 0, "no server key persisted");
   Assert(StringFind(content, "\"broker\"") < 0 && StringFind(content, "\"Broker\"") < 0, "no broker key persisted");

   //------------------------------------------------------------------
   // 8) Recovery report text populated and deterministic.
   //------------------------------------------------------------------
   CleanStateArtifacts();
   CStateStore st8; CRecoveryEngine rec8; rec8.SetStore(st8);
   st8.Init();
   rec8.RecoverOnRestart();
   string report=rec8.ReportText();
   Assert(StringFind(report, "outcome=")>=0, "report has outcome field");
   Assert(StringFind(report, "riskReductionActive=1")>=0, "report confirms risk-reduction active");
   Assert(StringFind(report, "riskIncBlocked=1")>=0, "report confirms risk-increasing blocked");

   if(g_fail==0) Print("RecoveryEngine_Test: ALL PASS"); else Print("RecoveryEngine_Test: FAIL count=",g_fail);
}
