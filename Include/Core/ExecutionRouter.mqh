//+------------------------------------------------------------------+
//|                                              ExecutionRouter.mqh |
//|      Phase 2/7: pre-send pipeline with logging and edge cases    |
//+------------------------------------------------------------------+
#ifndef MM_EXECUTION_ROUTER_MQH
#define MM_EXECUTION_ROUTER_MQH

#include "RiskEngine.mqh"
#include "StopsValidator.mqh"
#include "ExecutionPolicy.mqh"
#include "RejectSink.mqh"
#include "Contracts.mqh"
#include "Logger.mqh"
#include "../Guards/GuardEngine.mqh"
#include "../State/StateStore.mqh"
#include "../Trade/TradeLifecycle.mqh"
#include <Trade/Trade.mqh>

struct MM_ExecResult
{
   bool         allowed;
   bool         sent;
   MM_RiskResult  risk;
   MM_StopsCheck  checks;
   MM_GuardReport guards;
   MqlTradeResult tradeResult;
   string       reasonCode;
   string       messageEN;
   void Reset(){ allowed=false; sent=false; risk.Reset(); checks.Reset(); guards.Reset(); ZeroMemory(tradeResult); reasonCode=""; messageEN=""; }
};

class CExecutionRouter
{
private:
   CRiskEngine      m_risk;
   CStopsValidator  m_stops;
   CExecutionPolicy m_exec;
   CStateStore     *m_store;
   IRejectSink     *m_sink;
   CGuardEngine    *m_guards;
   CTrade           m_trade;
   ulong            m_magic;

   void Reject(const string symbol,const string code,const string msg,uint ret,const string ctx, MM_ExecResult &res)
   {
      res.allowed=false; res.sent=false; res.reasonCode=code; res.messageEN=msg;
      if(m_sink!=NULL) m_sink.OnExecutionReject(symbol,code,msg,ret,ctx);
      g_mmLog.Warn("EXEC_REJECT_ROUTE",symbol+" "+code+" rc="+(string)ret+" ctx="+ctx+" "+msg);
   }

public:
   CExecutionRouter(){ m_store=NULL; m_sink=NULL; m_guards=NULL; m_magic=0; }

   void Init(CStateStore *store, IRejectSink *sink, long magic=0, CGuardEngine *guards=NULL)
   {
      m_store=store; m_sink=sink; m_guards=guards;
      if(magic!=0){ m_magic=(ulong)magic; m_trade.SetExpertMagicNumber(m_magic); }
   }
   void SetGuards(CGuardEngine *guards){ m_guards=guards; }

   CTrade* Trade(){ return GetPointer(m_trade); }

   void BuildPlan(MM_TradePlan &plan, const string symbol, bool isBuy, bool pending, ENUM_ORDER_TYPE pendingType,
                  double entry, double sl, const double &tps[], int tpCount, double lotOrRisk,
                  ENUM_MM_SIZING_MODE sizingMode, const string templateId, long magic, int slippage)
   {
      plan.Reset();
      plan.symbol=symbol; plan.side=isBuy?POSITION_TYPE_BUY:POSITION_TYPE_SELL;
      plan.isPending=pending; plan.sizingMode=sizingMode; plan.templateId=templateId; plan.magic=magic; plan.slippagePoints=slippage;
      double ask=SymbolInfoDouble(symbol,SYMBOL_ASK), bid=SymbolInfoDouble(symbol,SYMBOL_BID);
      if(pending){ plan.orderType=pendingType; plan.entryPrice=entry; }
      else { plan.orderType=isBuy?ORDER_TYPE_BUY:ORDER_TYPE_SELL; plan.entryPrice=(entry>0)?entry:(isBuy?ask:bid); }
      plan.slPrice=sl;
      plan.tpCount = MathMin(tpCount, MM_MAX_TP_LEVELS);
      for(int i=0;i<plan.tpCount;i++) plan.tpPrice[i]=tps[i];
      if(sizingMode==SIZING_MANUAL_LOT) plan.lot=lotOrRisk; else plan.riskValue=lotOrRisk;
      plan.serverTime=TimeTradeServer();
   }

   bool Preflight(const MM_TradePlan &inPlan, MM_RiskContext &ctx, const MM_ExecPolicy &policy, MM_ExecResult &out, MM_GuardConfig &guardCfg)
   {
      out.Reset();
      if(inPlan.symbol==""){ Reject(inPlan.symbol,"INVALID_SYMBOL","Empty symbol",0,"preflight",out); return false; }
      if(m_store!=NULL && !m_store.IsOperational())
      { Reject(inPlan.symbol,"STATE_NOT_OPERATIONAL","State store non-operational; trading blocked",0,"preflight",out); return false; }
      MM_TradePlan plan=inPlan; plan.slippagePoints=policy.maxSlippagePoints;
      m_risk.Calculate(plan, ctx, out.risk);
      plan.lot = out.risk.lot;
      plan.riskValue = (inPlan.sizingMode==SIZING_AUTO_RISK)?inPlan.riskValue:out.risk.riskPercent;
      if(out.risk.blocked || !out.risk.valid)
      { Reject(inPlan.symbol,"RISK_BLOCK", out.risk.warningsCount>0?out.risk.warnings[0]:"Risk calculation blocked",0,"risk",out); return false; }
      if(!m_stops.ValidatePlan(plan, out.checks))
      { Reject(inPlan.symbol, out.checks.reasonCode, out.checks.messageEN, 0, "stops", out); return false; }
      if(m_guards!=NULL)
      {
         MM_TradePlan sized=plan; sized.lot=out.risk.lot;
         if(!m_guards.CanExecute(sized, guardCfg, out.guards))
         {
            out.allowed=false;
            out.reasonCode = out.guards.firstBlock.reasonCode;
            out.messageEN  = out.guards.firstBlock.messageEN;
            g_mmLog.Warn("GUARD_BLOCK",inPlan.symbol+" "+out.reasonCode);
            return false;
         }
      }
      out.allowed=true; out.reasonCode="OK"; out.messageEN="Preflight passed";
      return true;
   }

   bool Send(MM_TradePlan &plan, MM_RiskContext &ctx, MM_ExecPolicy &policy, MM_ExecResult &out, MM_GuardConfig &guardCfg)
   {
      out.Reset();
      if(!Preflight(plan, ctx, policy, out, guardCfg)) return false;
      plan.lot = out.risk.lot;
      m_exec.ApplyPolicyToTrade(m_trade, policy);
      if(m_magic==0 && plan.magic!=0){ m_magic=(ulong)plan.magic; m_trade.SetExpertMagicNumber(m_magic); }
      if(m_magic!=0 && plan.magic==0) plan.magic=(long)m_magic;
      bool ok = m_exec.ExecuteWithRetry(m_trade, plan, policy, out.tradeResult);
      uint rc = out.tradeResult.retcode;
      if(ok){ out.sent=true; out.allowed=true; out.reasonCode=m_exec.RetcodeReason(rc); out.messageEN="Order sent"; g_mmLog.Info("SEND_OK",plan.symbol+" rc="+(string)rc); return true; }
      string reason=m_exec.RetcodeReason(rc);
      Reject(plan.symbol, reason, (out.tradeResult.comment!="")?out.tradeResult.comment:reason, rc, "exec", out);
      out.tradeResult.retcode=rc;
      return false;
   }
};

#endif // MM_EXECUTION_ROUTER_MQH
