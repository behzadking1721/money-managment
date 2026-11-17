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
private:
   double VolumeDigits(double step)
   {
      if(step<=0) return 2;
      int d=(int)MathCeil(-MathLog10(step));
      if(d<0) d=0; if(d>8) d=8;
      return d;
   }

public:
   double BasisAmount(const MM_RiskContext &ctx)
   {
      if(ctx.basis==MM_BASIS_BALANCE_DAY && ctx.dayStartBalance>0) return ctx.dayStartBalance;
      if(ctx.basis==MM_BASIS_ALLOWED_DD)
      {
         double dd=0;
         bool has=false;
         if(ctx.remainingDailyDDMoney>0){ dd=ctx.remainingDailyDDMoney; has=true; }
         if(ctx.remainingMaxDDMoney>0){ dd = has ? MathMin(dd, ctx.remainingMaxDDMoney) : ctx.remainingMaxDDMoney; has=true; }
         if(has && dd>0) return dd;
      }
      if(ctx.equity>0) return ctx.equity;
      return ctx.balance;
   }

   // Core formula: risk money per 1.0 lot for given SL distance (price units).
   bool RiskPerLot(const string symbol, double slDistancePrice, const MM_RiskContext &ctx, double &perLot, string &err)
   {
      perLot=0; err="";
      double point=SymbolInfoDouble(symbol, SYMBOL_POINT);
      double tickValue=SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize=SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      if(point<=0 || tickValue<=0 || tickSize<=0 || slDistancePrice<=0)
      { err="invalid_symbol_or_sl"; return false; }
      double slPoints = slDistancePrice / point;
      double slMoney = (slPoints * point / tickSize) * tickValue;
      double extra = ctx.commissionPerLot;
      if(ctx.useSwapInRisk) extra += ctx.swapEstimatePerLot;
      perLot = slMoney + extra;
      if(perLot<=0){ err="invalid_risk_per_lot"; return false; }
      return true;
   }

   // Conservative aggregate open risk: sum(|price-sl| risk) over open positions by SL distance.
   double CalcOpenRiskMoney(long magicFilter=0, const string symbolFilter="")
   {
      double total=0.0;
      int totalPos=PositionsTotal();
      for(int i=0;i<totalPos;i++)
      {
         ulong ticket=PositionGetTicket(i);
         if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
         string sym=PositionGetString(POSITION_SYMBOL);
         long mg=(long)PositionGetInteger(POSITION_MAGIC);
         if(symbolFilter!="" && sym!=symbolFilter) continue;
         if(magicFilter!=0 && mg!=magicFilter) continue;
         double vol=PositionGetDouble(POSITION_VOLUME);
         double open=PositionGetDouble(POSITION_PRICE_OPEN);
         double sl=PositionGetDouble(POSITION_SL);
         ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double point=SymbolInfoDouble(sym,SYMBOL_POINT);
         double tickValue=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE);
         double tickSize=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_SIZE);
         if(point<=0 || tickValue<=0 || tickSize<=0 || vol<=0) continue;
         double refPrice = open; // conservative: risk from entry to SL
         double slDist = MathAbs(refPrice - sl);
         if(sl<=0 || slDist<=0)
         {
            // no SL: cannot quantify; treat as open risk unknown -> add 0 here but caller should cap elsewhere.
            continue;
         }
         double perLot = (slDist / tickSize) * tickValue;
         if(perLot>0) total += perLot * vol;
      }
      return total;
   }

   // Fill context from live account + computed open risk. DD remaining values must be supplied by caller (Protection/Prop in Phase 3).
   void BuildContext(MM_RiskContext &ctx, ENUM_MM_ACCOUNT_MODE mode, ENUM_MM_RISK_BASIS basis,
                     double dayStartBalance, double remainingDailyDDMoney, double remainingMaxDDMoney,
                     double commissionPerLot, double swapEstimatePerLot, bool useSwapInRisk,
                     double minRiskPercent, double maxRiskPercent, double maxPositionVolume,
                     long openRiskMagicFilter=0, const string openRiskSymbolFilter="")
   {
      ctx.Reset();
      ctx.accountMode=mode; ctx.basis=basis;
      ctx.equity=AccountInfoDouble(ACCOUNT_EQUITY);
      ctx.balance=AccountInfoDouble(ACCOUNT_BALANCE);
      ctx.dayStartBalance=dayStartBalance>0?dayStartBalance:ctx.balance;
      ctx.remainingDailyDDMoney=remainingDailyDDMoney;
      ctx.remainingMaxDDMoney=remainingMaxDDMoney;
      ctx.commissionPerLot=commissionPerLot;
      ctx.swapEstimatePerLot=swapEstimatePerLot;
      ctx.useSwapInRisk=useSwapInRisk;
      ctx.openRiskMoney=CalcOpenRiskMoney(openRiskMagicFilter, openRiskSymbolFilter);
      ctx.maxPositionVolume=maxPositionVolume;
      ctx.minRiskPercent=minRiskPercent; ctx.maxRiskPercent=maxRiskPercent;
   }

   void Calculate(const MM_TradePlan &plan, const MM_RiskContext &ctx, MM_RiskResult &out)
   {
      out.Reset();
      double basis = BasisAmount(ctx);
      out.basis = (ctx.basis==MM_BASIS_BALANCE_DAY)?"BalanceDay":(ctx.basis==MM_BASIS_ALLOWED_DD?"AllowedDD":"Equity");
      string sym = plan.symbol;

      double slDist = MathAbs(plan.entryPrice - plan.slPrice);
      if(slDist<=0)
      {
         out.valid=false; out.blocked=true;
         out.AddWarn(plan.sizingMode==SIZING_AUTO_RISK ? "NO_SL_BLOCK: auto-risk requires valid SL" : "NO_SL: SL required for risk/R preview");
         return;
      }

      double perLot=0; string err="";
      if(!RiskPerLot(sym, slDist, ctx, perLot, err)){ out.valid=false; out.blocked=true; out.AddWarn(err); return; }

      // DD/aggregate budget (strictest remaining after open exposure)
      double ddRemain=-1;
      if(ctx.remainingDailyDDMoney>0 || ctx.remainingMaxDDMoney>0)
      {
         ddRemain=1e100;
         if(ctx.remainingDailyDDMoney>0) ddRemain=MathMin(ddRemain, ctx.remainingDailyDDMoney);
         if(ctx.remainingMaxDDMoney>0) ddRemain=MathMin(ddRemain, ctx.remainingMaxDDMoney);
      }
      double ddBudgetAfterOpen = (ddRemain>=0) ? (ddRemain - ctx.openRiskMoney) : 1e100;

      double lot=0, riskMoney=0, riskPct=plan.riskValue;
      if(plan.sizingMode==SIZING_MANUAL_LOT)
      {
         lot = plan.lot;
         riskMoney = lot * perLot;
         // enforce aggregate/DD cap on manual lot too (block if exceeds)
         if(ddRemain>=0 && (ctx.openRiskMoney + riskMoney) > ddRemain + 1e-9)
         { out.valid=false; out.blocked=true; out.AddWarn("BLOCK: manual lot exceeds aggregate/DD risk budget"); out.lot=lot; out.riskMoney=riskMoney; return; }
         // enforce risk% budget vs basis aggregate (requested % budget over basis)
         if(basis>0)
         {
            double pctBudgetMoney = basis * (ctx.maxRiskPercent>0?ctx.maxRiskPercent:100.0) / 100.0;
            if(ctx.openRiskMoney + riskMoney > pctBudgetMoney + 1e-9){ out.AddCap("cap:aggregate_risk_budget"); /* warn/block conservative */ }
         }
         if(basis>0) riskPct = (riskMoney / basis) * 100.0; else riskPct=0;
      }
      else
      {
         double reqPct = riskPct;
         if(ctx.maxRiskPercent>0 && reqPct>ctx.maxRiskPercent){ reqPct=ctx.maxRiskPercent; out.AddCap("cap:maxRiskPercent"); }
         if(ctx.minRiskPercent>0 && reqPct>0 && reqPct<ctx.minRiskPercent){ out.AddWarn("below_minRiskPercent"); }
         double requestedMoney = (basis>0)? (basis * reqPct / 100.0) : 0;
         double allowedMoney = requestedMoney;
         // aggregate budget: (open + new) <= requestedMoney? No: total budget by risk% over basis is requestedMoney in isolation;
         // but must also respect (openRisk + newRisk) <= (basis * reqPct/100) when treating as portfolio budget — conservative: cap new so open+new <= requestedMoney
         double portfolioBudget = requestedMoney - ctx.openRiskMoney;
         if(portfolioBudget < allowedMoney){ allowedMoney = portfolioBudget; out.AddCap("cap:aggregate_open_risk"); }
         if(ddBudgetAfterOpen < allowedMoney){ allowedMoney = ddBudgetAfterOpen; out.AddCap("cap:DD_remaining"); }
         if(allowedMoney <= 0){ out.valid=false; out.blocked=true; out.AddWarn("BLOCK: no risk budget after aggregate/DD caps"); return; }
         riskMoney = allowedMoney;
         lot = riskMoney / perLot;
         if(basis>0) riskPct = (riskMoney / basis) * 100.0; else riskPct=0;
      }

      double vmin=SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
      double vmax=SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
      double vstep=SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
      if(ctx.maxPositionVolume>0) vmax=MathMin(vmax, ctx.maxPositionVolume);
      if(vstep<=0) vstep=0.01;
      if(vmax < vmin){ out.valid=false; out.blocked=true; out.AddWarn("BLOCK: symbol volume limits invalid"); return; }

      lot = MathFloor((lot + 1e-12) / vstep) * vstep; // floor to step (never exceed risk)
      int vdig=(int)VolumeDigits(vstep);
      lot = NormalizeDouble(lot, vdig);

      if(lot < vmin)
      {
         out.valid=false; out.blocked=true;
         out.lot=lot; out.riskMoney=lot*perLot; out.riskPercent=(basis>0?(out.riskMoney/basis*100.0):0);
         out.AddWarn("BLOCK: lot below minimum after caps/step");
         return;
      }
      if(lot > vmax){ lot=NormalizeDouble(MathFloor(vmax/vstep)*vstep, vdig); out.AddCap("cap:max_volume"); }

      riskMoney = lot * perLot;
      if(basis>0) riskPct = (riskMoney / basis) * 100.0;

      // final strict checks
      if(ddRemain>=0 && (ctx.openRiskMoney + riskMoney) > ddRemain + 1e-6)
         out.AddWarn("WARN: rounded risk near DD cap");
      if(plan.sizingMode==SIZING_AUTO_RISK && ctx.openRiskMoney + (basis*plan.riskValue/100.0) > 0 && riskMoney <= 0)
      { out.valid=false; out.blocked=true; out.AddWarn("BLOCK: aggregate risk budget exhausted"); return; }

      out.lot = lot;
      out.riskMoney = riskMoney;
      out.riskPercent = riskPct;
      out.rr = ComputeRR(plan);
      out.valid = true;
      out.blocked = false;
   }

   double ComputeRR(const MM_TradePlan &plan)
   {
      double sl=MathAbs(plan.entryPrice-plan.slPrice);
      if(sl<=0 || plan.tpCount<=0) return 0;
      double tp=MathAbs(plan.tpPrice[0]-plan.entryPrice);
      return tp/sl;
   }

   // Convenience: build default context from current account snapshot.
   void BuildDefaultContext(MM_RiskContext &ctx, ENUM_MM_ACCOUNT_MODE mode)
   {
      ENUM_MM_RISK_BASIS b = (mode==ACCOUNT_PROP)?MM_BASIS_ALLOWED_DD:MM_BASIS_EQUITY;
      BuildContext(ctx, mode, b, AccountInfoDouble(ACCOUNT_BALANCE), 0, 0, 0, 0, false, 0.0, 100.0, 0, 0, "");
   }
};

#endif // MM_RISK_ENGINE_MQH

