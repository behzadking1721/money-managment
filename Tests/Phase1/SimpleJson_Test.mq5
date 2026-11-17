//+------------------------------------------------------------------+
//|                                            SimpleJson_Test.mq5  |
//|                      Unit-style round-trip tests (Phase 1)       |
//+------------------------------------------------------------------+
#property script_show_inputs
#include "..\\..\\Include\\Core\\SimpleJson.mqh"

int g_fail=0;
void Assert(bool cond,const string name){ if(!cond){ Print("FAIL: ",name); g_fail++; } else Print("OK: ",name); }

void OnStart()
{
   g_fail=0;
   // round-trip state-like tagged keys
   CJsonBuilder b; b.Reset(); b.ObjStart();
   b.Key("version",1); b.Key("login",(long)12345678); b.Key("accountMode",2);
   b.Key("tradesDay",3); b.KeyBool("ui.mini",true); b.KeyBool("ui.hidden",false);
   b.Key("sym.EURUSD.mode",0); b.Key("sym.EURUSD.risk",1.25,6); b.Key("sym.EURUSD.tpl","tpl-1");
   b.Key("note","path C:\\tmp \"q\" / end"); b.Key("fa","سلام / تست"); b.Key("neg",-42); b.Key("dec",-1.5,6);
   b.ObjEnd();
   string js=b.Str();
   CJsonReader r; r.Load(js);
   Assert(r.GetLong("version")==1,"version");
   Assert(r.GetLong("login")==12345678,"login");
   Assert(r.GetLong("accountMode")==2,"accountMode");
   Assert(r.GetLong("tradesDay")==3,"tradesDay");
   Assert(r.GetBool("ui.mini",false)==true,"bool true");
   Assert(r.GetBool("ui.hidden",true)==false,"bool false");
   Assert(r.GetLong("sym.EURUSD.mode",-1)==0,"sym mode");
   Assert(MathAbs(r.GetDouble("sym.EURUSD.risk")-1.25)<0.00001,"sym risk decimal");
   Assert(r.GetString("sym.EURUSD.tpl")=="tpl-1","sym tpl");
   Assert(StringFind(r.GetString("note"),"C:\\tmp")>=0,"string backslash");
   Assert(StringFind(r.GetString("note"),"\"q\"")>=0 || StringFind(r.GetString("note"),"q")>=0,"string quote");
   Assert(StringFind(r.GetString("fa"),"سلام")>=0,"persian/unicode passthrough");
   Assert(r.GetLong("neg")==-42,"negative int");
   Assert(MathAbs(r.GetDouble("dec")+1.5)<0.00001,"negative decimal");
   Assert(r.GetLong("missing",77)==77,"missing default long");
   Assert(r.GetBool("missingB",true)==true,"missing default bool");

   // empty/zero cases
   CJsonBuilder b2; b2.Reset(); b2.ObjStart(); b2.Key("x",0); b2.Key("s",""); b2.Key("d",0.0,4); b2.ObjEnd();
   CJsonReader r2; r2.Load(b2.Str());
   Assert(r2.GetLong("x",-1)==0,"zero int");
   Assert(r2.GetString("s","d")=="","empty string");
   Assert(MathAbs(r2.GetDouble("d",1.0)-0.0)<0.0001,"zero double");

   if(g_fail==0) Print("SimpleJson_Test: ALL PASS"); else Print("SimpleJson_Test: FAIL count=",g_fail);
}
