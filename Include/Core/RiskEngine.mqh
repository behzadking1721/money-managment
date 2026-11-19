//+------------------------------------------------------------------+
//|                                                  RiskEngine.mqh  |
//|      Phase 2/2.2: lot/risk sizing, caps, margin, clear results  |
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

   double NormalizeVolume(double vol, double step)
   {
      if(step<=0) step=0.01;
      int vdig=(int)VolumeDigits(step);
      double v = MathFloor((vol + 1e-12) / step) * step; // floor to step (never exceed budget)
      return NormalizeDouble(v, vdig);
   }

   bool ResolveOrderTypeAndPrice(const MM_TradePlan &plan, ENUM_ORDER_TYPE &orderType, double &marginPrice)
   {
      bool isBuy = (plan.side==POSITION_TYPE_BUY);
      double ask=SymbolInfoDouble(plan.symbol,SYMBOL_ASK);
      double bid=SymbolInfoDouble(plan.symbol,SYMBOL_BID);
      if(plan.isPending)
      {
         orderType = plan.orderType;
         marginPrice = plan.entryPrice;
         return (marginPrice>0);
      }
      orderType = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      marginPrice = isBuy ? ask : bid;
      if(marginPrice<=0) marginPrice = plan.entryPrice; // fallback
      return (marginPrice>0);
   }

   bool CalcMargin(const string symbol, ENUM_ORDER_TYPE orderType, double volume, double price, double &margin, string &err)
   {
      margin=0.0; err="";
      if(volume<=0 || price<=0){ err="MARGIN_CALC_FAIL: invalid volume/price"; return false; }
      if(!OrderCalcMargin(orderType, symbol, volume, price, margin))
      { err="MARGIN_CALC_FAIL: OrderCalcMargin failed"; return false; }
      if(margin<0) margin=0.0;
      return true;
   }

   // Reduce lot by volume step until margin fits free margin. Never increases lot, never returns below vmin.
   bool CapLotByMargin(const string symbol, ENUM_ORDER_TYPE orderType, double price,
                       double &lot, double vmin, double vstep, double freeMargin,
                       bool &capped, string &err, double &requiredMargin)
   {
      capped=false; err=""; requiredMargin=0.0;
      if(freeMargin < 0) freeMargin = 0.0;
      string mErr="";
      if(CalcMargin(symbol, orderType, lot, price, requiredMargin, mErr))
      {
         if(requiredMargin <= freeMargin + 1e-9) return true;
      }
      else { err=mErr; return false; }

      capped=true;
      double cur = lot;
      while(cur >= vmin - 1e-12)
      {
         cur = NormalizeVolume(cur - vstep, vstep);
         if(cur < vmin - 1e-12) break;
         if(!CalcMargin(symbol, orderType, cur, price, requiredMargin, mErr))
         { err=mErr; return false; }
         if(requiredMargin <= freeMargin + 1e-9){ lot = cur; return true; }
      }
      err="NO_MONEY: insufficient free margin for minimum volume";
      return false;
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
      { err="INVALID_SYMBOL_OR_SL: symbol specs unavailable or invalid SL distance"; return false; }
      double slPoints = slDistancePrice / point;
      double slMoney = (slPoints * point / tickSize) * tickValue;
      double extra = ctx.commissionPerLot;
      if(ctx.useSwapInRisk) extra += ctx.swapEstimatePerLot;
      perLot = slMoney + extra;
      if(perLot<=0){ err="INVALID_RISK_PER_LOT: computed per-lot risk is invalid"; return false; }
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
         double point=SymbolInfoDouble(sym,SYMBOL_POINT);
         double tickValue=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE);
         double tickSize=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_SIZE);
         if(point<=0 || tickValue<=0 || tickSize<=0 || vol<=0) continue;
         double slDist = MathAbs(open - sl);
         if(sl<=0 || slDist<=0) continue; // no SL: unknown risk not added here
         double perLot = (slDist / tickSize) * tickValue;
         if(perLot>0) total += perLot * vol;
      }
      return total;
   }

   // Fill context from live account + computed open risk. DD remaining values must be supplied by caller.
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
         out.valid=false; out.blocked=true; out.lot=0; out.riskMoney=0; out.riskPercent=0;
         out.AddWarn(plan.sizingMode==SIZING_AUTO_RISK ? "NO_SL: auto-risk requires valid SL distance" : "NO_SL: SL required for risk calculation/preview");
         return;
      }

      double vmin=SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
      double vmax=SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
      double vstep=SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
      if(ctx.maxPositionVolume>0 && vmax>0) vmax=MathMin(vmax, ctx.maxPositionVolume);
      if(vstep<=0) vstep=0.01;
      if(vmin<=0 || vmax<=0 || vmax < vmin - 1e-12)
      {
         out.valid=false; out.blocked=true;
         out.AddWarn("INVALID_SYMBOL_SPECS: symbol volume limits invalid/unavailable");
         return;
      }

      double perLot=0; string err="";
      if(!RiskPerLot(sym, slDist, ctx, perLot, err))
      { out.valid=false; out.blocked=true; out.AddWarn(err); return; }

      ENUM_ORDER_TYPE marginOrderType = ORDER_TYPE_BUY;
      double marginPrice = plan.entryPrice;
      if(!ResolveOrderTypeAndPrice(plan, marginOrderType, marginPrice) || marginPrice<=0)
      {
         out.valid=false; out.blocked=true;
         out.AddWarn("INVALID_PRICE: unable to resolve price/order type for margin-aware sizing");
         return;
      }

      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(freeMargin < 0) freeMargin = 0.0;

      double ddRemain=-1;
      if(ctx.remainingDailyDDMoney>0 || ctx.remainingMaxDDMoney>0)
      {
         ddRemain=1e100;
         if(ctx.remainingDailyDDMoney>0) ddRemain=MathMin(ddRemain, ctx.remainingDailyDDMoney);
         if(ctx.remainingMaxDDMoney>0) ddRemain=MathMin(ddRemain, ctx.remainingMaxDDMoney);
      }
      double ddBudgetAfterOpen = (ddRemain>=0) ? (ddRemain - ctx.openRiskMoney) : 1e100;

      double lot=0, riskMoney=0;
      double requestedRiskMoney=0.0, requestedRiskPct=0.0;

      if(plan.sizingMode==SIZING_MANUAL_LOT)
      {
         requestedRiskMoney = plan.lot * perLot;
         requestedRiskPct = (basis>0)?(requestedRiskMoney / basis * 100.0):0.0;
         out.AddCap("requestedRiskPct="+DoubleToString(requestedRiskPct,4)+";requestedRiskMoney="+DoubleToString(requestedRiskMoney,2));

         lot = NormalizeVolume(plan.lot, vstep);
         if(lot > vmax + 1e-12){ lot = NormalizeVolume(vmax, vstep); out.AddCap("cap:max_volume"); }
         if(lot < vmin - 1e-12)
         {
            out.valid=false; out.blocked=true; out.lot=lot; out.riskMoney=lot*perLot;
            out.riskPercent=(basis>0 && out.riskMoney>0)?(out.riskMoney/basis*100.0):0.0;
            out.AddWarn("INVALID_VOLUME: manual lot below symbol minimum volume");
            return;
         }

         riskMoney = lot * perLot;
         if(ddRemain>=0 && (ctx.openRiskMoney + riskMoney) > ddRemain + 1e-9)
         {
            out.valid=false; out.blocked=true; out.lot=lot; out.riskMoney=riskMoney;
            out.riskPercent=(basis>0)?(riskMoney/basis*100.0):0.0;
            out.AddCap("cap:DD_remaining");
            out.AddWarn("BLOCK: manual lot exceeds aggregate/DD risk budget");
            return;
         }
         if(basis>0)
         {
            double pctBudgetMoney = basis * (ctx.maxRiskPercent>0?ctx.maxRiskPercent:100.0) / 100.0;
            if(ctx.openRiskMoney + riskMoney > pctBudgetMoney + 1e-9)
            {
               out.valid=false; out.blocked=true; out.lot=lot; out.riskMoney=riskMoney;
               out.riskPercent=(basis>0)?(riskMoney/basis*100.0):0.0;
               out.AddCap("cap:aggregate_risk_budget");
               out.AddWarn("BLOCK: manual lot exceeds aggregate risk percent budget");
               return;
            }
         }

         double reqMargin=0.0; bool marginCapped=false; string mErr="";
         if(!CapLotByMargin(sym, marginOrderType, marginPrice, lot, vmin, vstep, freeMargin, marginCapped, mErr, reqMargin))
         {
            out.valid=false; out.blocked=true;
            out.lot = (lot < vmin - 1e-12) ? 0 : NormalizeVolume(lot, vstep);
            out.riskMoney = out.lot*perLot;
            out.riskPercent = (basis>0 && out.riskMoney>0)?(out.riskMoney/basis*100.0):0.0;
            out.AddCap("cap:margin_free");
            out.AddWarn(mErr==""?"NO_MONEY: insufficient free margin for minimum volume":mErr);
            return;
         }
         if(marginCapped) out.AddCap("cap:margin_free");
      }
      else
      {
         requestedRiskPct = plan.riskValue;
         double reqPct = requestedRiskPct;
         if(ctx.maxRiskPercent>0 && reqPct > ctx.maxRiskPercent){ reqPct = ctx.maxRiskPercent; out.AddCap("cap:maxRiskPercent"); }
         if(ctx.minRiskPercent>0 && reqPct>0 && reqPct < ctx.minRiskPercent)
            out.AddWarn("below_minRiskPercent: requested risk percent below configured minimum");

         requestedRiskMoney = (basis>0)? (basis * requestedRiskPct / 100.0) : 0.0;
         double clampedRequestedMoney = (basis>0)? (basis * reqPct / 100.0) : 0.0;
         out.AddCap("requestedRiskPct="+DoubleToString(requestedRiskPct,4)+";requestedRiskMoney="+DoubleToString(requestedRiskMoney,2));

         double allowedMoney = clampedRequestedMoney;
         double portfolioBudget = clampedRequestedMoney - ctx.openRiskMoney;
         if(portfolioBudget < allowedMoney){ allowedMoney = portfolioBudget; out.AddCap("cap:aggregate_open_risk"); }
         if(ddBudgetAfterOpen < allowedMoney){ allowedMoney = ddBudgetAfterOpen; out.AddCap("cap:DD_remaining"); }
         if(allowedMoney <= 0 || !MathIsValidNumber(allowedMoney))
         {
            out.valid=false; out.blocked=true; out.lot=0; out.riskMoney=0; out.riskPercent=0;
            out.AddWarn("BLOCK: no risk budget after aggregate/DD caps");
            return;
         }

         riskMoney = allowedMoney;
         lot = (perLot>0) ? (riskMoney / perLot) : 0.0;
         lot = NormalizeVolume(lot, vstep);
         if(lot > vmax + 1e-12){ lot = NormalizeVolume(vmax, vstep); out.AddCap("cap:max_volume"); }
         if(lot < vmin - 1e-12)
         {
            out.valid=false; out.blocked=true; out.lot=lot; out.riskMoney=lot*perLot;
            out.riskPercent=(basis>0 && out.riskMoney>0)?(out.riskMoney/basis*100.0):0.0;
            out.AddWarn("BLOCK: lot below minimum after risk/aggregate/DD/step caps");
            return;
         }

         double reqMargin=0.0; bool marginCapped=false; string mErr="";
         if(!CapLotByMargin(sym, marginOrderType, marginPrice, lot, vmin, vstep, freeMargin, marginCapped, mErr, reqMargin))
         {
            out.valid=false; out.blocked=true;
            out.lot = (lot < vmin - 1e-12) ? 0 : NormalizeVolume(lot, vstep);
            out.riskMoney = out.lot*perLot;
            out.riskPercent=(basis>0 && out.riskMoney>0)?(out.riskMoney/basis*100.0):0.0;
            out.AddCap("cap:margin_free");
            out.AddWarn(mErr==""?"NO_MONEY: insufficient free margin for minimum volume":mErr);
            return;
         }
         if(marginCapped) out.AddCap("cap:margin_free");
      }

      // final normalization and safety: never increase volume
      lot = NormalizeVolume(lot, vstep);
      if(lot > vmax + 1e-12){ lot = NormalizeVolume(vmax, vstep); out.AddCap("cap:max_volume"); }
      if(lot < vmin - 1e-12)
      {
         out.valid=false; out.blocked=true; out.lot=lot; out.riskMoney=lot*perLot;
         out.riskPercent=(basis>0 && out.riskMoney>0)?(out.riskMoney/basis*100.0):0.0;
         out.AddWarn("BLOCK: final lot below symbol minimum volume");
         return;
      }

      // verify final selected volume again using OrderCalcMargin (required)
      double finalMargin=0.0; string fmErr="";
      if(!CalcMargin(sym, marginOrderType, lot, marginPrice, finalMargin, fmErr))
      {
         out.valid=false; out.blocked=true; out.lot=lot; out.riskMoney=lot*perLot;
         out.riskPercent=(basis>0)?(out.riskMoney/basis*100.0):0.0;
         out.AddWarn(fmErr==""?"MARGIN_CALC_FAIL: OrderCalcMargin failed for final volume":fmErr);
         return;
      }
      if(finalMargin > freeMargin + 1e-9)
      {
         bool mc=false; string me=""; double adjMargin=0.0;
         if(!CapLotByMargin(sym, marginOrderType, marginPrice, lot, vmin, vstep, freeMargin, mc, me, adjMargin) || lot < vmin - 1e-12)
         {
            out.valid=false; out.blocked=true;
            out.lot = (lot < vmin - 1e-12) ? 0 : NormalizeVolume(lot, vstep);
            out.riskMoney = out.lot*perLot;
            out.riskPercent=(basis>0 && out.riskMoney>0)?(out.riskMoney/basis*100.0):0.0;
            out.AddCap("cap:margin_free");
            out.AddWarn(me==""?"NO_MONEY: insufficient free margin for final volume":me);
            return;
         }
         out.AddCap("cap:margin_free");
      }

      riskMoney = lot * perLot;
      double finalRiskPct = (basis>0) ? (riskMoney / basis * 100.0) : 0.0;

      if(ddRemain>=0 && (ctx.openRiskMoney + riskMoney) > ddRemain + 1e-6)
         out.AddWarn("WARN: final risk near DD cap after rounding");

      out.lot = lot;
      out.riskMoney = riskMoney;
      out.riskPercent = finalRiskPct;
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
