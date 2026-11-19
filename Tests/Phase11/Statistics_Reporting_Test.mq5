//+------------------------------------------------------------------+
//|                                   Statistics_Reporting_Test.mq5  |
//|  Phase 11: Statistics/Reporting (focused, no broker dependency)  |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "..\\..\\Include\\Core\\Contracts.mqh"
#include "..\\..\\Include\\Statistics\\Statistics.mqh"

int g_fail=0;
void Assert(bool c,const string n){ if(!c){ Print("FAIL: ",n); g_fail++; } else Print("OK: ",n); }
bool Nearly(double a,double b,double eps=1e-6){ return MathAbs(a-b)<=eps; }

MM_TradeEvent MkOpen(long posId, ulong ticket, string sym, ENUM_POSITION_TYPE side, double vol, double price, double sl, datetime t, ENUM_MM_ACCOUNT_MODE mode)
{
   MM_TradeEvent e; e.Reset(); e.type=MM_EVENT_OPEN; e.positionId=posId; e.ticket=ticket; e.order=ticket;
   e.symbol=sym; e.side=side; e.volume=vol; e.price=price; e.sl=sl; e.timeServer=t; e.timeLocal=t; e.reasonCode="OPEN";
   // mode is set on statistics via SetAccountMode/RegisterPlannedRisk context
   return e;
}
MM_TradeEvent MkPartial(long posId, ulong ticket, string sym, double vol, double price, double profit, double comm, double swap, datetime t, string reason="PARTIAL_CLOSE")
{
   MM_TradeEvent e; e.Reset(); e.type=MM_EVENT_PARTIAL_FILL; e.positionId=posId; e.ticket=ticket; e.order=ticket;
   e.symbol=sym; e.volume=vol; e.price=price; e.profit=profit; e.commission=comm; e.swap=swap; e.timeServer=t; e.timeLocal=t; e.reasonCode=reason; e.reason=reason;
   return e;
}
MM_TradeEvent MkClose(long posId, ulong ticket, string sym, double vol, double price, double profit, double comm, double swap, datetime t)
{
   MM_TradeEvent e; e.Reset(); e.type=MM_EVENT_CLOSE; e.positionId=posId; e.ticket=ticket; e.order=ticket;
   e.symbol=sym; e.volume=vol; e.price=price; e.profit=profit; e.commission=comm; e.swap=swap; e.timeServer=t; e.timeLocal=t; e.reasonCode="CLOSE";
   return e;
}

void OnStart()
{
   g_fail=0;

   // 1) Aggregated partial closes: commission/swap included, R based on initial lifecycle risk (not reduced), duration lifecycle-wide
   {
      CStatistics st; st.Init("mm_test_stats.csv"); st.SetLiveSync(false);
      st.SetAccountMode(ACCOUNT_PERSONAL);
      datetime t0 = (datetime)1700000000;
      st.RegisterPlannedRisk("EURUSD", 100.0, ACCOUNT_PERSONAL);
      st.OnTradeEvent(MkOpen(1001, 2001, "EURUSD", POSITION_TYPE_BUY, 1.0, 1.1000, 1.0900, t0, ACCOUNT_PERSONAL));
      // partial 0.5 lot: +40 profit, -2 comm, -1 swap
      st.OnTradeEvent(MkPartial(1001, 2001, "EURUSD", 0.5, 1.1010, 40.0, -2.0, -1.0, t0+600, "PARTIAL_CLOSE"));
      // final close remaining 0.5: +30 profit, -1 comm, 0 swap
      st.OnTradeEvent(MkClose(1001, 2001, "EURUSD", 0.5, 1.1020, 30.0, -1.0, 0.0, t0+1200));

      MM_Kpi k; st.GetKpi(k);
      Assert(k.trades==1, "aggregated partial+close counted as one completed trade");
      double expectedNet = (40.0-2.0-1.0) + (30.0-1.0); // 66
      Assert(Nearly(k.netProfit, expectedNet, 1e-6), "net includes profit+commission+swap across partials");
      Assert(Nearly(k.expectancy, expectedNet, 1e-6), "expectancy equals net for single trade");
      Assert(Nearly(k.avgR, expectedNet/100.0, 1e-6), "R uses initial lifecycle risk baseline (not reduced by partial)");
      Assert(k.avgDurationMin > 19.9 && k.avgDurationMin < 20.1, "duration spans full lifecycle (20 min)");
      Assert(st.ClosedCount()==1, "single closed record for aggregated lifecycle");
   }

   // 2) Netting-style INOUT partial event aggregation (same accounting path) and win/loss/PF
   {
      CStatistics st; st.Init("mm_test_stats2.csv"); st.SetLiveSync(false);
      st.SetAccountMode(ACCOUNT_PERSONAL);
      datetime t0 = (datetime)1700100000;
      st.RegisterPlannedRisk("EURUSD", 50.0, ACCOUNT_PERSONAL);
      st.OnTradeEvent(MkOpen(2002, 3002, "EURUSD", POSITION_TYPE_SELL, 1.0, 1.1000, 1.1050, t0, ACCOUNT_PERSONAL));
      st.OnTradeEvent(MkPartial(2002, 3002, "EURUSD", 0.4, 1.0980, 20.0, -0.5, 0.0, t0+300, "INOUT"));
      st.OnTradeEvent(MkClose(2002, 3002, "EURUSD", 0.6, 1.0970, 30.0, -0.5, -0.2, t0+900));
      MM_Kpi k; st.GetKpi(k);
      double net = (20.0-0.5) + (30.0-0.5-0.2); // 48.8
      Assert(k.trades==1 && Nearly(k.netProfit, net, 1e-6), "INOUT partial aggregated consistently with realized costs");
      Assert(k.wins==1 && k.grossProfit>0 && Nearly(k.avgR, net/50.0, 1e-6), "R/net correct for aggregated netting-style lifecycle");
   }

   // 3) Mode filtering and per-mode/all views (reporting clarity)
   {
      CStatistics st; st.Init("mm_test_stats3.csv"); st.SetLiveSync(false);
      datetime t0 = (datetime)1700200000;
      st.SetAccountMode(ACCOUNT_PERSONAL);
      st.RegisterPlannedRisk("EURUSD", 100.0, ACCOUNT_PERSONAL);
      st.OnTradeEvent(MkOpen(3001,4001,"EURUSD",POSITION_TYPE_BUY,1.0,1.1,1.09,t0,ACCOUNT_PERSONAL));
      st.OnTradeEvent(MkClose(3001,4001,"EURUSD",1.0,1.11,50.0,-1.0,0.0,t0+600));

      st.SetAccountMode(ACCOUNT_PROP);
      st.RegisterPlannedRisk("EURUSD", 100.0, ACCOUNT_PROP);
      st.OnTradeEvent(MkOpen(3002,4002,"EURUSD",POSITION_TYPE_BUY,1.0,1.1,1.09,t0+1200,ACCOUNT_PROP));
      st.OnTradeEvent(MkClose(3002,4002,"EURUSD",1.0,1.095,-30.0,-1.0,0.0,t0+1800));

      MM_Kpi allk, pk, propk;
      st.GetKpi(allk);
      st.GetKpiForMode(ACCOUNT_PERSONAL, pk);
      st.GetKpiForMode(ACCOUNT_PROP, propk);
      Assert(allk.trades==2, "all-mode includes both trades");
      Assert(pk.trades==1 && Nearly(pk.netProfit,49.0,1e-6), "personal-mode KPI filtered");
      Assert(propk.trades==1 && Nearly(propk.netProfit,-31.0,1e-6), "prop-mode KPI filtered");
      Assert(allk.wins==1 && allk.losses==1 && allk.grossProfit>0 && allk.grossLoss>0, "PF/win-loss computed from net across modes");
   }

   // 4) CSV export schema stable + additive net column, data non-blocking
   {
      CStatistics st; st.Init("mm_test_stats4.csv"); st.SetLiveSync(false);
      st.SetAccountMode(ACCOUNT_PERSONAL);
      datetime t0 = (datetime)1700300000;
      st.RegisterPlannedRisk("EURUSD", 100.0, ACCOUNT_PERSONAL);
      st.OnTradeEvent(MkOpen(5001,6001,"EURUSD",POSITION_TYPE_BUY,1.0,1.1000,1.0900,t0,ACCOUNT_PERSONAL));
      st.OnTradeEvent(MkClose(5001,6001,"EURUSD",1.0,1.1050,25.0,-2.0,-0.5,t0+600));
      bool ok = st.ExportCSV("mm_test_phase11_export.csv", ACCOUNT_PERSONAL, false);
      Assert(ok, "CSV export succeeds");
      // verify header/content presence (file in Common files)
      int h = FileOpen("mm_test_phase11_export.csv", FILE_READ|FILE_CSV|FILE_COMMON|FILE_ANSI, ',');
      Assert(h!=INVALID_HANDLE, "exported CSV readable");
      if(h!=INVALID_HANDLE)
      {
         string c1=FileReadString(h); string c2=FileReadString(h); string c3=FileReadString(h);
         // read rest of header row to reach last column name 'net' and first data row values loosely
         string header = c1+","+c2+","+c3; // partial; just sanity
         Assert(StringFind(c1,"ticket")>=0 || StringFind(header,"ticket")>=0, "CSV header starts with ticket");
         // scan for 'net' token in header by reading line-wise fallback
         FileClose(h);
         int ht = FileOpen("mm_test_phase11_export.csv", FILE_READ|FILE_TXT|FILE_COMMON|FILE_ANSI|FILE_SHARE_READ);
         if(ht!=INVALID_HANDLE){ string line=FileReadString(ht); FileClose(ht); Assert(StringFind(line,",net")>=0 || StringFind(line,"net")>=0, "CSV schema includes additive net column"); }
      }
   }

   // 5) Incomplete/orphan data remains non-blocking (limitation explicitly tolerated)
   {
      CStatistics st; st.Init(); st.SetLiveSync(false);
      st.SetAccountMode(ACCOUNT_PERSONAL);
      datetime t0=(datetime)1700400000;
      MM_TradeEvent part=MkPartial(9999,9999,"EURUSD",0.2,1.1,5.0,-0.1,0.0,t0,"PARTIAL_CLOSE");
      st.OnTradeEvent(part); // orphan partial
      MM_Kpi k; st.GetKpi(k);
      Assert(k.trades==1, "orphan partial recorded without blocking");
      Assert(k.avgR==0.0, "orphan partial R unknown -> 0 (limitation, non-blocking)");
   }

   if(g_fail==0) Print("Statistics_Reporting_Test: ALL PASS"); else Print("Statistics_Reporting_Test: FAIL count=",g_fail);
}
