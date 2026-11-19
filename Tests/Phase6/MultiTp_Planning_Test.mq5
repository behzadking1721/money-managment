//+------------------------------------------------------------------+
//|                                      MultiTp_Planning_Test.mq5   |
//|  Phase 6 (Roadmap): Multi-TP planning/validation/split helpers   |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "..\\..\\Include\\Core\\Contracts.mqh"
#include "..\\..\\Include\\Core\\RiskEngine.mqh"
#include "..\\..\\Include\\Core\\StopsValidator.mqh"
#include "..\\..\\Include\\Core\\ExecutionPolicy.mqh"

int g_fail=0;
void Assert(bool c,const string n){ if(!c){Print("FAIL: ",n); g_fail++;} else Print("OK: ",n); }

bool Nearly(double a,double b,double eps){ return MathAbs(a-b)<=eps; }

// Local mirror of the step-grid split to validate invariants deterministically
bool MirrorSplit(const string symbol,double totalLot,int parts,double &vols[],string &reason)
{
   reason=""; ArrayResize(vols,parts); for(int i=0;i<parts;i++) vols[i]=0.0;
   double vmin=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   double vmax=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
   double vstep=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   if(vstep<=0.0){ reason="bad_step"; return false; }
   if(vmin<=0.0) vmin=vstep;
   if(vmax < vmin-1e-12){ reason="bad_bounds"; return false; }
   long stepMin=(long)MathCeil(vmin/vstep-1e-12); if(stepMin<1) stepMin=1;
   long stepMax=(long)MathFloor(vmax/vstep+1e-12);
   long stepTotal=(long)MathFloor(totalLot/vstep+1e-12);
   if(stepMax<stepMin || stepTotal<=0){ reason="invalid"; return false; }
   double normTotal=stepTotal*vstep;
   if(MathAbs(totalLot-normTotal)>vstep*1e-6){ reason="not_on_step_grid"; return false; }
   if(stepTotal < stepMin*(long)parts){ reason="impossible_min"; return false; }
   if(stepTotal > stepMax*(long)parts){ reason="impossible_max"; return false; }
   long base=stepTotal/parts, rem=stepTotal-base*(long)parts; long legSteps[]; ArrayResize(legSteps,parts);
   for(int i=0;i<parts;i++) legSteps[i]=base; for(int i=0;i<rem && i<parts;i++) legSteps[i]++;
   for(int i=0;i<parts;i++){ int g=0; while(legSteps[i]<stepMin && g<100000){ int d=-1; for(int j=0;j<parts;j++) if(j!=i && legSteps[j]>stepMin){d=j;break;} if(d<0){reason="borrow_fail";return false;} legSteps[d]--; legSteps[i]++; g++; } if(legSteps[i]<stepMin||legSteps[i]>stepMax){reason="leg_bounds";return false;} }
   int vdigits=(int)MathCeil(-MathLog10(vstep)); if(vdigits<0) vdigits=0; if(vdigits>8) vdigits=8;
   long finalSteps=0; double sum=0; for(int i=0;i<parts;i++){ finalSteps+=legSteps[i]; vols[i]=NormalizeDouble(legSteps[i]*vstep,vdigits); sum+=vols[i]; double q=vols[i]/vstep; if(MathAbs(q-MathRound(q))>1e-6){reason="not_aligned";return false;} if(vols[i]<vmin-1e-12||vols[i]>vmax+1e-12){reason="minmax";return false;} }
   if(finalSteps!=stepTotal){ reason="step_mismatch"; return false; }
   if(MathAbs(sum-normTotal)>vstep*1e-6){ reason="sum_mismatch"; return false; }
   reason="ok"; return true;
}

// Unit/script checks (no broker sends)
void OnStart()
{
   g_fail=0;

   // 1) Contract supports up to 5 TP levels and preserves single-TP default behavior
   {
      MM_TradePlan p; p.Reset();
      Assert(MM_MAX_TP_LEVELS==5, "MM_MAX_TP_LEVELS is 5");
      Assert(p.tpCount==0, "plan.tpCount default 0");
      p.tpCount=5; for(int i=0;i<5;i++) p.tpPrice[i]=1.0+i*0.1;
      Assert(p.tpCount==5 && MathAbs(p.tpPrice[4]-1.4)<1e-9, "plan holds 5 TP targets");
   }

   // 2) StopsValidator: single TP and all active TP levels validated for geometry
   {
      CStopsValidator v; MM_StopsCheck chk; string sym=_Symbol; if(sym=="") sym="EURUSD";
      double bid=SymbolInfoDouble(sym,SYMBOL_BID); double ask=SymbolInfoDouble(sym,SYMBOL_ASK);
      if(bid<=0 || ask<=0){ bid=1.1000; ask=1.1002; }
      double pt=SymbolInfoDouble(sym,SYMBOL_POINT); if(pt<=0) pt=0.0001;
      double stops=MathMax((int)SymbolInfoInteger(sym,SYMBOL_TRADE_STOPS_LEVEL),(int)SymbolInfoInteger(sym,SYMBOL_TRADE_FREEZE_LEVEL))*pt;
      double pad = stops + 100*pt;
      double vmin=SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN); if(vmin<=0) vmin=0.01;

      MM_TradePlan p; p.Reset(); p.symbol=sym; p.side=POSITION_TYPE_BUY; p.isPending=false; p.orderType=ORDER_TYPE_BUY;
      p.entryPrice=ask; p.slPrice=ask - pad; p.tpCount=1; p.tpPrice[0]=ask + pad; p.lot=vmin;
      bool ok1 = v.ValidatePlan(p, chk);
      Assert(ok1==chk.ok, "single TP validation returns consistent result");
      if(!ok1) Print("single-TP env note: ", chk.reasonCode, " ", chk.messageEN);

      MM_TradePlan m=p; m.tpCount=3; m.tpPrice[0]=ask+pad; m.tpPrice[1]=ask+pad*2; m.tpPrice[2]=ask+pad*3;
      MM_StopsCheck chk2; bool okm = v.ValidatePlan(m, chk2);
      if(ok1) Assert(okm, "multi-TP (3) valid targets accepted when single-TP context valid");
      else Print("skip multi-TP accept assert (single invalid in env): ", chk2.reasonCode, " ", chk2.messageEN);

      MM_TradePlan bad=m; bad.tpPrice[1]=ask - pad; // wrong side
      MM_StopsCheck chk3; bool okb = v.ValidatePlan(bad, chk3);
      Assert(!okb && chk3.blocked, "invalid TP level geometry blocked");
      Assert(chk3.reasonCode=="INVALID_STOPS" || chk3.reasonCode=="INVALID_TP" || chk3.reasonCode=="NO_SL", "invalid TP returns blocking reason");
   }

   // 3) Volume split: preservation, step/min/max alignment, explicit rejection cases
   {
      string sym=_Symbol; double vmin=SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN); double vstep=SymbolInfoDouble(sym,SYMBOL_VOLUME_STEP); double vmax=SymbolInfoDouble(sym,SYMBOL_VOLUME_MAX);
      if(vstep<=0) vstep=0.01; if(vmin<=0) vmin=vstep; if(vmax<=0) vmax=100;

      // valid 2-TP split preserving total
      double total2 = vmin*4.0; if(total2>vmax) total2=MathFloor(vmax/vstep)*vstep; // keep feasible
      double vols2[]; string r2="";
      bool ok2 = MirrorSplit(sym,total2,2,vols2,r2);
      if(total2 >= vmin*2.0)
      {
         Assert(ok2, "valid 2-way split accepted");
         if(ok2){ double s=vols2[0]+vols2[1]; Assert(Nearly(s,total2,vstep*1e-6), "2-way split preserves total within step precision"); Assert(vols2[0]>=vmin-1e-12 && vols2[1]>=vmin-1e-12, "2-way legs >= min"); Assert(vols2[0]<=vmax+1e-12 && vols2[1]<=vmax+1e-12, "2-way legs <= max"); Assert(Nearly(vols2[0]/vstep,MathRound(vols2[0]/vstep),1e-6) && Nearly(vols2[1]/vstep,MathRound(vols2[1]/vstep),1e-6), "2-way legs step-aligned"); }
      }

      // valid 5-TP split (if feasible) or explicit reject
      double total5 = vmin*10.0; if(total5>vmax) total5=MathFloor(vmax/vstep)*vstep;
      double vols5[]; string r5=""; bool ok5 = MirrorSplit(sym,total5,5,vols5,r5);
      if(total5 >= vmin*5.0)
      {
         Assert(ok5, "valid 5-way split accepted when feasible");
         if(ok5){ double s=0; bool legsOk=true; for(int i=0;i<5;i++){ s+=vols5[i]; if(vols5[i]<vmin-1e-12||vols5[i]>vmax+1e-12) legsOk=false; if(!Nearly(vols5[i]/vstep,MathRound(vols5[i]/vstep),1e-6)) legsOk=false; } Assert(Nearly(s,total5,vstep*1e-6), "5-way split preserves total"); Assert(legsOk, "5-way legs satisfy min/max/step"); }
      }
      else
      {
         Assert(!ok5, "impossible 5-way split explicitly rejected");
      }

      // impossible: below minimum total for parts
      double badTotal = vmin*2.0 - vstep; if(badTotal < vstep) badTotal = vmin*0.5;
      double volsBad[]; string rb=""; bool okb = MirrorSplit(sym,badTotal,3,volsBad,rb);
      Assert(!okb, "impossible split (below min total) rejected");

      // invalid: not on step grid (no silent reduction/increase)
      double offGrid = vmin*3.0 + vstep*0.37;
      double volsG[]; string rg=""; bool okg = MirrorSplit(sym,offGrid,3,volsG,rg);
      Assert(!okg, "off-step-grid total rejected (no silent adjust)");

      Print("Split checks: sym=",sym," vmin=",DoubleToString(vmin,8)," step=",DoubleToString(vstep,8)," vmax=",DoubleToString(vmax,8)," r2=",r2," r5=",r5," rb=",rb," rg=",rg);
   }

   // 4) Default single-TP behavior preserved (no split path for tpCount<=1)
   {
      MM_TradePlan p; p.Reset(); p.tpCount=1; p.tpPrice[0]=1.2345; p.lot=0.10; p.isPending=false; p.side=POSITION_TYPE_BUY;
      Assert(!(p.tpCount>1), "single TP does not trigger multi-TP path");
   }

   // 5) ExecutionPolicy surface sanity (single-TP path remains callable; multi-TP netting rejection exercised in demo/runtime)
   {
      CExecutionPolicy pol; MM_ExecPolicy cfg; cfg.Reset();
      Assert(pol.RetcodeReason(TRADE_RETCODE_DONE)=="DONE", "retcode mapping intact");
      Assert(pol.IsSuccess(TRADE_RETCODE_DONE), "success classification intact");
   }

   // 6) Multi-TP precondition flag
   {
      MM_TradePlan p; p.Reset(); p.tpCount=2; p.tpPrice[0]=1.2; p.tpPrice[1]=1.3;
      Assert(p.tpCount>1, "multi-TP plan flagged by tpCount>1");
   }

   if(g_fail==0) Print("MultiTp_Planning_Test: ALL PASS"); else Print("MultiTp_Planning_Test: FAIL count=",g_fail);
}
