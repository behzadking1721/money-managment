//+------------------------------------------------------------------+
//|                                    EngineMath_Test.mq5           |
//| Phase 16: deterministic decision-math tests for                  |
//| CPositionManagementEngine (no live position required).           |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "..\\..\\Include\\Position\\PositionManagementEngine.mqh"

int g_fail=0;
void Assert(bool c,const string n){ if(!c){Print("FAIL: ",n); g_fail++;} else Print("OK: ",n); }
void AssertNear(double a,double b,double eps,const string n)
{
   bool ok=(MathAbs(a-b)<=eps);
   if(!ok) Print("   got=",DoubleToString(a,5)," expected=",DoubleToString(b,5));
   Assert(ok,n);
}

void TestProfitAndR()
{
   Print("--- Profit points / R-multiple ---");
   AssertNear(CPositionManagementEngine::ProfitPointsOf(POSITION_TYPE_BUY,1.10000,1.10100,0.00001),100.0,1e-9,"BUY +100 points");
   AssertNear(CPositionManagementEngine::ProfitPointsOf(POSITION_TYPE_SELL,1.10000,1.09900,0.00001),100.0,1e-9,"SELL +100 points");
   AssertNear(CPositionManagementEngine::ProfitPointsOf(POSITION_TYPE_BUY,1.10000,1.09900,0.00001),-100.0,1e-9,"BUY negative points");
   AssertNear(CPositionManagementEngine::RMultipleOf(POSITION_TYPE_BUY,1.10000,0.00100,1.10100),1.0,1e-9,"BUY 1R");
   AssertNear(CPositionManagementEngine::RMultipleOf(POSITION_TYPE_SELL,1.10000,0.00200,1.09800),1.0,1e-9,"SELL 1R");
   AssertNear(CPositionManagementEngine::RMultipleOf(POSITION_TYPE_BUY,1.10000,0.0,1.10100),0.0,1e-12,"R unknown without risk distance");
   AssertNear(CPositionManagementEngine::RMultipleOf(POSITION_TYPE_BUY,1.10000,0.00100,1.09950),0.0,1e-12,"R not reported for losing trade");
}

void TestBETriggers()
{
   Print("--- Break-even activation thresholds ---");
   string why="";
   Assert(CPositionManagementEngine::BETriggerReached(MM_BE_TRIGGER_POINTS,19,0.9,20,1.0,why)==false,"points below threshold false");
   Assert(CPositionManagementEngine::BETriggerReached(MM_BE_TRIGGER_POINTS,20,0.9,20,1.0,why)==true,"points threshold reached");
   Assert(CPositionManagementEngine::BETriggerReached(MM_BE_TRIGGER_R,999,0.99,20,1.0,why)==false,"R below threshold false");
   Assert(CPositionManagementEngine::BETriggerReached(MM_BE_TRIGGER_R,0,1.0,20,1.0,why)==true,"R threshold reached");
   Assert(CPositionManagementEngine::BETriggerReached(MM_BE_TRIGGER_ANY,0,1.2,20,1.0,why)==true,"ANY via R");
   Assert(CPositionManagementEngine::BETriggerReached(MM_BE_TRIGGER_ANY,20,0.0,20,1.0,why)==true,"ANY via points");
   Assert(CPositionManagementEngine::BETriggerReached(MM_BE_TRIGGER_OFF,100,5.0,1,1.0,why)==false,"OFF never triggers");
   Assert(CPositionManagementEngine::BETriggerReached(MM_BE_TRIGGER_R,0,1.0,0,0.0,why)==false,"zero threshold disabled");
}

void TestTrailing()
{
   Print("--- Trailing activation / candidate / update step ---");
   string why="";
   Assert(CPositionManagementEngine::TrailActivationReached(0,0,0,0,why)==true,"no activation threshold => active");
   Assert(CPositionManagementEngine::TrailActivationReached(30,0,29,5,why)==false,"activation points not reached");
   Assert(CPositionManagementEngine::TrailActivationReached(30,0,30,5,why)==true,"activation points reached");
   Assert(CPositionManagementEngine::TrailActivationReached(0,1.5,100,1.49,why)==false,"activation R not reached");
   Assert(CPositionManagementEngine::TrailActivationReached(0,1.5,100,1.5,why)==true,"activation R reached");

   double sl=0;
   Assert(CPositionManagementEngine::ComputeTrailSL(TRAIL_FIXED,POSITION_TYPE_BUY,1.10500,0,0,0,50,0.00001,sl,why),"fixed BUY computes");
   AssertNear(sl,1.10450,1e-9,"fixed BUY SL = price - 50 points");
   Assert(CPositionManagementEngine::ComputeTrailSL(TRAIL_FIXED,POSITION_TYPE_SELL,1.10500,0,0,0,50,0.00001,sl,why),"fixed SELL computes");
   AssertNear(sl,1.10550,1e-9,"fixed SELL SL = price + 50 points");

   Assert(CPositionManagementEngine::ComputeTrailSL(TRAIL_ATR,POSITION_TYPE_BUY,1.10500,0.00100,0,0,1.5,0.00001,sl,why),"ATR BUY computes");
   AssertNear(sl,1.10350,1e-9,"ATR BUY SL = price - 1.5*ATR");
   Assert(CPositionManagementEngine::ComputeTrailSL(TRAIL_ATR,POSITION_TYPE_BUY,1.10500,0,0,0,1.5,0.00001,sl,why)==false,"ATR unavailable rejected");

   Assert(CPositionManagementEngine::ComputeTrailSL(TRAIL_CANDLE,POSITION_TYPE_BUY,1.10500,0,1.10400,1.10600,0,0.00001,sl,why),"candle BUY computes");
   AssertNear(sl,1.10400,1e-9,"candle BUY uses previous low");
   Assert(CPositionManagementEngine::ComputeTrailSL(TRAIL_CANDLE,POSITION_TYPE_SELL,1.10500,0,1.10400,1.10600,0,0.00001,sl,why),"candle SELL computes");
   AssertNear(sl,1.10600,1e-9,"candle SELL uses previous high");
   Assert(CPositionManagementEngine::ComputeTrailSL(TRAIL_CANDLE,POSITION_TYPE_SELL,1.10500,0,0,0,0,0.00001,sl,why)==false,"invalid candle rejected");

   Assert(CPositionManagementEngine::IsProtectiveImprovement(POSITION_TYPE_BUY,0,1.10400,5,0.00001),"no existing SL => candidate accepted");
   Assert(CPositionManagementEngine::IsProtectiveImprovement(POSITION_TYPE_BUY,1.10300,1.10310,5,0.00001)==false,"BUY improvement below update step rejected");
   Assert(CPositionManagementEngine::IsProtectiveImprovement(POSITION_TYPE_BUY,1.10300,1.10350,5,0.00001),"BUY improvement at step accepted");
   Assert(CPositionManagementEngine::IsProtectiveImprovement(POSITION_TYPE_BUY,1.10400,1.10350,0,0.00001)==false,"BUY loosening rejected");
   Assert(CPositionManagementEngine::IsProtectiveImprovement(POSITION_TYPE_SELL,1.10500,1.10550,0,0.00001)==false,"SELL loosening rejected");
   Assert(CPositionManagementEngine::IsProtectiveImprovement(POSITION_TYPE_SELL,1.10500,1.10450,0,0.00001),"SELL tightening accepted");
}

void TestPartialVolume()
{
   Print("--- Multi-level partial close volume ---");
   double v=0; bool full=false; string why="";
   Assert(CPositionManagementEngine::ComputePartialCloseVolume(1.00,1.00,30,false,0.01,100,0.01,v,full,why),"30% of 1.00 computes");
   AssertNear(v,0.30,1e-9,"partial volume 0.30");
   Assert(!full,"not a full close");

   Assert(CPositionManagementEngine::ComputePartialCloseVolume(0.20,1.00,50,false,0.01,100,0.01,v,full,why),"large level capped to remaining minimum");
   AssertNear(v,0.19,1e-9,"capped close leaves VOLUME_MIN");

   Assert(CPositionManagementEngine::ComputePartialCloseVolume(1.00,1.00,30,false,0.50,100,0.01,v,full,why)==false,"below minimum close volume rejected");
   Assert(why=="close_volume_below_min","below-min reason reported");

   Assert(CPositionManagementEngine::ComputePartialCloseVolume(1.00,1.00,0,false,0.01,100,0.01,v,full,why)==false,"0% rejected");
   Assert(CPositionManagementEngine::ComputePartialCloseVolume(1.00,1.00,100,false,0.01,100,0.01,v,full,why)==false,"100% rejected (partial path)");
   Assert(CPositionManagementEngine::ComputePartialCloseVolume(0,1.00,30,false,0.01,100,0.01,v,full,why)==false,"no volume rejected");

   Assert(CPositionManagementEngine::ComputePartialCloseVolume(0.37,1.00,100,true,0.01,100,0.01,v,full,why),"remainder mode computes");
   Assert(full,"remainder mode flagged full close");
   AssertNear(v,0.37,1e-9,"remainder closes current volume");

   double pcts[3]; pcts[0]=30; pcts[1]=30; pcts[2]=40;
   Assert(CPositionManagementEngine::DeriveLevelMask(1.00,0.29,pcts,3,0.01)==0,"no level below first target");
   Assert(CPositionManagementEngine::DeriveLevelMask(1.00,0.30,pcts,3,0.01)==1,"level 1 derived from confirmed volume");
   Assert(CPositionManagementEngine::DeriveLevelMask(1.00,0.60,pcts,3,0.01)==3,"levels 1+2 derived");
   Assert(CPositionManagementEngine::DeriveLevelMask(1.00,1.00,pcts,3,0.01)==7,"all levels derived");
   Assert(CPositionManagementEngine::DeriveLevelMask(0.0,1.00,pcts,3,0.01)==0,"unknown baseline yields no mask");

   Assert(CPositionManagementEngine::PartialLevelTriggerReached(1.0,1.0,0,0),"partial R trigger at threshold");
   Assert(CPositionManagementEngine::PartialLevelTriggerReached(0.99,1.0,0,0)==false,"partial R below threshold");
   Assert(CPositionManagementEngine::PendingCloseConfirmed(0.70,0.70,0.01),"pending close confirmed at target");
   Assert(CPositionManagementEngine::PendingCloseConfirmed(0.705,0.70,0.01),"pending close tolerance half step");
   Assert(CPositionManagementEngine::PendingCloseConfirmed(0.72,0.70,0.01)==false,"pending close not confirmed above tolerance");
}

void TestFiltersAndStatus()
{
   Print("--- Magic / symbol filtering and status ---");
   CPositionManagementEngine eng;
   MM_PosMgmtConfig cfg; cfg.Reset();
   cfg.enabled=true; cfg.magic=555; cfg.manageOnlyOwnMagic=true;
   cfg.symbolFilterEnabled=true; cfg.symbolList="EURUSD, XAUUSD";
   eng.Init(555,cfg);
   Assert(eng.IsEligible(555,"EURUSD"),"own magic allowed");
   Assert(eng.IsEligible(555,"XAUUSD"),"second allowed symbol");
   Assert(eng.IsEligible(999,"EURUSD")==false,"unrelated magic excluded");
   Assert(eng.IsEligible(555,"GBPUSD")==false,"symbol outside allow-list excluded");
   Assert(eng.StatusSummary()!="AUTO off","enabled status reported");
   Assert(StringFind(eng.StatusSummary(),"AUTO on")>=0,"status contains AUTO on");
   Assert(eng.TrackCount()==0,"no positions => no tracks");
   eng.OnTick();
   Assert(eng.TrackCount()==0,"OnTick with no positions is a no-op");
   eng.SetEnabled(false);
   Assert(StringFind(eng.StatusSummary(),"AUTO off")>=0,"disabled status reported");

   cfg.manageOnlyOwnMagic=false; cfg.symbolFilterEnabled=false; eng.Init(555,cfg);
   Assert(eng.IsEligible(1,"ANY"),"filter disabled allows other magic");
}

void OnStart()
{
   g_fail=0;
   TestProfitAndR();
   TestBETriggers();
   TestTrailing();
   TestPartialVolume();
   TestFiltersAndStatus();
   if(g_fail==0) Print("EngineMath_Test: ALL PASS");
   else Print("EngineMath_Test: FAIL count=",g_fail);
}
//+------------------------------------------------------------------+
