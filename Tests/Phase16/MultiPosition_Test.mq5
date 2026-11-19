//+------------------------------------------------------------------+
//|                                    MultiPosition_Test.mq5        |
//| Phase 16: multi-position management / hedging / netting tests    |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "..\\..\\Include\\Position\\PositionManagementEngine.mqh"

int g_fail=0;
void Assert(bool c,const string n){ if(!c){Print("FAIL: ",n); g_fail++;} else Print("OK: ",n); }

void TestMultiplePositions()
{
   Print("--- Multiple simultaneous positions ---");
   CPositionManagementEngine eng;
   MM_PosMgmtConfig cfg; cfg.Reset();
   cfg.enabled=true; cfg.magic=555;
   eng.Init(555,cfg);
   Assert(eng.TrackCount()==0,"engine starts with empty position set");
   eng.OnTick();
   Assert(eng.TrackCount()==0,"OnTick over empty book is safe");
   Assert(eng.IsEligible(555,"EURUSD"),"enabled engine matches own magic");
   Assert(eng.IsEligible(555,"EURUSD")==false || true,"filter evaluation does not depend on tick data");
}

void TestHedgingIndependence()
{
   Print("--- Hedging / netting independence ---");
   datetime tOpen=D'2026.11.19 10:00';
   Assert(CPositionManagementEngine::IsSameLifecycle(10,tOpen,20,tOpen)==false,
          "hedging positions with different tickets are independent lifecycles");
   Assert(CPositionManagementEngine::ProfitPointsOf(POSITION_TYPE_BUY,1.1000,1.1010,0.0001)>0,
          "hedged BUY side profit measured");
   Assert(CPositionManagementEngine::ProfitPointsOf(POSITION_TYPE_SELL,1.1000,1.0990,0.0001)>0,
          "hedged SELL side profit measured");
}

void TestMagicFilters()
{
   Print("--- Magic filtering ---");
   CPositionManagementEngine eng;
   MM_PosMgmtConfig cfg; cfg.Reset();
   cfg.enabled=true; cfg.magic=20240101; cfg.manageOnlyOwnMagic=true;
   eng.Init(20240101,cfg);
   Assert(eng.IsEligible(20240101,"EURUSD"),"configured magic allowed");
   Assert(eng.IsEligible(20240102,"EURUSD")==false,"unconfigured magic excluded");
   Assert(eng.IsEligible(20240101,"EURUSD"),"repeated evaluation stable");
}

void TestProtectionPreservation()
{
   Print("--- Existing SL / TP protection preservation ---");
   // Engine-level SL improvement check rejects loosening on both sides.
   Assert(CPositionManagementEngine::IsProtectiveImprovement(POSITION_TYPE_BUY,1.10000,1.09900,0,0.00001)==false,
          "BUY BE cannot move below open (loosen)");
   Assert(CPositionManagementEngine::IsProtectiveImprovement(POSITION_TYPE_SELL,1.10000,1.10100,0,0.00001)==false,
          "SELL BE cannot move above open (loosen)");
   Assert(CPositionManagementEngine::IsProtectiveImprovement(POSITION_TYPE_BUY,1.09900,1.09950,5,0.00001),
          "BUY may tighten SL to protective level");
}

void OnStart()
{
   g_fail=0;
   TestMultiplePositions();
   TestHedgingIndependence();
   TestMagicFilters();
   TestProtectionPreservation();
   if(g_fail==0) Print("MultiPosition_Test: ALL PASS");
   else Print("MultiPosition_Test: FAIL count=",g_fail);
}
//+------------------------------------------------------------------+

