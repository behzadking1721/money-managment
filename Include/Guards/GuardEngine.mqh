//+------------------------------------------------------------------+
//|                                                GuardEngine.mqh   |
//|                 Unified guard evaluation & reject sink (Phase 3) |
//+------------------------------------------------------------------+
#ifndef MM_GUARD_ENGINE_MQH
#define MM_GUARD_ENGINE_MQH

#include "IGuard.mqh"
#include "PermissionGuard.mqh"
#include "PropGuard.mqh"
#include "ProtectionGuard.mqh"
#include "NewsGuard.mqh"
#include "SessionSpreadGuard.mqh"
#include "../Core/RejectSink.mqh"
#include "../Core/Contracts.mqh"

struct MM_GuardReport
{
   bool          allowed;      // no BLOCK
   bool          hasWarn;
   bool          hasBlock;
   MM_GuardResult firstBlock;
   MM_GuardResult results[MM_MAX_GUARD_RESULTS];
   int           count;
   void Reset(){ allowed=true; hasWarn=false; hasBlock=false; count=0; firstBlock.Reset(); }
   void Add(const MM_GuardResult &r)
   {
      if(count<MM_MAX_GUARD_RESULTS) results[count++]=r;
      if(r.decision==GUARD_BLOCK){ hasBlock=true; allowed=false; if(firstBlock.reasonCode=="") firstBlock=r; }
      if(r.decision==GUARD_WARN){ hasWarn=true; }
   }
};

class CGuardEngine
{
private:
   CPermissionGuard    m_permission;
   CPropGuard          m_prop;
   CProtectionGuard    m_protection;
   CNewsGuard          m_news;
   CSessionSpreadGuard m_sessionSpread;
   IRejectSink        *m_sink;
   bool                m_sendToSink;

   void EvalOne(IGuard *g, const MM_TradePlan &plan, const MM_GuardConfig &cfg, MM_GuardReport &rep)
   {
      MM_GuardResult r; r.Reset();
      if(g==NULL){ rep.Add(r); return; }
      g.Evaluate(plan,cfg,r);
      // route BLOCK/WARN to central sink per contract
      if(m_sendToSink && m_sink!=NULL && (r.decision==GUARD_BLOCK || r.decision==GUARD_WARN))
         m_sink.OnGuardReject(r, plan.symbol);
      rep.Add(r);
   }

public:
   CGuardEngine(){ m_sink=NULL; m_sendToSink=true; }

   void Init(IRejectSink *sink, bool sendToSink=true){ m_sink=sink; m_sendToSink=sendToSink; }
   void SetSink(IRejectSink *sink){ m_sink=sink; }

   // Evaluate in frozen priority order: Permission -> Prop -> Protection -> News -> Session/Spread
   void Evaluate(const MM_TradePlan &plan, const MM_GuardConfig &cfg, MM_GuardReport &rep)
   {
      rep.Reset();
      EvalOne(GetPointer(m_permission),   plan, cfg, rep);
      EvalOne(GetPointer(m_prop),         plan, cfg, rep);
      EvalOne(GetPointer(m_protection),   plan, cfg, rep);
      EvalOne(GetPointer(m_news),         plan, cfg, rep);
      EvalOne(GetPointer(m_sessionSpread),plan, cfg, rep);
   }

   // Single CanExecute used by UI preview and send path. Reports to sink.
   bool CanExecute(const MM_TradePlan &plan, const MM_GuardConfig &cfg, MM_GuardReport &rep)
   {
      Evaluate(plan,cfg,rep);
      return rep.allowed;
   }

   // Preview without sink side-effects (UI live preview can opt-in)
   bool Preview(const MM_TradePlan &plan, const MM_GuardConfig &cfg, MM_GuardReport &rep)
   {
      bool prev=m_sendToSink; m_sendToSink=false;
      Evaluate(plan,cfg,rep);
      m_sendToSink=prev;
      return rep.allowed;
   }

   // Helper: fill common live fields (spread). Caller fills limits/counters/news/DD flags.
   void FillLiveConfig(const MM_TradePlan &plan, MM_GuardConfig &cfg)
   {
      double ask=SymbolInfoDouble(plan.symbol,SYMBOL_ASK), bid=SymbolInfoDouble(plan.symbol,SYMBOL_BID);
      double pt=SymbolInfoDouble(plan.symbol,SYMBOL_POINT);
      if(pt>0) cfg.spreadPoints=(ask-bid)/pt;
   }

   // Apply news manager state (Phase 7 wiring)
   void ApplyNewsState(MM_GuardConfig &cfg, bool hasData, bool isStale, bool inBlackout)
   {
      cfg.newsDataAvailable = hasData;
      cfg.newsIsStale = isStale;
      cfg.newsInBlackout = inBlackout;
   }
};

#endif // MM_GUARD_ENGINE_MQH
