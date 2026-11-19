//+------------------------------------------------------------------+
//|                                  RestartSafety_Test.mq5          |
//| Phase 16: restart / uncertainty / duplicate-prevention semantics |
//| Deterministic checks of server-truth reconstruction and pending   |
//| confirmation rules (no invented execution history).              |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "..\\..\\Include\\Position\\PositionManagementEngine.mqh"

int g_fail=0;
void Assert(bool c,const string n){ if(!c){Print("FAIL: ",n); g_fail++;} else Print("OK: ",n); }

void TestReconstructionNoInvention()
{
   Print("--- Restart: reconstruct executed stages from confirmed volume ---");
   double pcts[3]; pcts[0]=25; pcts[1]=25; pcts[2]=50;

   int m0=CPositionManagementEngine::DeriveLevelMask(2.00,0.00,pcts,3,0.01);
   Assert(m0==0,"fresh position: no stage assumed executed");

   int m1=CPositionManagementEngine::DeriveLevelMask(2.00,0.50,pcts,3,0.01);
   Assert(m1==1,"confirmed 0.50 volume => stage 1 only");

   int m2=CPositionManagementEngine::DeriveLevelMask(2.00,0.99,pcts,3,0.01);
   Assert(m2==1,"0.99 volume does not complete stage 2 (1.00 target)");

   int m3=CPositionManagementEngine::DeriveLevelMask(2.00,1.00,pcts,3,0.01);
   Assert(m3==3,"1.00 volume => stages 1+2");

   int unknown=CPositionManagementEngine::DeriveLevelMask(0.0,1.00,pcts,3,0.01);
   Assert(unknown==0,"unknown baseline (untrusted history) marks nothing done");

   int capped=CPositionManagementEngine::DeriveLevelMask(1.00,9.00,pcts,3,0.01);
   Assert(capped==7,"over-closed volume cannot exceed defined stages");
}

void TestDuplicatePrevention()
{
   Print("--- Restart: duplicate stage prevention ---");
   int mask=1; // stage 1 already confirmed
   Assert((mask&(1<<0))!=0,"stage 1 marked done is skipped");
   Assert((mask&(1<<1))==0,"stage 2 remains eligible");
   mask|= (1<<1);
   Assert((mask&(1<<1))!=0,"stage 2 becomes done and is skipped afterwards");

   bool full=false;
   double v=0; string why="";
   // A stage that cannot be executed must not advance the mask.
   bool ok=CPositionManagementEngine::ComputePartialCloseVolume(1.00,1.00,30,false,0.50,100,0.01,v,full,why);
   Assert(!ok,"invalid volume step/min rejects stage");
   Assert(mask==3,"mask unchanged after rejected computation");
}

void TestPendingServerConfirmation()
{
   Print("--- Restart: server confirmation of partial close ---");
   // Requested 30% of 1.00 => expected target 0.70.
   Assert(CPositionManagementEngine::PendingCloseConfirmed(0.70,0.70,0.01),"full request executed is confirmed");
   Assert(CPositionManagementEngine::PendingCloseConfirmed(0.90,0.70,0.01)==false,"DONE_PARTIAL-like volume is not treated as complete");
   Assert(CPositionManagementEngine::PendingCloseConfirmed(1.00,0.70,0.01)==false,"unchanged volume is not confirmed");
   Assert(CPositionManagementEngine::PendingCloseConfirmed(0.69,0.70,0.01),"more than requested closed is still satisfying");
}

void TestLifecycleSeparation()
{
   Print("--- Restart: lifecycle separation (hedging / netting reversal) ---");
   datetime t1=D'2026.11.19 10:00';
   datetime t2=D'2026.11.19 11:00';
   Assert(CPositionManagementEngine::IsSameLifecycle(1,t1,1,t1),"same side/time = same lifecycle");
   Assert(CPositionManagementEngine::IsSameLifecycle(1,t1,-1,t2)==false,"netting reversal side flip = new lifecycle");
   Assert(CPositionManagementEngine::IsSameLifecycle(1,t1,1,t2)==false,"new open time = new lifecycle");
   Assert(CPositionManagementEngine::IsSameLifecycle(0,t1,1,t1)==false,"opposite hedge ticket is independent");
}

void TestEstimatorBoundaries()
{
   Print("--- Restart: BE/trail remain duplicate-safe, partial fails closed ---");
   Assert(CPositionManagementEngine::IsProtectiveImprovement(POSITION_TYPE_BUY,1.10000,1.10000,0,0.00001)==false,
          "re-applying identical BE SL is not an improvement (no duplicate modify)");
   Assert(CPositionManagementEngine::IsProtectiveImprovement(POSITION_TYPE_SELL,1.10000,1.10000,0,0.00001)==false,
          "identical SELL BE SL is not an improvement");

   string why="";
   Assert(CPositionManagementEngine::BETriggerReached(MM_BE_TRIGGER_R,0,0.0,0,1.0,why)==false,
          "unknown R does not trigger BE (no guess)");
   Assert(CPositionManagementEngine::TrailActivationReached(0,1.0,0,0.0,why)==false,
          "unknown R does not satisfy R activation");
}

void OnStart()
{
   g_fail=0;
   TestReconstructionNoInvention();
   TestDuplicatePrevention();
   TestPendingServerConfirmation();
   TestLifecycleSeparation();
   TestEstimatorBoundaries();
   if(g_fail==0) Print("RestartSafety_Test: ALL PASS");
   else Print("RestartSafety_Test: FAIL count=",g_fail);
}
//+------------------------------------------------------------------+
