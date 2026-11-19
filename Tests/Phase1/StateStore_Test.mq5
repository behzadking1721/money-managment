//+------------------------------------------------------------------+
//|                                             StateStore_Test.mq5  |
//| Phase 2.1 corrected: explicit resolution, no auto rebase, privacy |
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
   string files[24]={"state.json","state.bak","state.tmp","state.lock",
                     "state.json.legacy","state.json.corrupt","state.json.future",
                     "state.bak.legacy","state.bak.corrupt","state.bak.future",
                     "state.tmp.invalid","state.tmp.nobackup","state.json.prelegacy",
                     "state.json.invalid"};
   for(int i=0;i<24;i++)
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

   // 1) fresh init => no persisted protective state, but continuity/initialization requires explicit resolution (no auto init)
   CStateStore st;
   bool inited = st.Init();
   Assert(inited, "fresh init returns true");
   Assert(!st.IsOperational(), "fresh init not operational");
   Assert(st.RequiresExplicitResolution() || st.RequiresManualReview(), "fresh init requires explicit resolution/review");
   Assert(!st.HasRestoredProtectiveState(), "fresh init has no restored protective state");

   // 2) implicit/auto safe init must be rejected (F-01 safety)
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   bool implicit = st.BeginSafeInitFromCurrent(bal, eq, eq, bal, ACCOUNT_PERSONAL, "personal");
   Assert(!implicit, "implicit BeginSafeInitFromCurrent rejected");
   Assert(!st.IsOperational(), "still not operational after implicit init");

   // 3) explicit user-confirmed new protective initialization from current MT5/runtime values
   bool confirmed = st.BeginSafeInitFromCurrentConfirmed(bal, eq, eq, bal, ACCOUNT_PROP, "prop");
   Assert(confirmed, "explicit confirmed safe init persisted");
   Assert(st.IsOperational(), "operational after explicit confirmed init");

   // 4) mutate minimal config/state and save
   st.SetAccountMode(ACCOUNT_PROP);
   MM_UIState ui=st.UI(); ui.panelX=123; ui.panelY=45; ui.mini=true; ui.hidden=false; st.SetUI(ui);
   MM_SymbolState ss; ss.Reset(); ss.symbol=_Symbol; ss.sizingMode=SIZING_MANUAL_LOT; ss.riskValue=2.5; ss.templateId="tplA";
   st.SetSymbolState(ss);
   Assert(st.Save(),"save after changes");

   // 5) restart-like reload => continuity cannot be proven => restored state preserved but blocked pending explicit resolution (no auto rebase)
   CStateStore st2;
   bool inited2 = st2.Init();
   Assert(inited2, "reload init returns true (continuity uncertain)");
   Assert(!st2.IsOperational(), "reload not operational before explicit resolution");
   Assert(st2.HasRestoredProtectiveState(), "reload preserves restored protective state in memory");
   Assert(st2.RequiresExplicitResolution() || st2.RequiresManualReview(), "reload requires explicit resolution/review");
   MM_UIState ui2=st2.UI(); Assert(ui2.panelX==123 && ui2.panelY==45, "reload preserves non-protective UI config");
   MM_SymbolState ss2; st2.GetSymbolState(_Symbol, ss2);
   Assert(ss2.sizingMode==SIZING_MANUAL_LOT && ss2.templateId=="tplA", "reload preserves symbol config");

   // privacy: persisted file must not contain Account Login or Broker Server identifiers
   string content=ReadAll(primary);
   Assert(StringFind(content, "\"login\"") < 0, "no login persisted");
   Assert(StringFind(content, "AccountLogin") < 0, "no AccountLogin key");
   Assert(StringFind(content, "\"server\"") < 0, "no server key persisted");
   Assert(StringFind(content, "\"broker\"") < 0 && StringFind(content, "\"Broker\"") < 0, "no broker key persisted");

   // 6) legacy migration (v0) must drop forbidden identity, load safely, and require explicit resolution (never auto-apply)
   CleanStateArtifacts();
   string legacy="{\"version\":0,\"login\":123456,\"accountMode\":1,\"activeProfileId\":\"prop\",\"ui.x\":77}";
   Assert(WriteAll(primary, legacy), "write legacy");
   CStateStore st3; bool okMig=st3.Init();
   Assert(okMig, "legacy load returns true (blocked pending resolution)");
   Assert(!st3.IsOperational(), "legacy not operational");
   Assert(st3.RequiresExplicitResolution() || st3.RequiresManualReview(), "legacy requires explicit resolution");
   Assert(st3.HasRestoredProtectiveState(), "legacy protective/config state loaded");
   bool okNew = st3.BeginSafeInitFromCurrentConfirmed(bal,eq,eq,bal,ACCOUNT_PROP,"prop");
   Assert(okNew, "explicit init after legacy");
   string s3=ReadAll(primary);
   Assert(StringFind(s3,"\"login\"")<0 && StringFind(s3,"123456")<0, "legacy login not persisted after canonical save");

   // 7) corrupt primary + corrupt backup => blocked/manual review, not operational
   CleanStateArtifacts();
   Assert(WriteAll(primary,"{corrupt"), "write corrupt primary");
   Assert(WriteAll(bak,"not-json"), "write corrupt backup");
   CStateStore st4;
   bool ok4 = st4.Init();
   Assert(!ok4 || !st4.IsOperational(), "corrupt artifacts not operational");
   Assert(!st4.IsOperational(), "corrupt artifacts blocked");
   Assert(st4.RequiresManualReview() || st4.RequiresExplicitResolution(), "corrupt artifacts require review/resolution");

   if(g_fail==0) Print("StateStore_Test: ALL PASS"); else Print("StateStore_Test: FAIL count=",g_fail);
}
