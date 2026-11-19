//+------------------------------------------------------------------+
//|                                     StateStore_Foundation_Test.mq5 |
//| Phase 2.1 corrected: F-01..F-05 safety, continuity, validation   |
//+------------------------------------------------------------------+
#property script_show_inputs
#include "..\\..\\Include\\State\\StateStore.mqh"

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
   string files[40]={"state.json","state.bak","state.tmp","state.lock",
                     "state.json.legacy","state.json.corrupt","state.json.future",
                     "state.bak.legacy","state.bak.corrupt","state.bak.future",
                     "state.tmp.invalid","state.tmp.nobackup","state.json.prelegacy",
                     "state.json.invalid","state.bak.invalid"};
   for(int i=0;i<40;i++)
      if(FileIsExist("MoneyManager\\"+files[i], FILE_COMMON))
         FileDelete("MoneyManager\\"+files[i], FILE_COMMON);
}

void OnStart()
{
   g_fail=0;
   string dir="MoneyManager";
   string primary=dir+"\\state.json";
   string bak=dir+"\\state.bak";
   string tmp=dir+"\\state.tmp";

   CleanStateArtifacts();
   double bal=AccountInfoDouble(ACCOUNT_BALANCE);
   double eq =AccountInfoDouble(ACCOUNT_EQUITY);

   // T01: fresh init requires explicit resolution; implicit init rejected; explicit confirmed init allowed
   CStateStore st;
   Assert(st.Init(),"T01 fresh init returns true");
   Assert(!st.IsOperational(),"T01 not operational");
   Assert(st.RequiresExplicitResolution() || st.RequiresManualReview(),"T01 requires explicit resolution");
   Assert(!st.BeginSafeInitFromCurrent(bal,eq,eq,bal,ACCOUNT_PERSONAL,"personal"),"T01 implicit init rejected (F-01)");
   Assert(st.BeginSafeInitFromCurrentConfirmed(bal,eq,eq,bal,ACCOUNT_PERSONAL,"personal"),"T01 explicit init established");
   Assert(st.IsOperational(),"T01 operational after explicit init");
   string s=ReadAll(primary);
   Assert(StringFind(s,"\"schemaVersion\":2")>=0,"T01 has schemaVersion v2");
   Assert(StringFind(s,"\"login\"")<0,"T01 no login persisted");
   Assert(StringFind(s,"\"server\"")<0 && StringFind(s,"\"broker\"")<0 && StringFind(s,"\"Broker\"")<0,"T01 no broker/server identifiers");

   // T02: continuity uncertain after restart-like reload preserves restored protective/config state and blocks (no auto rebase)
   MM_UIState ui=st.UI(); ui.panelX=55; ui.panelY=66; ui.mini=true; ui.hidden=false; st.SetUI(ui);
   MM_SymbolState ss; ss.Reset(); ss.symbol=_Symbol; ss.sizingMode=SIZING_MANUAL_LOT; ss.riskValue=1.5; ss.templateId="tplX";
   st.SetSymbolState(ss);
   st.SetAccountMode(ACCOUNT_PROP);
   Assert(st.Save(),"T02 save ok");
   CStateStore st2;
   Assert(st2.Init(),"T02 reload init true");
   Assert(!st2.IsOperational(),"T02 blocked before explicit resolution");
   Assert(st2.HasRestoredProtectiveState(),"T02 restored protective state preserved");
   Assert(st2.RequiresExplicitResolution() || st2.RequiresManualReview(),"T02 continuity uncertain => explicit resolution required");
   MM_UIState ui2=st2.UI(); Assert(ui2.panelX==55 && ui2.panelY==66 && ui2.mini==true,"T02 UI loaded/preserved");
   MM_SymbolState ss2; st2.GetSymbolState(_Symbol,ss2);
   Assert(ss2.sizingMode==SIZING_MANUAL_LOT && MathAbs(ss2.riskValue-1.5)<0.0001 && ss2.templateId=="tplX","T02 symbol loaded/preserved");
   Assert(st2.AccountMode()==ACCOUNT_PROP,"T02 mode loaded/preserved");

   // T03 (F-01/F-02): valid prior protective baselines must NOT be auto-reset; explicit init replaces only after confirmation
   CleanStateArtifacts();
   string crafted="{\"schemaVersion\":2,\"accountMode\":0,\"activeProfileId\":\"p\",\"activeTemplateId\":\"\",\"tradesDay\":9,\"tradesWeek\":7,\"tradesMonth\":11,\"dayKey\":20200101,\"weekKey\":202001,\"monthKey\":202001,\"lastResetServer\":0,\"timeFallback\":false,\"dayStartBalance\":99999.00,\"dayStartEquity\":88888.00,\"peakEquity\":77777.00,\"peakBalance\":66666.00,\"ui.x\":20,\"ui.y\":20,\"ui.mini\":false,\"ui.hidden\":false,\"symbolCount\":0}";
   Assert(WriteAll(primary,crafted),"T03 craft persisted protective state");
   CStateStore st3;
   Assert(st3.Init(),"T03 init on crafted state");
   Assert(st3.HasRestoredProtectiveState(),"T03 restored state present");
   Assert(!st3.IsOperational(),"T03 blocked (no auto apply)");
   Assert(st3.RequiresExplicitResolution() || st3.RequiresManualReview(),"T03 explicit resolution required");
   Assert(MathAbs(st3.DayStartBalance()-99999.00)<0.01,"T03 dayStartBalance preserved before explicit init");
   Assert(MathAbs(st3.PeakEquity()-77777.00)<0.01,"T03 peakEquity preserved before explicit init");
   Assert(st3.TradesDayCount()==9,"T03 tradesDay preserved before explicit init");
   Assert(!st3.BeginSafeInitFromCurrent(bal,eq,eq,bal,ACCOUNT_PERSONAL,""),"T03 implicit init rejected");
   Assert(MathAbs(st3.DayStartBalance()-99999.00)<0.01,"T03 no auto rebase on implicit attempt");
   double cbal=AccountInfoDouble(ACCOUNT_BALANCE), ceq=AccountInfoDouble(ACCOUNT_EQUITY);
   Assert(st3.BeginSafeInitFromCurrentConfirmed(cbal,ceq,ceq,cbal,ACCOUNT_PERSONAL,""),"T03 explicit init from current");
   Assert(st3.IsOperational(),"T03 operational after explicit init");
   Assert(MathAbs(st3.DayStartBalance()-cbal)<0.01 || cbal<=0,"T03 dayStartBalance replaced from current");
   Assert(MathAbs(st3.DayStartEquity()-ceq)<0.01 || ceq<=0,"T03 dayStartEquity replaced from current");
   Assert(st3.TradesDayCount()==0,"T03 counters reset on explicit init");

   // T04 (F-03/F-05): corrupt primary with valid backup => deterministic recovery, blocked pending explicit resolution
   CleanStateArtifacts();
   CStateStore st4a; Assert(st4a.Init(),"T04 init"); Assert(st4a.BeginSafeInitFromCurrentConfirmed(bal,eq,eq,bal,ACCOUNT_PERSONAL,""),"T04 explicit init");
   MM_UIState u4=st4a.UI(); u4.panelX=11; u4.panelY=22; st4a.SetUI(u4); Assert(st4a.Save(),"T04 save 1");
   u4.panelX=33; u4.panelY=44; st4a.SetUI(u4); Assert(st4a.Save(),"T04 save 2 (backup rotated)");
   string backupContent = ReadAll(bak);
   Assert(StringFind(backupContent,"schemaVersion")>=0,"T04 backup exists and valid");
   Assert(WriteAll(primary,"{corrupt"),"T04 corrupt primary");
   CStateStore st4;
   Assert(st4.Init(),"T04 init recovers from backup context");
   Assert(!st4.IsOperational(),"T04 not operational (continuity uncertain)");
   Assert(st4.RequiresExplicitResolution() || st4.RequiresManualReview(),"T04 requires explicit resolution");
   Assert(st4.HasRestoredProtectiveState(),"T04 restored from backup");

   // T05: corrupt primary and corrupt/missing backup => blocked/manual review, not operational
   CleanStateArtifacts();
   Assert(WriteAll(primary,"{corrupt"),"T05 corrupt primary");
   Assert(WriteAll(bak,"not-json"),"T05 corrupt backup");
   CStateStore st5;
   bool ok5 = st5.Init();
   Assert(!ok5 || !st5.IsOperational(),"T05 no operational unsafe state");
   Assert(!st5.IsOperational(),"T05 not operational");
   Assert(st5.RequiresManualReview() || st5.RequiresExplicitResolution(),"T05 requires review/resolution");

   // T06 (F-04 privacy/migration): legacy v0 with login field must not persist login and must require explicit resolution
   CleanStateArtifacts();
   string legacy="{\"version\":0,\"login\":123456,\"accountMode\":1,\"tradesDay\":5,\"activeProfileId\":\"prop\"}";
   Assert(WriteAll(primary,legacy),"T06 write legacy");
   CStateStore st6;
   Assert(st6.Init(),"T06 legacy init returns true");
   Assert(!st6.IsOperational(),"T06 legacy not operational");
   Assert(st6.RequiresExplicitResolution() || st6.RequiresManualReview(),"T06 legacy requires explicit resolution");
   Assert(st6.BeginSafeInitFromCurrentConfirmed(bal,eq,eq,bal,ACCOUNT_PROP,"prop"),"T06 explicit init");
   string s6=ReadAll(primary);
   Assert(StringFind(s6,"\"login\"")<0,"T06 login not persisted after canonical save");
   Assert(StringFind(s6,"123456")<0,"T06 legacy login value not persisted");

   // T07 (F-04): future schema => fail-safe blocked, not operational
   CleanStateArtifacts();
   Assert(WriteAll(primary,"{\"schemaVersion\":999,\"accountMode\":0}"),"T07 write future schema");
   CStateStore st7;
   bool ok7 = st7.Init();
   Assert(!ok7 || !st7.IsOperational(),"T07 future schema not operational");
   Assert(!st7.IsOperational(),"T07 blocked");

   // T08 (F-05): stale tmp/invalid backup artifacts do not break validated save path
   CleanStateArtifacts();
   CStateStore st8; Assert(st8.Init(),"T08 init"); Assert(st8.BeginSafeInitFromCurrentConfirmed(bal,eq,eq,bal,ACCOUNT_PERSONAL,""),"T08 explicit init");
   Assert(WriteAll(tmp,"garbage"),"T08 pre-existing tmp");
   Assert(WriteAll(bak,"garbage-bak"),"T08 pre-existing invalid bak");
   Assert(st8.Save(),"T08 save succeeds despite stale artifacts");
   string s8=ReadAll(primary);
   Assert(StringFind(s8,"schemaVersion")>=0,"T08 valid primary written");

   // T09 (F-04 semantic): semantically invalid primary rejected in favor of valid backup, remains blocked pending explicit resolution
   CleanStateArtifacts();
   string valid="{\"schemaVersion\":2,\"accountMode\":0,\"activeProfileId\":\"ok\",\"activeTemplateId\":\"\",\"tradesDay\":0,\"tradesWeek\":0,\"tradesMonth\":0,\"dayKey\":0,\"weekKey\":0,\"monthKey\":0,\"lastResetServer\":0,\"timeFallback\":false,\"dayStartBalance\":1000.00,\"dayStartEquity\":1000.00,\"peakEquity\":1000.00,\"peakBalance\":1000.00,\"ui.x\":1,\"ui.y\":2,\"ui.mini\":false,\"ui.hidden\":false,\"symbolCount\":0}";
   Assert(WriteAll(bak,valid),"T09 write valid backup");
   Assert(WriteAll(primary,"{\"schemaVersion\":2,\"accountMode\":-5,\"dayStartBalance\":-10}"),"T09 write semantically invalid primary");
   CStateStore st9;
   Assert(st9.Init(),"T09 init recovers from valid backup");
   Assert(st9.HasRestoredProtectiveState(),"T09 restored from backup");
   Assert(!st9.IsOperational(),"T09 blocked pending explicit resolution");
   Assert(MathAbs(st9.DayStartBalance()-1000.00)<0.01,"T09 used backup baseline, not invalid primary");

   // T10: runtime switch-like block preserves restored state and requires explicit resolution
   CleanStateArtifacts();
   CStateStore st10; Assert(st10.Init(),"T10 init"); Assert(st10.BeginSafeInitFromCurrentConfirmed(bal,eq,eq,bal,ACCOUNT_PERSONAL,""),"T10 explicit init");
   Assert(st10.Save(),"T10 save");
   CStateStore st10b; Assert(st10b.Init(),"T10b reload"); // continuity uncertain, restored preserved
   Assert(st10b.HasRestoredProtectiveState(),"T10b restored state present");
   st10b.BlockPendingExplicitResolution("runtime_account_switch_explicit_resolution_required", true);
   Assert(!st10b.IsOperational(),"T10b blocked after switch");
   Assert(st10b.RequiresExplicitResolution() || st10b.RequiresManualReview(),"T10b explicit resolution required");
   Assert(st10b.HasRestoredProtectiveState(),"T10b protective state still preserved (not discarded)");

   // T11: GetSymbolState uses in-memory default for unknown
   MM_SymbolState unknown; st10.GetSymbolState("NOSUCH_SYMBOL_XYZ", unknown);
   Assert(unknown.symbol=="NOSUCH_SYMBOL_XYZ","T11 unknown symbol default name");

   if(g_fail==0) Print("StateStore_Foundation_Test: ALL PASS");
   else Print("StateStore_Foundation_Test: FAIL count=",g_fail);
}
