//+------------------------------------------------------------------+
//|                                      TradeAggregation_Test.mq5   |
//|  Phase 2.3: completed-trade aggregation & lifecycle correctness  |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "..\\..\\Include\\Protection\\Protection.mqh"

int g_fail=0;
void Assert(bool c,const string n){ if(!c){Print("FAIL: ",n); g_fail++;} else Print("OK: ",n); }

// Mirrors EA aggregation rules:
// net component = profit + commission + swap + fee per deal, included exactly once (deal-id dedupe).
// Directional lifecycle aggregates IN/OUT/position-linked adjustments; finalizes once on full close.
// Netting reversal (INOUT, position remains open, POSITION_IDENTIFIER preserved): finalize previous lifecycle
// with full INOUT deal financials attributed conservatively to closed portion (no separable split invented),
// start new logical lifecycle for opposite exposure with no carryover; exposure/trade counted once.
// Partial closes do not finalize. Hedging/out-of-band separate deals remain per-position when posId distinct.
struct TTrack
{
   long   positionId;
   double net;
   bool   finalized;
   void Reset(){ positionId=0; net=0; finalized=false; }
};

bool Seen(ulong &seen[], int seenCount, ulong id){ for(int i=0;i<seenCount;i++) if(seen[i]==id) return true; return false; }
double DealNet(double profit,double comm,double swap,double fee){ return profit+comm+swap+fee; }

int FindActive(TTrack &t[], int count, long posId){ for(int i=0;i<count;i++) if(t[i].positionId==posId && !t[i].finalized) return i; return -1; }
int AllocOrReuse(TTrack &t[], int count, long posId)
{
   int idx=FindActive(t,count,posId); if(idx>=0) return idx;
   for(int i=0;i<count;i++) if(t[i].positionId==0 || t[i].finalized){ t[i].Reset(); t[i].positionId=posId; return i; }
   return -1;
}

void OnStart()
{
   g_fail=0;

   // 1) Non-reversal partial close regression: entry+partials aggregate, exactly one finalize with DEAL_FEE included once
   {
      TTrack tr[4]; for(int i=0;i<4;i++) tr[i].Reset();
      int finalizeCount=0; CProtection p; p.Init();
      datetime base=TimeTradeServer(); if(base==0) base=TimeCurrent(); p.SyncPeriods(base);
      long pos=100; int ti=AllocOrReuse(tr,4,pos);
      tr[ti].net += DealNet(0.0,-2.0,0.0,-0.4); // DEAL_ENTRY_IN incl fee/commission
      // partial close 1 (still open)
      tr[ti].net += DealNet(4.0,-0.5,0.0,-0.1);
      bool stillOpen=true;
      if(!stillOpen && !tr[ti].finalized){ p.RecordCompletedTrade(tr[ti].net); tr[ti].finalized=true; finalizeCount++; }
      Assert(finalizeCount==0 && MathAbs(p.DailyProfit())<1e-9 && MathAbs(p.DailyLoss())<1e-9, "partial close does not finalize/account");
      // partial close 2 (still open)
      tr[ti].net += DealNet(3.0,-0.5,-0.2,-0.1);
      if(!stillOpen && !tr[ti].finalized){ p.RecordCompletedTrade(tr[ti].net); tr[ti].finalized=true; finalizeCount++; }
      Assert(finalizeCount==0, "second partial close does not finalize");
      // final close
      tr[ti].net += DealNet(-1.0,-0.5,-0.1,-0.2);
      stillOpen=false;
      if(!stillOpen && !tr[ti].finalized){ p.RecordCompletedTrade(tr[ti].net); tr[ti].finalized=true; finalizeCount++; }
      if(!stillOpen && !tr[ti].finalized){ p.RecordCompletedTrade(tr[ti].net); tr[ti].finalized=true; finalizeCount++; } // dup-safe
      double expected = DealNet(0,-2,-0,-0.4)+DealNet(4,-0.5,0,-0.1)+DealNet(3,-0.5,-0.2,-0.1)+DealNet(-1,-0.5,-0.1,-0.2);
      Assert(finalizeCount==1, "non-reversal partial closes: exactly one finalize");
      Assert(MathAbs(tr[ti].net - expected) < 1e-9, "non-reversal lifecycle aggregates all components incl fees once");
      Assert(MathAbs(p.DailyProfit() - expected) < 1e-6, "single completed-trade accounting update");
   }

   // 2) DEAL_FEE inclusion without double-counting (fee on deal fields and/or separate position-linked adjustment before finalize)
   {
      TTrack tr[4]; for(int i=0;i<4;i++) tr[i].Reset();
      CProtection p; p.Init(); long pos=200; int ti=AllocOrReuse(tr,4,pos);
      tr[ti].net += DealNet(0.0,-1.0,0.0,-0.2); // entry
      tr[ti].net += DealNet(5.0,-1.0,-0.3,-0.1); // exit deal carries fee
      tr[ti].net += DealNet(0.0,0.0,0.0,-0.4);   // separately posted position-linked fee/adjustment (pre-finalize)
      // duplicate same adjustment deal must not apply twice (deal-id dedupe concept)
      ulong seen[4]; ArrayInitialize(seen,0); int sc=0; ulong adj=9001;
      if(!Seen(seen,sc,adj)){ /* already applied above */ seen[sc++]=adj; }
      if(!Seen(seen,sc,adj)){ tr[ti].net += DealNet(0,0,0,-0.4); seen[sc++]=adj; }
      bool stillOpen=false; int fin=0;
      if(!stillOpen && !tr[ti].finalized){ p.RecordCompletedTrade(tr[ti].net); tr[ti].finalized=true; fin++; }
      double expected = DealNet(0,-1,0,-0.2)+DealNet(5,-1,-0.3,-0.1)+DealNet(0,0,0,-0.4);
      Assert(fin==1, "fee scenario single finalize");
      Assert(MathAbs(tr[ti].net - expected) < 1e-9, "DEAL_FEE included once without double-counting");
      Assert(MathAbs(p.DailyProfit() - expected) < 1e-6, "fee-inclusive net accounted once");
   }

   // 3) Netting BUY -> SELL reversal (POSITION_IDENTIFIER preserved): close BUY lifecycle (loss), open SELL lifecycle, independent streak updates
   {
      TTrack tr[4]; for(int i=0;i<4;i++) tr[i].Reset();
      CProtection p; p.Init(); datetime base=TimeTradeServer(); if(base==0) base=TimeCurrent(); p.SyncPeriods(base);
      long posId=300; // preserved identifier
      // BUY opened
      int b=AllocOrReuse(tr,4,posId);
      tr[b].net += DealNet(0.0,-1.0,0.0,-0.2); // BUY entry (commission+fee)
      p.RegisterExposureOrder(1001,0);
      // Reversal deal INOUT while position remains open (now SELL): profit realized for closed BUY; comm/swap/fee attributed conservatively to closed lifecycle
      tr[b].net += DealNet(-10.0,-1.0,-0.3,-0.1); // reversal financials
      bool stillOpen=true; int fin=0;
      if(stillOpen)
      {
         p.RecordCompletedTrade(tr[b].net); if(tr[b].net<0) p.ApplyConsecLossPolicy(3,30,base); else p.UpdateCooldown(base);
         tr[b].finalized=true; fin++;
         int s=AllocOrReuse(tr,4,posId); // new logical lifecycle, same identifier
         tr[s].net=0.0; tr[s].finalized=false;
         p.RegisterExposureOrder(1002,0);
         // SELL later closed at profit
         tr[s].net += DealNet(6.0,-0.8,-0.2,-0.1);
         stillOpen=false;
         if(!stillOpen && !tr[s].finalized){ p.RecordCompletedTrade(tr[s].net); if(tr[s].net<0) p.ApplyConsecLossPolicy(3,30,base); else p.UpdateCooldown(base); tr[s].finalized=true; fin++; }
      }
      double buyNet  = DealNet(0,-1,0,-0.2)+DealNet(-10,-1,-0.3,-0.1); // -12.6
      double sellNet = DealNet(6,-0.8,-0.2,-0.1);                        // 4.9
      Assert(fin==2, "BUY->SELL reversal produces two independent completed lifecycles");
      Assert(FindActive(tr,4,posId)==-1, "no active lifecycle after full close of reversal-opened position");
      Assert(p.ConsecutiveLosses()==0, "independent streaks: loss then win resets streak");
      Assert(MathAbs((p.DailyProfit()+0.0) - (sellNet)) < 1e-6 && MathAbs(p.DailyLoss() - MathAbs(buyNet)) < 1e-6, "BUY loss and SELL win accounted independently with reversal fees");
   }

   // 4) Netting SELL -> BUY reversal
   {
      TTrack tr[4]; for(int i=0;i<4;i++) tr[i].Reset();
      CProtection p; p.Init(); datetime base=TimeTradeServer(); if(base==0) base=TimeCurrent(); p.SyncPeriods(base);
      long posId=400;
      int s=AllocOrReuse(tr,4,posId);
      tr[s].net += DealNet(0.0,-1.0,0.0,-0.2); // SELL entry
      p.RegisterExposureOrder(2001,0);
      tr[s].net += DealNet(8.0,-1.0,-0.1,-0.1); // reversal closes SELL in profit, opens BUY
      bool stillOpen=true; int fin=0;
      if(stillOpen)
      {
         p.RecordCompletedTrade(tr[s].net); if(tr[s].net<0) p.ApplyConsecLossPolicy(3,30,base); else p.UpdateCooldown(base);
         tr[s].finalized=true; fin++;
         int b=AllocOrReuse(tr,4,posId);
         tr[b].net=0.0; tr[b].finalized=false;
         p.RegisterExposureOrder(2002,0);
         tr[b].net += DealNet(-5.0,-0.7,-0.2,-0.1); // BUY closed in loss
         stillOpen=false;
         if(!stillOpen && !tr[b].finalized){ p.RecordCompletedTrade(tr[b].net); if(tr[b].net<0) p.ApplyConsecLossPolicy(3,30,base); else p.UpdateCooldown(base); tr[b].finalized=true; fin++; }
      }
      double sellNet = DealNet(0,-1,0,-0.2)+DealNet(8,-1,-0.1,-0.1); // 5.6
      double buyNet  = DealNet(-5,-0.7,-0.2,-0.1);                    // -6.0
      Assert(fin==2, "SELL->BUY reversal produces two independent completed lifecycles");
      Assert(p.ConsecutiveLosses()==1, "independent streaks: win then loss yields 1 loss");
      Assert(MathAbs(p.DailyProfit() - sellNet) < 1e-6 && MathAbs(p.DailyLoss() - MathAbs(buyNet)) < 1e-6, "SELL win and BUY loss accounted independently");
   }

   // 5) Reversal with partial execution-like sequence: partial close (no finalize) then reversal INOUT finalizes closed lifecycle and opens new
   {
      TTrack tr[4]; for(int i=0;i<4;i++) tr[i].Reset();
      CProtection p; p.Init(); datetime base=TimeTradeServer(); if(base==0) base=TimeCurrent(); p.SyncPeriods(base);
      long posId=500; int fin=0;
      int a=AllocOrReuse(tr,4,posId);
      tr[a].net += DealNet(0,-1,0,0);         // entry
      p.RegisterExposureOrder(3001,0);
      tr[a].net += DealNet(2,-0.2,0,0);       // partial close, still open
      Assert(!tr[a].finalized, "partial before reversal does not finalize");
      tr[a].net += DealNet(-4,-0.3,-0.1,-0.2); // reversal INOUT, still open opposite
   bool stillOpen=true;
   if(stillOpen){ p.RecordCompletedTrade(tr[a].net); tr[a].finalized=true; fin++; int b=AllocOrReuse(tr,4,posId); tr[b].net=0; tr[b].finalized=false; p.RegisterExposureOrder(3002,0); }
   double closedNet = DealNet(0,-1,0,0)+DealNet(2,-0.2,0,0)+DealNet(-4,-0.3,-0.1,-0.2);
   Assert(fin==1, "reversal finalizes previous lifecycle once (incl. prior partial)");
   Assert(MathAbs(p.DailyLoss() - MathAbs(closedNet)) < 1e-6, "partial+reversal costs aggregated into closed lifecycle once");
   Assert(p.TradesToday()==2, "new opposite exposure counted as actual risk-increasing exposure");
   }

   // 6) Exposure dedupe: partial fills of same entry order do not increment more than once
   {
      CProtection p; p.Init();
      bool c1=p.RegisterExposureOrder(4001,5001);
      bool c2=p.RegisterExposureOrder(4001,5002);
      bool c3=p.RegisterExposureOrder(4001,5003);
      Assert(c1 && !c2 && !c3 && p.TradesToday()==1, "partial fills same entry order counted once");
   }

   // 7) Deal-id dedupe prevents double-counting a reversal/adjustment deal
   {
      ulong seen[4]; ArrayInitialize(seen,0); int sc=0; double net=0; ulong d=7001; double dn=DealNet(-3,-1,-0.1,-0.2);
      if(!Seen(seen,sc,d)){ net+=dn; seen[sc++]=d; }
      if(!Seen(seen,sc,d)){ net+=dn; seen[sc++]=d; }
      Assert(MathAbs(net-dn)<1e-9, "duplicate deal not double-counted");
   }

   if(g_fail==0) Print("TradeAggregation_Test: ALL PASS"); else Print("TradeAggregation_Test: FAIL count=",g_fail);
}
