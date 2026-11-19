//+------------------------------------------------------------------+
//|                                               PreviewOverlay.mqh |
//|          Floating live preview (lot/risk/RR/guards) (Phase 4)    |
//+------------------------------------------------------------------+
#ifndef MM_PREVIEW_OVERLAY_MQH
#define MM_PREVIEW_OVERLAY_MQH

#include "UiStrings.mqh"
#include "DragTool.mqh"
#include "../Core/RiskEngine.mqh"
#include "../Core/StopsValidator.mqh"
#include "../Core/ExecutionPolicy.mqh"
#include "../Guards/GuardEngine.mqh"

class CPreviewOverlay
{
private:
   long   m_chart;
   string m_name;
   bool   m_visible;
   MM_RiskResult m_lastRisk;
   MM_GuardReport m_lastGuards;

   void Ensure()
   {
      if(ObjectFind(m_chart,m_name)<0)
      {
         ObjectCreate(m_chart,m_name,OBJ_LABEL,0,0,0);
         ObjectSetInteger(m_chart,m_name,OBJPROP_CORNER,CORNER_RIGHT_UPPER);
         ObjectSetInteger(m_chart,m_name,OBJPROP_ANCHOR,ANCHOR_RIGHT_UPPER);
         ObjectSetInteger(m_chart,m_name,OBJPROP_SELECTABLE,false);
         ObjectSetInteger(m_chart,m_name,OBJPROP_HIDDEN,true);
         ObjectSetInteger(m_chart,m_name,OBJPROP_FONTSIZE,9);
         ObjectSetString(m_chart,m_name,OBJPROP_FONT,"Consolas");
      }
   }

public:
   CPreviewOverlay(){ m_chart=0; m_name="MM_Preview"; m_visible=true; m_lastRisk.Reset(); m_lastGuards.Reset(); }
   void Init(long chart,const string name){ m_chart=chart; m_name=name; }
   void SetVisible(bool v){ m_visible=v; if(ObjectFind(m_chart,m_name)>=0) ObjectSetInteger(m_chart,m_name,OBJPROP_TIMEFRAMES,v?OBJ_ALL_PERIODS:OBJ_NO_PERIODS); }
   MM_RiskResult LastRisk(){ return m_lastRisk; }
   MM_GuardReport LastGuards(){ return m_lastGuards; }

   void Update(CDragTool &drag, CRiskEngine &riskEng, CStopsValidator &stops, CGuardEngine &guards,
               MM_RiskContext &ctx, MM_GuardConfig &gcfg, CUiStrings &ui)
   {
      if(!drag.Active()){ Destroy(); return; }
      Ensure();
      MM_TradePlan plan; if(!drag.BuildPlan(plan)){ Destroy(); return; }

      // compute risk
      riskEng.Calculate(plan, ctx, m_lastRisk);
      plan.lot = m_lastRisk.lot>0?m_lastRisk.lot:plan.lot;

      // stops/margin quick check
      MM_StopsCheck chk; chk.Reset(); bool stopsOk = stops.ValidatePlan(plan, chk);

      // guards preview (no sink side-effects)
      guards.Preview(plan, gcfg, m_lastGuards);

      bool pending=false; ENUM_ORDER_TYPE ot=ORDER_TYPE_BUY; drag.ResolveOrder(pending, ot);
      string dir = drag.IsBuy()?ui.S_Buy():ui.S_Sell();
      string kind = pending?ui.S_Pending():ui.S_Market();
      double ask=SymbolInfoDouble(plan.symbol,SYMBOL_ASK), bid=SymbolInfoDouble(plan.symbol,SYMBOL_BID);
      double pt=SymbolInfoDouble(plan.symbol,SYMBOL_POINT); double sp = (pt>0)?(ask-bid)/pt:0;

      string status = ui.S_Ready();
      color bg = clrDarkSlateGray;
      if(!m_lastRisk.valid || m_lastRisk.blocked || !stopsOk || !m_lastGuards.allowed){ status=ui.S_Blocked(); bg=clrMaroon; }
      else if(m_lastGuards.hasWarn || chk.warnCount>0 || drag.InstabilityWarn()){ status=ui.S_Warn(); bg=clrOlive; }

      string txt = " "+status+"  "+dir+" "+kind+"\n";
      txt += " "+ui.S_Entry()+": "+DoubleToString(plan.entryPrice,(int)SymbolInfoInteger(plan.symbol,SYMBOL_DIGITS))+"\n";
      txt += " "+ui.S_SL()+": "+DoubleToString(plan.slPrice,(int)SymbolInfoInteger(plan.symbol,SYMBOL_DIGITS));
      if(plan.tpCount <= 1)
         txt += "  "+ui.S_TP()+": "+(plan.tpCount>0?DoubleToString(plan.tpPrice[0],(int)SymbolInfoInteger(plan.symbol,SYMBOL_DIGITS)):"-")+"\n";
      else
      {
         txt += "  TP("+IntegerToString(plan.tpCount)+"):";
         for(int ti=0; ti<plan.tpCount; ti++) txt += " "+DoubleToString(plan.tpPrice[ti],(int)SymbolInfoInteger(plan.symbol,SYMBOL_DIGITS));
         txt += "\n";
      }
      txt += " "+ui.S_Lot()+": "+DoubleToString(m_lastRisk.lot,2)+"  "+ui.S_Risk()+": "+DoubleToString(m_lastRisk.riskPercent,2)+"% ($"+DoubleToString(m_lastRisk.riskMoney,2)+")\n";
      txt += " "+ui.S_RR()+": "+DoubleToString(m_lastRisk.rr,2)+"  "+ui.S_Spread()+": "+DoubleToString(sp,1)+"\n";

      // reasons/warns (compact)
      if(!m_lastRisk.valid && m_lastRisk.warningsCount>0) txt += " !"+m_lastRisk.warnings[0]+"\n";
      if(!stopsOk) txt += " !"+chk.reasonCode+"\n";
      if(m_lastGuards.hasBlock) txt += " !"+m_lastGuards.firstBlock.reasonCode+"\n";
      else if(m_lastGuards.hasWarn)
      {
         for(int i=0;i<m_lastGuards.count;i++) if(m_lastGuards.results[i].decision==GUARD_WARN){ txt += " ~"+m_lastGuards.results[i].reasonCode+"\n"; break; }
      }
      if(drag.InstabilityWarn()) txt += " ~"+ui.T("Spread/price jump","پرش اسپرد/قیمت")+"\n";
      if(m_lastGuards.hasBlock || !m_lastRisk.valid || !stopsOk) txt += " "+ui.T("Send blocked","ارسال مسدود")+"\n";

      ObjectSetInteger(m_chart,m_name,OBJPROP_XDISTANCE,12);
      ObjectSetInteger(m_chart,m_name,OBJPROP_YDISTANCE,28);
      ObjectSetInteger(m_chart,m_name,OBJPROP_BGCOLOR,bg);
      ObjectSetInteger(m_chart,m_name,OBJPROP_COLOR,clrWhite);
      ObjectSetString(m_chart,m_name,OBJPROP_TEXT,txt);
      SetVisible(m_visible);
   }

   void Destroy(){ if(ObjectFind(m_chart,m_name)>=0) ObjectDelete(m_chart,m_name); }
};

#endif // MM_PREVIEW_OVERLAY_MQH
