//+------------------------------------------------------------------+
//|                                              ExecutionPolicy.mqh |
//|   Phase 2/7: slippage, retcode policy, retry, unknown logging    |
//+------------------------------------------------------------------+
#ifndef MM_EXECUTION_POLICY_MQH
#define MM_EXECUTION_POLICY_MQH

#include "Contracts.mqh"
#include "Logger.mqh"
#include <Trade/Trade.mqh>

enum ENUM_MM_PARTIAL_FILL_POLICY
{
   MM_FILL_KEEP_REMAINDER   = 0, // default
   MM_FILL_CANCEL_REMAINDER = 1,
   MM_FILL_REPRICE_RETRY    = 2
};

struct MM_ExecPolicy
{
   int                      maxRetries;
   int                      retryDelayMs;
   int                      maxSlippagePoints; // per-symbol/template resolved value
   ENUM_MM_PARTIAL_FILL_POLICY partialFill;
   void Reset(){ maxRetries=3; retryDelayMs=250; maxSlippagePoints=30; partialFill=MM_FILL_KEEP_REMAINDER; }
};

class CExecutionPolicy
{
public:
   bool IsRetryable(uint retcode)
   {
      switch(retcode)
      {
         case TRADE_RETCODE_REQUOTE:
         case TRADE_RETCODE_PRICE_CHANGED:
         case TRADE_RETCODE_PRICE_OFF:
         case TRADE_RETCODE_TIMEOUT:
         case TRADE_RETCODE_CONNECTION:
         case TRADE_RETCODE_TOO_MANY_REQUESTS:
         case TRADE_RETCODE_REJECT:
         case TRADE_RETCODE_ERROR:
            return true;
         default:
            return false;
      }
   }

   bool IsTerminalBlock(uint retcode)
   {
      switch(retcode)
      {
         case TRADE_RETCODE_INVALID_STOPS:
         case TRADE_RETCODE_INVALID_VOLUME:
         case TRADE_RETCODE_INVALID_FILL:
         case TRADE_RETCODE_INVALID_ORDER:
         case TRADE_RETCODE_INVALID_PRICE:
         case TRADE_RETCODE_INVALID_EXPIRATION:
         case TRADE_RETCODE_TRADE_DISABLED:
         case TRADE_RETCODE_MARKET_CLOSED:
         case TRADE_RETCODE_NO_MONEY:
         case TRADE_RETCODE_LIMIT_ORDERS:
         case TRADE_RETCODE_LIMIT_POSITIONS:
         case TRADE_RETCODE_HEDGE_PROHIBITED:
         case TRADE_RETCODE_POSITION_CLOSED:
            return true;
         default:
            return false;
      }
   }

   bool IsSuccess(uint retcode)
   {
      return (retcode==TRADE_RETCODE_DONE || retcode==TRADE_RETCODE_DONE_PARTIAL || retcode==TRADE_RETCODE_PLACED);
   }

   const string RetcodeReason(uint retcode)
   {
      switch(retcode)
      {
         case TRADE_RETCODE_REQUOTE: return "REQUOTE";
         case TRADE_RETCODE_REJECT: return "REJECT";
         case TRADE_RETCODE_CANCEL: return "CANCEL";
         case TRADE_RETCODE_PLACED: return "PLACED";
         case TRADE_RETCODE_DONE: return "DONE";
         case TRADE_RETCODE_DONE_PARTIAL: return "DONE_PARTIAL";
         case TRADE_RETCODE_ERROR: return "ERROR";
         case TRADE_RETCODE_TIMEOUT: return "TIMEOUT";
         case TRADE_RETCODE_INVALID: return "INVALID_REQUEST";
         case TRADE_RETCODE_INVALID_VOLUME: return "INVALID_VOLUME";
         case TRADE_RETCODE_INVALID_PRICE: return "INVALID_PRICE";
         case TRADE_RETCODE_INVALID_STOPS: return "INVALID_STOPS";
         case TRADE_RETCODE_TRADE_DISABLED: return "TRADE_DISABLED";
         case TRADE_RETCODE_MARKET_CLOSED: return "MARKET_CLOSED";
         case TRADE_RETCODE_NO_MONEY: return "NO_MONEY";
         case TRADE_RETCODE_PRICE_CHANGED: return "PRICE_CHANGED";
         case TRADE_RETCODE_PRICE_OFF: return "PRICE_OFF";
         case TRADE_RETCODE_INVALID_EXPIRATION: return "INVALID_EXPIRATION";
         case TRADE_RETCODE_INVALID_FILL: return "INVALID_FILL";
         case TRADE_RETCODE_CONNECTION: return "CONNECTION";
         case TRADE_RETCODE_TOO_MANY_REQUESTS: return "TOO_MANY_REQUESTS";
         case TRADE_RETCODE_LIMIT_ORDERS: return "LIMIT_ORDERS";
         case TRADE_RETCODE_LIMIT_POSITIONS: return "LIMIT_POSITIONS";
         case TRADE_RETCODE_INVALID_ORDER: return "INVALID_ORDER";
         case TRADE_RETCODE_POSITION_CLOSED: return "POSITION_CLOSED";
         case TRADE_RETCODE_HEDGE_PROHIBITED: return "HEDGE_PROHIBITED";
         case TRADE_RETCODE_CLOSE_ORDER_EXIST: return "CLOSE_ORDER_EXIST";
         case TRADE_RETCODE_LIMIT_VOLUME: return "LIMIT_VOLUME";
         case TRADE_RETCODE_FIFO_CLOSE: return "FIFO_CLOSE";
         default:
            g_mmLog.Warn("RETCODE_UNKNOWN","Unknown trade retcode="+(string)retcode);
            return "RETCODE_UNKNOWN";
      }
   }

   void ApplyPolicyToTrade(CTrade &trade, const MM_ExecPolicy &policy)
   {
      trade.SetDeviationInPoints((ulong)policy.maxSlippagePoints);
      trade.SetTypeFilling(ORDER_FILLING_FOK);
      // caller may adjust filling/expiration per symbol; default safe
   }

   bool ExecuteWithRetry(CTrade &trade, const MM_TradePlan &plan, const MM_ExecPolicy &policy, MqlTradeResult &outRes)
   {
      ZeroMemory(outRes);
      // Multi-TP execution: split into multiple orders/positions (hedging-safe). If tpCount<=1, behave as before.
      if(plan.tpCount > 1)
      {
         return ExecuteMultiTp(trade, plan, policy, outRes);
      }
      for(int attempt=0; attempt<=policy.maxRetries; attempt++)
      {
         bool sent=false;
         if(plan.isPending)
         {
            sent = trade.OrderOpen(plan.symbol, plan.orderType, plan.lot, 0, plan.entryPrice, plan.slPrice,
                                   (plan.tpCount>0?plan.tpPrice[0]:0), ORDER_TIME_GTC, 0, plan.comment);
         }
         else
         {
            ENUM_ORDER_TYPE ot = (plan.side==POSITION_TYPE_BUY)?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
            sent = trade.PositionOpen(plan.symbol, ot, plan.lot,
                                      (plan.side==POSITION_TYPE_BUY)?SymbolInfoDouble(plan.symbol,SYMBOL_ASK):SymbolInfoDouble(plan.symbol,SYMBOL_BID),
                                      plan.slPrice, (plan.tpCount>0?plan.tpPrice[0]:0), plan.comment);
         }
         trade.Result(outRes);
         uint rc = outRes.retcode;
         string reason = RetcodeReason(rc);
         if(IsSuccess(rc))
         {
            if(rc==TRADE_RETCODE_DONE_PARTIAL)
            {
               g_mmLog.Warn("PARTIAL_FILL","symbol="+plan.symbol+" vol="+DoubleToString(outRes.volume,2)+" req="+DoubleToString(plan.lot,2)+" policy="+(string)((int)policy.partialFill));
               if(policy.partialFill==MM_FILL_CANCEL_REMAINDER)
                  outRes.comment = "partial_keep_or_cancel_by_caller";
            }
            g_mmLog.Info("EXEC_OK",plan.symbol+" "+reason+" vol="+DoubleToString(outRes.volume,2)+" deal="+(string)outRes.deal+" order="+(string)outRes.order);
            return true;
         }
         if(IsTerminalBlock(rc))
         {
            g_mmLog.Error("EXEC_BLOCK",plan.symbol+" "+reason+" rc="+(string)rc+" "+outRes.comment);
            return false;
         }
         if(IsRetryable(rc))
         {
            g_mmLog.Warn("EXEC_RETRY",plan.symbol+" "+reason+" rc="+(string)rc+" attempt="+(string)(attempt+1));
            if(attempt < policy.maxRetries) { Sleep(policy.retryDelayMs); continue; }
         }
         else
         {
            g_mmLog.Warn("RETCODE_UNCLASSIFIED",plan.symbol+" rc="+(string)rc+" "+reason+" "+outRes.comment);
         }
         return false;
      }
      return false;
   }

   // Split totalLot into 'parts' legs aligned to SYMBOL_VOLUME_STEP.
   // Preserves total exactly on broker step grid (no silent increase/reduction), enforces min/max per leg.
   // Returns parts on success (vols[0..parts-1] filled), or 0 if invalid/impossible.
   int SplitVolume(const string symbol, double totalLot, int parts, double &vols[])
   {
      if(parts<=0) return 0;
      ArrayResize(vols, parts);
      for(int i=0;i<parts;i++) vols[i]=0.0;

      double vmin=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
      double vmax=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
      double vstep=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
      if(vstep<=0.0) return 0;
      if(vmin<=0.0) vmin=vstep;
      if(vmax < vmin - 1e-12) return 0;

      // integer-step arithmetic for exact preservation/alignment
      long stepMin = (long)MathCeil(vmin/vstep - 1e-12);
      long stepMax = (long)MathFloor(vmax/vstep + 1e-12);
      long stepTotal = (long)MathFloor(totalLot/vstep + 1e-12);
      if(stepMin < 1) stepMin = 1;
      if(stepMax < stepMin || stepTotal <= 0) return 0;

      double normTotal = stepTotal * vstep;
      // reject if requested total is not on step grid (prevents silent reduction/increase)
      if(MathAbs(totalLot - normTotal) > vstep*1e-6) return 0;

      // feasibility
      if(stepTotal < stepMin * (long)parts) return 0;
      if(stepTotal > stepMax * (long)parts) return 0;

      long base = stepTotal / parts;
      long rem  = stepTotal - base * (long)parts;
      long legSteps[]; ArrayResize(legSteps, parts);
      for(int i=0;i<parts;i++) legSteps[i]=base;
      for(int i=0;i<rem && i<parts;i++) legSteps[i]++;

      // ensure each leg >= stepMin by borrowing (feasible by checks above)
      for(int i=0;i<parts;i++)
      {
         int guard=0;
         while(legSteps[i] < stepMin && guard < 100000)
         {
            int donor=-1;
            for(int j=0;j<parts;j++) if(j!=i && legSteps[j] > stepMin){ donor=j; break; }
            if(donor<0) return 0;
            legSteps[donor]--; legSteps[i]++; guard++;
         }
         if(legSteps[i] < stepMin || legSteps[i] > stepMax) return 0;
      }

      int vdigits = (int)MathCeil(-MathLog10(vstep)); if(vdigits<0) vdigits=0; if(vdigits>8) vdigits=8;
      long finalSteps=0;
      for(int i=0;i<parts;i++)
      {
         finalSteps += legSteps[i];
         vols[i] = NormalizeDouble(legSteps[i] * vstep, vdigits);
         if(vols[i] < vmin - 1e-12 || vols[i] > vmax + 1e-12) return 0;
         // step alignment guard
         double q = vols[i] / vstep;
         if(MathAbs(q - MathRound(q)) > 1e-6) return 0;
      }
      if(finalSteps != stepTotal) return 0;
      double finalSum=0.0; for(int i=0;i<parts;i++) finalSum += vols[i];
      if(MathAbs(finalSum - normTotal) > vstep*1e-6) return 0;
      return parts;
   }

private:
   bool ExecuteMultiTp(CTrade &trade, const MM_TradePlan &plan, const MM_ExecPolicy &policy, MqlTradeResult &outRes)
   {
      ZeroMemory(outRes);
      // Multi-TP uses split execution (separate positions/orders per TP). On netting accounts market positions merge
      // and cannot hold multiple TPs; reject explicitly to avoid silent incorrect behavior.
      long marginMode = AccountInfoInteger(ACCOUNT_MARGIN_MODE);
      bool isHedging = (marginMode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
      if(!plan.isPending && !isHedging)
      {
         outRes.retcode = TRADE_RETCODE_INVALID; outRes.comment = "Multi-TP market unsupported on netting account";
         g_mmLog.Warn("EXEC_BLOCK","MULTI_TP_NETTING_UNSUPPORTED: market split TP requires hedging account");
         return false;
      }
      if(plan.isPending && !isHedging)
      {
         // Pending orders can be placed, but on fill in netting they merge; reject to keep behavior explicit/safe.
         outRes.retcode = TRADE_RETCODE_INVALID; outRes.comment = "Multi-TP pending unsupported on netting account";
         g_mmLog.Warn("EXEC_BLOCK","MULTI_TP_NETTING_UNSUPPORTED: pending split TP may merge on fill in netting");
         return false;
      }

      int n = plan.tpCount; if(n<2) return false; if(n>MM_MAX_TP_LEVELS) n=MM_MAX_TP_LEVELS;
      double vols[]; if(SplitVolume(plan.symbol, plan.lot, n, vols) != n)
      {
         outRes.retcode = TRADE_RETCODE_INVALID_VOLUME; outRes.comment = "Multi-TP volume split failed";
         g_mmLog.Warn("EXEC_BLOCK","MULTI_TP_SPLIT_FAIL: invalid/impossible split for "+IntegerToString(n)+" TPs (lot="+DoubleToString(plan.lot,8)+")");
         return false;
      }

      bool allOk=true; uint lastRc=TRADE_RETCODE_DONE; string lastReason="DONE"; double sentVol=0.0; ulong lastDeal=0, lastOrder=0;
      for(int i=0;i<n;i++)
      {
         if(vols[i] <= 0.0) continue;
         bool sent=false; MqlTradeResult partRes; ZeroMemory(partRes);
         for(int attempt=0; attempt<=policy.maxRetries; attempt++)
         {
            if(plan.isPending)
            {
               sent = trade.OrderOpen(plan.symbol, plan.orderType, vols[i], 0, plan.entryPrice, plan.slPrice,
                                      plan.tpPrice[i], ORDER_TIME_GTC, 0, plan.comment);
            }
            else
            {
               ENUM_ORDER_TYPE ot = (plan.side==POSITION_TYPE_BUY)?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
               sent = trade.PositionOpen(plan.symbol, ot, vols[i],
                                         (plan.side==POSITION_TYPE_BUY)?SymbolInfoDouble(plan.symbol,SYMBOL_ASK):SymbolInfoDouble(plan.symbol,SYMBOL_BID),
                                         plan.slPrice, plan.tpPrice[i], plan.comment);
            }
            trade.Result(partRes);
            uint rc = partRes.retcode;
            string reason = RetcodeReason(rc);
            if(IsSuccess(rc))
            {
               sentVol += partRes.volume>0?partRes.volume:vols[i];
               lastDeal = partRes.deal; lastOrder = partRes.order; lastRc=rc; lastReason=reason;
               g_mmLog.Info("EXEC_OK","MULTI_TP part="+IntegerToString(i+1)+"/"+IntegerToString(n)+" vol="+DoubleToString(vols[i],2)+" tp="+DoubleToString(plan.tpPrice[i],(int)SymbolInfoInteger(plan.symbol,SYMBOL_DIGITS))+" rc="+reason);
               break;
            }
            if(IsTerminalBlock(rc))
            {
               g_mmLog.Error("EXEC_BLOCK","MULTI_TP part="+IntegerToString(i+1)+" "+reason+" rc="+(string)rc+" "+partRes.comment);
               allOk=false; outRes=partRes; lastRc=rc; lastReason=reason; attempt=policy.maxRetries+1; break;
            }
            if(IsRetryable(rc))
            {
               g_mmLog.Warn("EXEC_RETRY","MULTI_TP part="+IntegerToString(i+1)+" "+reason+" attempt="+(string)(attempt+1));
               if(attempt < policy.maxRetries) { Sleep(policy.retryDelayMs); continue; }
            }
            allOk=false; outRes=partRes; lastRc=rc; lastReason=reason; attempt=policy.maxRetries+1; break;
         }
         if(!allOk) break;
      }

      if(allOk)
      {
         outRes.retcode = lastRc; outRes.comment = "MULTI_TP:"+IntegerToString(n)+" parts sent";
         outRes.volume = sentVol; outRes.deal = lastDeal; outRes.order = lastOrder;
         g_mmLog.Info("EXEC_OK",plan.symbol+" MULTI_TP complete parts="+IntegerToString(n)+" totalVol="+DoubleToString(sentVol,2));
         return true;
      }
      // Partial failure: do not roll back successful parts automatically (may have filled); report failure for remaining.
      outRes.comment = StringFormat("MULTI_TP partial failure after vol=%.2f (%s)", sentVol, outRes.comment);
      return false;
   }
};

#endif // MM_EXECUTION_POLICY_MQH
