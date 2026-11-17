//+------------------------------------------------------------------+
//|                                         ExecutionPolicy_Test.mq5 |
//|                    Phase 2: retcode classification & reasons     |
//+------------------------------------------------------------------+
#property script_show_inputs
#include "..\\..\\Include\\Core\\ExecutionPolicy.mqh"

int g_fail=0;
void Assert(bool c,const string n){ if(!c){Print("FAIL: ",n); g_fail++;} else Print("OK: ",n); }

void OnStart()
{
   g_fail=0; CExecutionPolicy p;
   // retryable per frozen spec
   Assert(p.IsRetryable(TRADE_RETCODE_REQUOTE),"requote retry");
   Assert(p.IsRetryable(TRADE_RETCODE_PRICE_CHANGED),"price changed retry");
   Assert(p.IsRetryable(TRADE_RETCODE_PRICE_OFF),"price off retry");
   Assert(p.IsRetryable(TRADE_RETCODE_TIMEOUT),"timeout retry");
   Assert(p.IsRetryable(TRADE_RETCODE_CONNECTION),"connection retry");
   Assert(p.IsRetryable(TRADE_RETCODE_TOO_MANY_REQUESTS),"too many retry");
   Assert(p.IsRetryable(TRADE_RETCODE_REJECT),"reject retry");
   Assert(p.IsRetryable(TRADE_RETCODE_ERROR),"error retry");
   // terminal block
   Assert(p.IsTerminalBlock(TRADE_RETCODE_INVALID_STOPS),"invalid stops terminal");
   Assert(p.IsTerminalBlock(TRADE_RETCODE_INVALID_VOLUME),"invalid volume terminal");
   Assert(p.IsTerminalBlock(TRADE_RETCODE_NO_MONEY),"no money terminal");
   Assert(p.IsTerminalBlock(TRADE_RETCODE_MARKET_CLOSED),"market closed terminal");
   Assert(p.IsTerminalBlock(TRADE_RETCODE_TRADE_DISABLED),"trade disabled terminal");
   Assert(p.IsTerminalBlock(TRADE_RETCODE_HEDGE_PROHIBITED),"hedge prohibited terminal");
   // success
   Assert(p.IsSuccess(TRADE_RETCODE_DONE),"done success");
   Assert(p.IsSuccess(TRADE_RETCODE_DONE_PARTIAL),"partial success");
   Assert(p.IsSuccess(TRADE_RETCODE_PLACED),"placed success");
   // reasons
   Assert(p.RetcodeReason(TRADE_RETCODE_INVALID_STOPS)=="INVALID_STOPS","reason invalid stops");
   Assert(p.RetcodeReason(TRADE_RETCODE_REQUOTE)=="REQUOTE","reason requote");
   // mutual expectations
   Assert(!p.IsRetryable(TRADE_RETCODE_INVALID_STOPS),"invalid stops not retryable");
   Assert(!p.IsTerminalBlock(TRADE_RETCODE_REQUOTE),"requote not terminal");

   if(g_fail==0) Print("ExecutionPolicy_Test: ALL PASS"); else Print("ExecutionPolicy_Test: FAIL count=",g_fail);
}
