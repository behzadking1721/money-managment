//+------------------------------------------------------------------+
//|                                                    IGuard.mqh    |
//|                             Guard interface & config (Phase 3)   |
//+------------------------------------------------------------------+
#ifndef MM_IGUARD_MQH
#define MM_IGUARD_MQH

#include "../Core/Contracts.mqh"

#define MM_MAX_GUARD_RESULTS 16

// Config/context shared by guards (values sourced from State/Profile/Prop settings)
struct MM_GuardConfig
{
   ENUM_MM_ACCOUNT_MODE accountMode;

   // Permission/connection
   bool   requireTerminalConnected;
   bool   requireTradeAllowed;
   bool   requireExpertEnabled;
   bool   requireAccountTradeAllowed;

   // Protection (personal/general)
   bool   protectionEnabled;
   double dailyLossLimitPct;      // 0 ignore
   double dailyProfitLimitPct;    // 0 ignore (profit lock target)
   double weeklyLossLimitPct;     // 0 ignore
   double monthlyLossLimitPct;    // 0 ignore
   double maxDrawdownPct;         // 0 ignore
   int    maxTradesPerDay;        // 0 ignore
   int    maxConsecLoss;          // 0 ignore
   int    cooldownMinutes;        // after consec loss breach
   bool   profitLockEnabled;

   // Runtime counters/state (fed from StateStore/Stats)
   double dailyLossPct;
   double dailyProfitPct;
   double weeklyLossPct;
   double monthlyLossPct;
   double currentDrawdownPct;
   int    tradesToday;
   int    consecLosses;
   bool   inCooldown;

   // Prop
   bool   propEnabled;
   int    propMaxTradesPerDay;    // 0 ignore
   double propDailyLossLimitPct;  // 0 ignore
   double propMaxTotalDDPct;      // 0 ignore
   double propDailyLossUsedPct;   // current
   double propTotalDDUsedPct;     // current
   double propMaxPositionSizePct; // 0 ignore
   bool   propConsistencyEnabled;
   double propConsistencyPct;     // 0 ignore
   double propTodayProfitPct;
   bool   propWeekendClose;
   bool   propNewsBlackout;       // delegated to NewsGuard config too

   // News
   bool   newsEnabled;
   bool   newsBlackoutOnHigh;     // when blackout configured
   bool   newsOfflineBlock;       // default false (warn)
   bool   newsIsStale;
   bool   newsDataAvailable;
   bool   newsInBlackout;
   bool   newsUpcomingWarn;

   // Session/Spread
   bool   sessionFilterEnabled;
   bool   sessionAllowed;         // resolved by caller
   bool   spreadCheckEnabled;
   double spreadPoints;
   double maxSpreadPoints;        // 0 ignore
   double spreadWarnPoints;       // 0 ignore

   void Reset()
   {
      accountMode=ACCOUNT_PERSONAL;
      requireTerminalConnected=true; requireTradeAllowed=true; requireExpertEnabled=true; requireAccountTradeAllowed=true;
      protectionEnabled=true;
      dailyLossLimitPct=0; dailyProfitLimitPct=0; weeklyLossLimitPct=0; monthlyLossLimitPct=0; maxDrawdownPct=0;
      maxTradesPerDay=0; maxConsecLoss=0; cooldownMinutes=0; profitLockEnabled=false;
      dailyLossPct=0; dailyProfitPct=0; weeklyLossPct=0; monthlyLossPct=0; currentDrawdownPct=0;
      tradesToday=0; consecLosses=0; inCooldown=false;
      propEnabled=false; propMaxTradesPerDay=0; propDailyLossLimitPct=0; propMaxTotalDDPct=0;
      propDailyLossUsedPct=0; propTotalDDUsedPct=0; propMaxPositionSizePct=0;
      propConsistencyEnabled=false; propConsistencyPct=0; propTodayProfitPct=0; propWeekendClose=false; propNewsBlackout=false;
      newsEnabled=true; newsBlackoutOnHigh=false; newsOfflineBlock=false; newsIsStale=false; newsDataAvailable=true; newsInBlackout=false; newsUpcomingWarn=false;
      sessionFilterEnabled=false; sessionAllowed=true; spreadCheckEnabled=true; spreadPoints=0; maxSpreadPoints=0; spreadWarnPoints=0;
   }
};

class IGuard
{
public:
   virtual string Id() = 0;
   virtual int Priority() = 0; // lower = higher priority in reporting
   virtual void Evaluate(const MM_TradePlan &plan, const MM_GuardConfig &cfg, MM_GuardResult &out) = 0;
};

#endif // MM_IGUARD_MQH
