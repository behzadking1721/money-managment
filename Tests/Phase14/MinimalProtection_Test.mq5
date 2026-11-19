//+------------------------------------------------------------------+
//|                            MinimalProtection_Test.mq5            |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs
#include "..\\..\\Include\\Protection\\Protection.mqh"
#include "..\\..\\Include\\PropFirm\\PropFirm.mqh"

int g_fail=0;
void Assert(bool c,const string n){ if(!c){Print("FAIL: ",n); g_fail++;} else Print("OK: ",n); }

void OnStart()
{
   g_fail=0;
   CProtection p; p.Init();
   Assert(p.DailyLoss()==0.0, "fresh init daily loss = 0");
   CPropFirm pf; SPropFirmRules r; pf.LoadPreset("FTMO", r);
   pf.Enable(r);
   Assert(pf.IsEnabled()==true, "prop firm enabled");
   if(g_fail==0) Print("MinimalProtection_Test: ALL PASS"); else Print("MinimalProtection_Test: FAIL count=",g_fail);
}
