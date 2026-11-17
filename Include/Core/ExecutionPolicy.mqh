//+------------------------------------------------------------------+
//|                                            ExecutionPolicy.mqh   |
//|   Phase 2: slippage, retcode retry/terminal, partial-fill policy |
//+------------------------------------------------------------------+
#ifndef MM_EXECUTION_POLICY_MQH
#define MM_EXECUTION_POLICY_MQH

#include "Contracts.mqh"

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
      // No-retry + block/fail with reason (frozen spec set)
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
         default: return "RETCODE_UNKNOWN";
      }
   }
};

#endif // MM_EXECUTION_POLICY_MQH
