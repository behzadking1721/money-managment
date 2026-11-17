//+------------------------------------------------------------------+
//|                                          Lifecycle_Map_Test.mq5  |
//|          Transaction/result -> TradeEvent mapping (Phase 1)      |
//+------------------------------------------------------------------+
#property script_show_inputs
#include "..\\..\\Include\\Trade\\TradeLifecycle.mqh"

int g_fail=0; int g_events=0; MM_TradeEvent g_last; bool g_gotReject=false;
void Assert(bool cond,const string name){ if(!cond){ Print("FAIL: ",name); g_fail++; } else Print("OK: ",name); }

class CRecListener : public ITradeEventListener
{
public:
   virtual void OnTradeEvent(const MM_TradeEvent &event){ g_events++; g_last=event; if(event.type==MM_EVENT_REJECT) g_gotReject=true; }
};

void OnStart()
{
   g_fail=0; g_events=0; g_gotReject=false;
   CTradeLifecycle lc; CRecListener rec; lc.AddListener(&rec);

   // request failure -> reject + dispatch
   MqlTradeTransaction tr; ZeroMemory(tr); tr.type=TRADE_TRANSACTION_REQUEST; tr.symbol=_Symbol;
   MqlTradeRequest req; ZeroMemory(req); req.symbol=_Symbol;
   MqlTradeResult res; ZeroMemory(res); res.retcode=TRADE_RETCODE_INVALID_STOPS; res.comment="invalid stops";
   lc.OnTradeTransaction(tr,req,res);
   Assert(g_gotReject,"reject on failed retcode");
   Assert(lc.RejectCount()>=1,"reject sink count");

   // partial fill
   g_gotReject=false;
   ZeroMemory(res); res.retcode=TRADE_RETCODE_DONE_PARTIAL; res.volume=0.10; res.price=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   lc.OnTradeTransaction(tr,req,res);
   Assert(g_last.type==MM_EVENT_PARTIAL_FILL,"partial fill event");
   Assert(MathAbs(g_last.volume-0.10)<0.0001,"partial volume");

   // guard reject path (contract: blocks flow to sink)
   MM_GuardResult gr; gr.Reset(); gr.decision=GUARD_BLOCK; gr.guardId="Prop"; gr.reasonCode="DAILY_DD"; gr.messageEN="Daily DD limit"; gr.messageFA="سقف ضرر روزانه";
   int before=lc.RejectCount();
   lc.RecordGuardReject(gr,_Symbol);
   Assert(lc.RejectCount()==before+1,"guard reject recorded");
   Assert(g_last.type==MM_EVENT_REJECT && g_last.reasonCode=="DAILY_DD","guard reject dispatched");

   if(g_fail==0) Print("Lifecycle_Map_Test: ALL PASS (deal-add cases require live/demo transactions)"); else Print("Lifecycle_Map_Test: FAIL count=",g_fail);
}
