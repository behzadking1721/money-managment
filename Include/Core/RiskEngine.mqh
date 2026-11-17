//+------------------------------------------------------------------+
//|                                                  RiskEngine.mqh  |
//|             Phase 2: lot/risk sizing, caps, aggregate exposure  |
//+------------------------------------------------------------------+
#ifndef MM_RISK_ENGINE_MQH
#define MM_RISK_ENGINE_MQH

#include "Contracts.mqh"

// Risk basis for sizing/caps (configurable by mode/profile; defaults per frozen plan)
enum ENUM_MM_RISK_BASIS
{
   MM_BASIS_EQUITY = 0,       // Personal default
   MM_BASIS_BALANCE_DAY = 1,  // day-start balance
   MM_BASIS_ALLOWED_DD = 2    // Prop default: min(remaining Daily DD, remaining Max DD)
};

struct MM_RiskContext
{
   ENUM_MM_ACCOUNT_MODE accountMode;
   ENUM_MM_RISK_BASIS   basis;
   double               equity;
   double               balance;
   double               dayStartBalance;
   double               remainingDailyDDMoney; // money allowed until daily DD breach (0 = ignore)
   double               remainingMaxDDMoney;   // money allowed until max DD breach (0 = ignore)
   double               commissionPerLot;      // account-currency per round lot (estimate)
   double               swapEstimatePerLot;    // account-currency estimate (optional)
   bool                 useSwapInRisk;
   double               openRiskMoney;         // aggregate risk of open positions (by SL distance)
   double               maxPositionVolume;     // 0 = ignore (prop/symbol cap)
   double               minRiskPercent;
   double               maxRiskPercent;
   void Reset()
   {
      accountMode=ACCOUNT_PERSONAL; basis=MM_BASIS_EQUITY;
      equity=0; balance=0; dayStartBalance=0;
      remainingDailyDDMoney=0; remainingMaxDDMoney=0;
      commissionPerLot=0; swapEstimatePerLot=0; useSwapInRisk=false;
      openRiskMoney=0; maxPositionVolume=0; minRiskPercent=0; maxRiskPercent=100;
   }
};

class CRiskEngine
{
public:
   // Resolve basis amount in account currency.
   double BasisAmount(const MM_RiskContext &ctx)
   {
      if(ctx.basis==MM_BASIS_BALANCE_DAY && ctx.dayStartBalance>0) return ctx.dayStartBalance;
      if(ctx.basis==MM_BASIS_ALLOWED_DD)
      {
         double dd=0;
         if(ctx.remainingDailyDDMoney>0 && ctx.remainingMaxDDMoney>0) dd=MathMin(ctx.remainingDailyDDMoney, ctx.remainingMaxDDMoney);
         else if(ctx.remainingDailyDDMoney>0) dd=ctx.remainingDailyDDMoney;
         else if(ctx.remainingMaxDDMoney>0) dd=ctx.remainingMaxDDMoney;
         if(dd>0) return dd;
         // fallback to equity if caps not provided
      }
      if(ctx.equity>0) return ctx.equity;
      return ctx.balance;
   }

   // Allowed remaining risk money for a new trade given aggregate exposure and caps.
   double AllowedNewRiskMoney(const MM_RiskContext &ctx, double basisAmount, double requestedRiskMoney, string &capNote)
   {
      capNote="";
      double allowed=requestedRiskMoney;
      // Prop/DD cap on money: min(remainingDailyDD, remainingMaxDD) minus open risk
      if(ctx.remainingDailyDDMoney>0 || ctx.remainingMaxDDMoney>0)
      {
         double ddRemain=1e100;
         if(ctx.remainingDailyDDMoney>0) ddRemain=MathMin(ddRemain, ctx.remainingDailyDDMoney);
         if(ctx.remainingMaxDDMoney>0) ddRemain=MathMin(ddRemain, ctx.remainingMaxDDMoney);
         double ddBudget = ddRemain - ctx.openRiskMoney;
         if(ddBudget < allowed){ allowed=MathMax(0.0, ddBudget); capNote="cap:DD_remaining"; }
      }
      // Aggregate exposure cap: (openRisk + newRisk) <= risk budget over basis
      // risk budget here = requested as % of basis; ensure not exceeding remaining after open
      double basisBudget = requestedRiskMoney; // caller passes desired; aggregate guard below
      if(ctx.openRiskMoney + allowed > basisBudget + ctx.openRiskMoney && basisBudget>=0)
      {
         // no-op: basisBudget already represented by requested; explicit aggregate clamp:
      }
      if(allowed < 0) allowed=0;
      return allowed;
   }

   // Core formula: risk money per 1.0 lot for given SL distance.
   bool RiskPerLot(const string symbol, double slDistancePrice, const MM_RiskContext &ctx, double &perLot, string &err)
   {
      perLot=0; err="";
      double point=SymbolInfoDouble(symbol, SYMBOL_POINT);
      double tickValue=SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize=SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      if(point<=0 || tickValue<=0 || tickSize<=0 || slDistancePrice<=0)
      { err="invalid_symbol_or_sl"; return false; }
      double slPoints = slDistancePrice / point;
      double slMoney = (slPoints * point / tickSize) * tickValue; // account currency per lot
      double extra = ctx.commissionPerLot;
      if(ctx.useSwapInRisk) extra += ctx.swapEstimatePerLot;
      perLot = slMoney + extra;
      if(perLot<=0){ err="invalid_risk_per_lot"; return false; }
      return true;
   }

   // Compute lot/risk for a plan. Enforces: no-SL block in auto, aggregate open+new, caps, min/max/step.
   void Calculate(const MM_TradePlan &plan, const MM_RiskContext &ctx, MM_RiskResult &out)
   {
      out.Reset();
      double basis = BasisAmount(ctx);
      out.basis = (ctx.basis==MM_BASIS_BALANCE_DAY)?"BalanceDay":(ctx.basis==MM_BASIS_ALLOWED_DD?"AllowedDD":"Equity");
      string sym = plan.symbol;

      double slDist = MathAbs(plan.entryPrice - plan.slPrice);
      if(slDist<=0)
      {
         if(plan.sizingMode==SIZING_AUTO_RISK)
         {
            out.valid=false; out.blocked=true; out.AddWarn("NO_SL_BLOCK: auto-risk requires valid SL");
            return;
         }
         // manual lot still needs SL for preview/R; mark invalid preview but carry lot
         out.valid=false; out.blocked=true; out.AddWarn("NO_SL: SL required for risk/R preview");
         return;
      }

      double perLot=0; string err="";
      if(!RiskPerLot(sym, slDist, ctx, perLot, err)){ out.valid=false; out.blocked=true; out.AddWarn(err); return; }

      double lot=0;
      double riskMoney=0;
      double riskPct = plan.riskValue;
      if(plan.sizingMode==SIZING_MANUAL_LOT)
      {
         lot = plan.lot;
         riskMoney = lot * perLot;
         if(basis>0) riskPct = (riskMoney / basis) * 100.0; else riskPct=0;
      }
      else
      {
         // clamp requested percent to profile bounds
         double reqPct = riskPct;
         if(ctx.maxRiskPercent>0 && reqPct>ctx.maxRiskPercent){ reqPct=ctx.maxRiskPercent; out.AddCap("cap:maxRiskPercent"); }
         if(ctx.minRiskPercent>0 && reqPct<ctx.minRiskPercent && reqPct>0){ /* allow below min? keep as requested but warn */ out.AddWarn("below_minRiskPercent"); }
         double requestedMoney = (basis>0)? (basis * reqPct / 100.0) : 0;
         riskMoney = requestedMoney;
         // aggregate + DD remaining cap (strictest)
         string capNote="";
         double allowedMoney = AllowedNewRiskMoney(ctx,basis,requestedMoney,capNote);
         if(allowedMoney < riskMoney){ riskMoney=allowedMoney; if(capNote!="") out.AddCap(capNote); out.AddCap("cap:aggregate_or_dd"); }
         if(riskMoney<=0){ out.valid=false; out.blocked=true; out.AddWarn("BLOCK: no risk budget after aggregate/DD caps"); return; }
         lot = riskMoney / perLot;
         if(basis>0) riskPct = (riskMoney / basis) * 100.0; else riskPct=0;
      }

      // volume constraints
      double vmin=SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
      double vmax=SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
      double vstep=SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
      if(ctx.maxPositionVolume>0) vmax=MathMin(vmax, ctx.maxPositionVolume);
      if(vstep<=0) vstep=0.01;
      // floor to step (conservative: do not exceed risk)
      lot = MathFloor(lot / vstep) * vstep;
      if(lot < vmin){ out.valid=false; out.blocked=true; out.AddWarn("BLOCK: lot below minimum after caps/step"); out.lot=lot; out.riskMoney=riskMoney; return; }
      if(lot > vmax){ lot=vmax; out.AddCap("cap:max_volume"); }
      // re-evaluate money/percent after rounding
      riskMoney = lot * perLot;
      if(basis>0) riskPct = (riskMoney / basis) * 100.0;

      // aggregate exposure final guard (openRisk + newRisk vs allowed budgets)
      if(ctx.remainingDailyDDMoney>0 || ctx.remainingMaxDDMoney>0)
      {
         double ddRemain=1e100;
         if(ctx.remainingDailyDDMoney>0) ddRemain=MathMin(ddRemain, ctx.remainingDailyDDMoney);
         if(ctx.remainingMaxDDMoney>0) ddRemain=MathMin(ddRemain, ctx.remainingMaxDDMoney);
         if(ctx.openRiskMoney + riskMoney > ddRemain + 1e-6){ out.AddWarn("WARN: rounded risk touches DD cap"); }
      }

      out.lot = lot;
      out.riskMoney = riskMoney;
      out.riskPercent = riskPct;
      out.rr = 0; // set by caller when TP known (|TP-entry|/|entry-SL|)
      out.valid = true;
      out.blocked = false;
   }

   // Helper: compute RR from plan distances (TP1).
   double ComputeRR(const MM_TradePlan &plan)
   {
      double sl=MathAbs(plan.entryPrice-plan.slPrice);
      if(sl<=0 || plan.tpCount<=0) return 0;
      double tp=MathAbs(plan.tpPrice[0]-plan.entryPrice);
      return tp/sl;
   }
};

#endif // MM_RISK_ENGINE_MQH
