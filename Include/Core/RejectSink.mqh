//+------------------------------------------------------------------+
//|                                                RejectSink.mqh    |
//|                  Central reject-reason sink contract (Phase 1+)  |
//+------------------------------------------------------------------+
#ifndef MM_REJECT_SINK_MQH
#define MM_REJECT_SINK_MQH

#include "Contracts.mqh"

// Unified sink: execution retcodes and guard decisions must both flow here.
// GuardEngine (Phase 3) should call IRejectSink::OnGuardReject for every BLOCK
// and (optionally) WARN so UI/Stats see a single source of truth.
class IRejectSink
{
public:
   virtual void OnExecutionReject(const string symbol,const string reasonCode,const string messageEN,uint retcode,const string context) = 0;
   virtual void OnGuardReject(const MM_GuardResult &gr,const string symbol) = 0;
};

#endif // MM_REJECT_SINK_MQH
