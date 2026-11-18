//+------------------------------------------------------------------+
//|                                              TradeLifecycle.mqh  |
//|   OnTradeTransaction -> TradeEvent dispatch + reject sink (Ph7)  |
//+------------------------------------------------------------------+
#ifndef MM_TRADE_LIFECYCLE_MQH
#define MM_TRADE_LIFECYCLE_MQH

#include "../Core/Contracts.mqh"
#include "../Core/Logger.mqh"

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

   bool PositionStillOpen(long positionId, const string symbol)
   {
      if(positionId<=0) return false;
      // hedging/netting: position ticket commonly equals position id
      if(PositionSelectByTicket((ulong)positionId)) return (PositionGetDouble(POSITION_VOLUME)>0.0);
      // netting fallback by symbol
      if(symbol!="" && PositionSelect(symbol))
      {
         if((long)PositionGetInteger(POSITION_IDENTIFIER)==positionId || (long)PositionGetInteger(POSITION_TICKET)==positionId)
            return (PositionGetDouble(POSITION_VOLUME)>0.0);
      }
      return false;
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
      if(reasonCode=="RETCODE_UNKNOWN" || reasonCode=="EXEC_RETCODE")
         g_mmLog.Warn("EXEC_REJECT",symbol+" "+reasonCode+" rc="+(string)retcode+" "+messageEN+" ctx="+context);
      else
         g_mmLog.Error("EXEC_REJECT",symbol+" "+reasonCode+" rc="+(string)retcode+" "+messageEN+" ctx="+context);
      MM_TradeEvent ev; ev.Reset(); ev.type=MM_EVENT_REJECT; ev.symbol=symbol; ev.timeServer=r.timeServer; ev.timeLocal=TimeLocal(); ev.retcode=retcode; ev.reasonCode=reasonCode; ev.reason=messageEN;
      Dispatch(ev);
   }

   void RecordGuardReject(const MM_GuardResult &gr,const string symbol)
   {
      MM_RejectRecord r; r.timeServer=TimeTradeServer(); if(r.timeServer==0) r.timeServer=TimeCurrent();
      r.symbol=symbol; r.guardId=gr.guardId; r.reasonCode=gr.reasonCode; r.messageEN=gr.messageEN; r.retcode=0; r.context=gr.context;
      PushReject(r);
      g_mmLog.Warn("GUARD_REJECT",symbol+" "+gr.guardId+" "+gr.reasonCode+" "+gr.messageEN);
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

   void OnTradeTransaction(const MqlTradeTransaction &trans,
                           const MqlTradeRequest &request,
                           const MqlTradeResult &result)
   {
      datetime srv=TimeTradeServer(); if(srv==0) srv=TimeCurrent();

      if(trans.type==TRADE_TRANSACTION_DEAL_ADD)
      {
         if(!HistoryDealSelect(trans.deal)) return;
         ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
         ENUM_DEAL_TYPE  dt=(ENUM_DEAL_TYPE)HistoryDealGetInteger(trans.deal, DEAL_TYPE);
         if(dt!=DEAL_TYPE_BUY && dt!=DEAL_TYPE_SELL)
         {
            g_mmLog.Info("DEAL_SKIP","Non trade deal type="+(string)dt+" deal="+(string)trans.deal);
            return;
         }
         MM_TradeEvent ev; ev.Reset();
         ev.deal=trans.deal; ev.order=trans.order; ev.positionId=(long)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
         if(ev.positionId==0) ev.positionId=(long)trans.position;
         ev.symbol=trans.symbol; ev.volume=HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
         ev.price=HistoryDealGetDouble(trans.deal, DEAL_PRICE);
         ev.profit=HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
         ev.commission=HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
         ev.swap=HistoryDealGetDouble(trans.deal, DEAL_SWAP);
         ev.timeServer=(datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);
         ev.timeLocal=TimeLocal();
         ev.side = (dt==DEAL_TYPE_BUY)?POSITION_TYPE_BUY:POSITION_TYPE_SELL;
         if(entry==DEAL_ENTRY_IN)
         {
            ev.type=MM_EVENT_OPEN; ev.reasonCode="OPEN";
            Dispatch(ev);
         }
         else if(entry==DEAL_ENTRY_OUT)
         {
            bool stillOpen = PositionStillOpen(ev.positionId, ev.symbol);
            ev.type = stillOpen ? MM_EVENT_PARTIAL_FILL : MM_EVENT_CLOSE;
            ev.reasonCode = stillOpen ? "PARTIAL_CLOSE" : "CLOSE";
            ev.reason = stillOpen ? "partial_close" : "close";
            Dispatch(ev);
         }
         else if(entry==DEAL_ENTRY_INOUT)
         {
            // reversal/netting: treat as close (and possible open component handled by separate deal if present)
            bool stillOpen = PositionStillOpen(ev.positionId, ev.symbol);
            ev.type = stillOpen ? MM_EVENT_PARTIAL_FILL : MM_EVENT_CLOSE;
            ev.reasonCode = "INOUT";
            ev.reason = stillOpen ? "inout_partial" : "inout_close";
            Dispatch(ev);
         }
         else
         {
            ev.type=MM_EVENT_DEAL_ADD; ev.reasonCode="DEAL";
            Dispatch(ev);
         }
      }
      else if(trans.type==TRADE_TRANSACTION_REQUEST)
      {
         uint rc = result.retcode;
         if(rc==0) return;
         if(rc!=TRADE_RETCODE_DONE && rc!=TRADE_RETCODE_DONE_PARTIAL && rc!=TRADE_RETCODE_PLACED)
         {
            string rcode = (rc==0?"RETCODE_UNKNOWN":"EXEC_RETCODE");
            if(rc==TRADE_RETCODE_REQUOTE || rc==TRADE_RETCODE_REJECT || rc==TRADE_RETCODE_CANCEL || rc==TRADE_RETCODE_ERROR || rc==TRADE_RETCODE_TIMEOUT) { /* known non-success */ }
            RecordReject(request.symbol,"Execution",rcode,result.comment,rc,"req");
         }
         if(rc==TRADE_RETCODE_DONE_PARTIAL)
         {
            MM_TradeEvent ev; ev.Reset(); ev.type=MM_EVENT_PARTIAL_FILL; ev.symbol=request.symbol;
            ev.volume=result.volume; ev.price=result.price; ev.timeServer=srv; ev.timeLocal=TimeLocal();
            ev.retcode=rc; ev.reasonCode="DONE_PARTIAL"; ev.reason="partial_fill";
            g_mmLog.Warn("REQ_PARTIAL",request.symbol+" vol="+DoubleToString(result.volume,2)+" req="+DoubleToString(request.volume,2));
            Dispatch(ev);
         }
      }
      else if(trans.type==TRADE_TRANSACTION_ORDER_ADD || trans.type==TRADE_TRANSACTION_ORDER_UPDATE || trans.type==TRADE_TRANSACTION_ORDER_DELETE)
      {
         if(trans.type==TRADE_TRANSACTION_ORDER_UPDATE || trans.type==TRADE_TRANSACTION_ORDER_DELETE)
         {
            MM_TradeEvent ev; ev.Reset(); ev.type=MM_EVENT_MODIFY; ev.order=trans.order; ev.symbol=trans.symbol;
            if(HistoryOrderSelect(trans.order))
            {
               ev.price=HistoryOrderGetDouble(trans.order, ORDER_PRICE_OPEN);
               ev.sl=HistoryOrderGetDouble(trans.order, ORDER_SL);
               ev.tp=HistoryOrderGetDouble(trans.order, ORDER_TP);
               ev.volume=HistoryOrderGetDouble(trans.order, ORDER_VOLUME_INITIAL);
            }
            else { ev.price=trans.price; ev.sl=trans.price_sl; ev.tp=trans.price_tp; ev.volume=trans.volume; }
            ev.timeServer=srv; ev.timeLocal=TimeLocal();
            ev.reasonCode = (trans.type==TRADE_TRANSACTION_ORDER_DELETE)?"ORDER_DELETE":"ORDER_UPDATE";
            Dispatch(ev);
         }
      }
      else if(trans.type==TRADE_TRANSACTION_POSITION)
      {
         MM_TradeEvent ev; ev.Reset(); ev.type=MM_EVENT_MODIFY; ev.symbol=trans.symbol;
         ev.positionId=(long)trans.position; ev.volume=trans.volume; ev.price=trans.price; ev.sl=trans.price_sl; ev.tp=trans.price_tp;
         ev.timeServer=srv; ev.timeLocal=TimeLocal(); ev.reasonCode="POSITION";
         Dispatch(ev);
      }
      else if(trans.type==TRADE_TRANSACTION_HISTORY_ADD || trans.type==TRADE_TRANSACTION_HISTORY_UPDATE || trans.type==TRADE_TRANSACTION_HISTORY_DELETE)
      {
         // informational
      }
      else
      {
         g_mmLog.Warn("TRANS_UNKNOWN","Unhandled transaction type="+(string)((int)trans.type)+" symbol="+trans.symbol);
      }
   }
};

#endif // MM_TRADE_LIFECYCLE_MQH
