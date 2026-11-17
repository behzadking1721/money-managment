//+------------------------------------------------------------------+
//|                                              TradeLifecycle.mqh  |
//|         OnTradeTransaction -> TradeEvent dispatch + reject sink  |
//+------------------------------------------------------------------+
#ifndef MM_TRADE_LIFECYCLE_MQH
#define MM_TRADE_LIFECYCLE_MQH

#include "../Core/Contracts.mqh"

#define MM_MAX_LISTENERS 16
#define MM_MAX_REJECT_LOG 64

struct MM_RejectRecord
{
   datetime timeServer;
   string   symbol;
   string   guardId;
   string   reasonCode;
   string   messageEN;
   uint     retcode;
   string   context;
};

class CTradeLifecycle
{
private:
   ITradeEventListener* m_listeners[MM_MAX_LISTENERS];
   int                  m_listenerCount;
   MM_RejectRecord      m_rejects[MM_MAX_REJECT_LOG];
   int                  m_rejectCount;
   int                  m_rejectHead;

   void PushReject(const MM_RejectRecord &r)
   {
      int idx = m_rejectCount < MM_MAX_REJECT_LOG ? m_rejectCount++ : m_rejectHead;
      m_rejects[idx]=r;
      if(m_rejectCount>=MM_MAX_REJECT_LOG) m_rejectHead=(m_rejectHead+1)%MM_MAX_REJECT_LOG;
   }

public:
   CTradeLifecycle(){ m_listenerCount=0; m_rejectCount=0; m_rejectHead=0; }

   bool AddListener(ITradeEventListener *l)
   {
      if(l==NULL || m_listenerCount>=MM_MAX_LISTENERS) return false;
      m_listeners[m_listenerCount++]=l; return true;
   }

   void Dispatch(const MM_TradeEvent &ev)
   {
      for(int i=0;i<m_listenerCount;i++) if(m_listeners[i]!=NULL) m_listeners[i].OnTradeEvent(ev);
   }

   void RecordReject(const string symbol,const string guardId,const string reasonCode,const string messageEN,uint retcode,const string context)
   {
      MM_RejectRecord r; r.timeServer=TimeTradeServer(); if(r.timeServer==0) r.timeServer=TimeCurrent();
      r.symbol=symbol; r.guardId=guardId; r.reasonCode=reasonCode; r.messageEN=messageEN; r.retcode=retcode; r.context=context;
      PushReject(r);
      MM_TradeEvent ev; ev.Reset(); ev.type=MM_EVENT_REJECT; ev.symbol=symbol; ev.timeServer=r.timeServer; ev.timeLocal=TimeLocal(); ev.retcode=retcode; ev.reasonCode=reasonCode; ev.reason=messageEN;
      Dispatch(ev);
   }

   // Unified sink for guard decisions (Phase 3+); records BLOCK/WARN and emits REJECT for BLOCK.
   void RecordGuardReject(const MM_GuardResult &gr,const string symbol)
   {
      MM_RejectRecord r; r.timeServer=TimeTradeServer(); if(r.timeServer==0) r.timeServer=TimeCurrent();
      r.symbol=symbol; r.guardId=gr.guardId; r.reasonCode=gr.reasonCode; r.messageEN=gr.messageEN; r.retcode=0; r.context=gr.context;
      PushReject(r);
      if(gr.decision==GUARD_BLOCK)
      {
         MM_TradeEvent ev; ev.Reset(); ev.type=MM_EVENT_REJECT; ev.symbol=symbol; ev.timeServer=r.timeServer; ev.timeLocal=TimeLocal();
         ev.retcode=0; ev.reasonCode=gr.reasonCode; ev.reason=gr.messageEN;
         Dispatch(ev);
      }
   }

   int RejectCount(){ return m_rejectCount; }
   bool GetReject(int index, MM_RejectRecord &out)
   {
      if(index<0 || index>=m_rejectCount) return false;
      int idx = m_rejectCount < MM_MAX_REJECT_LOG ? index : (m_rejectHead+index)%MM_MAX_REJECT_LOG;
      out=m_rejects[idx]; return true;
   }

   // Normalize OnTradeTransaction into TradeEvent(s)
   void OnTradeTransaction(const MqlTradeTransaction &trans,
                           const MqlTradeRequest &request,
                           const MqlTradeResult &result)
   {
      datetime srv=TimeTradeServer(); if(srv==0) srv=TimeCurrent();

      if(trans.type==TRADE_TRANSACTION_DEAL_ADD)
      {
         if(!HistoryDealSelect(trans.deal)) return;
         ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
         MM_TradeEvent ev; ev.Reset();
         ev.deal=trans.deal; ev.order=trans.order; ev.positionId=trans.position;
         ev.symbol=trans.symbol; ev.volume=HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
         ev.price=HistoryDealGetDouble(trans.deal, DEAL_PRICE);
         ev.profit=HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
         ev.commission=HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
         ev.swap=HistoryDealGetDouble(trans.deal, DEAL_SWAP);
         ev.timeServer=(datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);
         ev.timeLocal=TimeLocal();
         ENUM_DEAL_TYPE dt=(ENUM_DEAL_TYPE)HistoryDealGetInteger(trans.deal, DEAL_TYPE);
         ev.side = (dt==DEAL_TYPE_BUY)?POSITION_TYPE_BUY:POSITION_TYPE_SELL;
         if(entry==DEAL_ENTRY_IN) ev.type=MM_EVENT_OPEN;
         else if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_INOUT) ev.type=MM_EVENT_CLOSE;
         else ev.type=MM_EVENT_DEAL_ADD;
         Dispatch(ev);
      }
      else if(trans.type==TRADE_TRANSACTION_REQUEST)
      {
         // request result; record failures
         if(result.retcode!=TRADE_RETCODE_DONE && result.retcode!=TRADE_RETCODE_DONE_PARTIAL && result.retcode!=TRADE_RETCODE_PLACED && result.retcode!=0)
         {
            RecordReject(request.symbol,"Execution","EXEC_RETCODE",result.comment,result.retcode,"req");
         }
         if(result.retcode==TRADE_RETCODE_DONE_PARTIAL)
         {
            MM_TradeEvent ev; ev.Reset(); ev.type=MM_EVENT_PARTIAL_FILL; ev.symbol=request.symbol;
            ev.volume=result.volume; ev.price=result.price; ev.timeServer=srv; ev.timeLocal=TimeLocal();
            ev.retcode=result.retcode; ev.reason="partial_fill";
            Dispatch(ev);
         }
      }
      else if(trans.type==TRADE_TRANSACTION_ORDER_ADD || trans.type==TRADE_TRANSACTION_ORDER_UPDATE)
      {
         if(HistoryOrderSelect(trans.order))
         {
            if(trans.type==TRADE_TRANSACTION_ORDER_UPDATE)
            {
               MM_TradeEvent ev; ev.Reset(); ev.type=MM_EVENT_MODIFY; ev.order=trans.order; ev.symbol=trans.symbol;
               ev.price=HistoryOrderGetDouble(trans.order, ORDER_PRICE_OPEN);
               ev.sl=HistoryOrderGetDouble(trans.order, ORDER_SL);
               ev.tp=HistoryOrderGetDouble(trans.order, ORDER_TP);
               ev.volume=HistoryOrderGetDouble(trans.order, ORDER_VOLUME_INITIAL);
               ev.timeServer=srv; ev.timeLocal=TimeLocal();
               Dispatch(ev);
            }
         }
         else if(trans.type==TRADE_TRANSACTION_ORDER_UPDATE)
         {
            // fallback when history not yet available
            MM_TradeEvent ev; ev.Reset(); ev.type=MM_EVENT_MODIFY; ev.order=trans.order; ev.symbol=trans.symbol;
            ev.price=trans.price; ev.volume=trans.volume; ev.timeServer=srv; ev.timeLocal=TimeLocal();
            Dispatch(ev);
         }
      }
      else if(trans.type==TRADE_TRANSACTION_POSITION)
      {
         // position changed (SL/TP/volume)
         MM_TradeEvent ev; ev.Reset(); ev.type=MM_EVENT_MODIFY; ev.symbol=trans.symbol;
         ev.volume=trans.volume; ev.price=trans.price; ev.timeServer=srv; ev.timeLocal=TimeLocal();
         Dispatch(ev);
      }
   }
};

#endif // MM_TRADE_LIFECYCLE_MQH
