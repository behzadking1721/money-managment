//+------------------------------------------------------------------+
//|                                             StateStore_Test.mq5  |
//|          Serialize/restore, per-symbol, migration (Phase 1)      |
//+------------------------------------------------------------------+
#property script_show_inputs
#include "..\\..\\Include\\State\\StateStore.mqh"

int g_fail=0;
void Assert(bool cond,const string name){ if(!cond){ Print("FAIL: ",name); g_fail++; } else Print("OK: ",name); }

void OnStart()
{
   g_fail=0;
   CStateStore st;
   Assert(st.Init(AccountInfoInteger(ACCOUNT_LOGIN)),"init/load");
   st.SetAccountMode(ACCOUNT_PROP);
   MM_UIState ui=st.UI(); ui.panelX=123; ui.panelY=45; ui.mini=true; ui.hidden=false; st.SetUI(ui);
   MM_SymbolState ss; ss.Reset(); ss.symbol=_Symbol; ss.sizingMode=SIZING_MANUAL_LOT; ss.riskValue=2.5; ss.templateId="tplA";
   st.SetSymbolState(ss);
   Assert(st.Save(),"save");

   CStateStore st2;
   Assert(st2.Init(AccountInfoInteger(ACCOUNT_LOGIN)),"reload");
   Assert(st2.AccountMode()==ACCOUNT_PROP,"account mode");
   MM_UIState ui2=st2.UI(); Assert(ui2.panelX==123 && ui2.panelY==45 && ui2.mini==true,"ui restore");
   MM_SymbolState ss2; st2.GetSymbolState(_Symbol,ss2);
   Assert(ss2.sizingMode==SIZING_MANUAL_LOT && MathAbs(ss2.riskValue-2.5)<0.0001 && ss2.templateId=="tplA","symbol restore");

   // migration: write legacy version=0 state and reload
   string dir="MoneyManager"; string base="state_"+(string)AccountInfoInteger(ACCOUNT_LOGIN);
   string legacy="{\"version\":0,\"login\":"+(string)AccountInfoInteger(ACCOUNT_LOGIN)+",\"accountMode\":1,\"tradesDay\":5}";
   // backup real file then inject legacy
   string path=dir+"\\"+base+".json"; string bak=dir+"\\"+base+".migtest.bak";
   int in=FileOpen(path,FILE_READ|FILE_BIN|FILE_COMMON); uchar buf[]; int sz=0;
   if(in!=INVALID_HANDLE){ sz=(int)FileSize(in); ArrayResize(buf,sz>0?sz:0); if(sz>0)FileReadArray(in,buf,0,sz); FileClose(in);
      int bo=FileOpen(bak,FILE_WRITE|FILE_BIN|FILE_COMMON); if(bo!=INVALID_HANDLE){ if(sz>0)FileWriteArray(bo,buf,0,sz); FileClose(bo);} }
   int h=FileOpen(path,FILE_WRITE|FILE_TXT|FILE_COMMON|FILE_ANSI);
   if(h!=INVALID_HANDLE){ FileWriteString(h,legacy); FileClose(h); }
   CStateStore st3; bool okMig=st3.Init(AccountInfoInteger(ACCOUNT_LOGIN));
   Assert(okMig,"migration load (v0->current)");
   Assert(st3.AccountMode()==ACCOUNT_PROP,"migration field");
   // restore original
   if(sz>0){ int r=FileOpen(path,FILE_WRITE|FILE_BIN|FILE_COMMON); if(r!=INVALID_HANDLE){ FileWriteArray(r,buf,0,sz); FileClose(r);} }

   if(g_fail==0) Print("StateStore_Test: ALL PASS"); else Print("StateStore_Test: FAIL count=",g_fail);
}
