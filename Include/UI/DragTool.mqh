//+------------------------------------------------------------------+
//|                                                     DragTool.mqh |
//|             Chart drag lines for Entry/SL/TP (Phase 4)           |
//|  Extended: optional Multi-TP planning up to MM_MAX_TP_LEVELS     |
//+------------------------------------------------------------------+
#ifndef MM_DRAG_TOOL_MQH
#define MM_DRAG_TOOL_MQH

#include "../Core/Contracts.mqh"
#include "../Core/StopsValidator.mqh"

enum ENUM_MM_DRAG_ORDER_MODE { MM_DRAG_AUTO=0, MM_DRAG_MARKET=1, MM_DRAG_PENDING=2 };

struct MM_DragTemplate
{
   string id;
   bool   isBuy;
   ENUM_MM_SIZING_MODE sizingMode;
   double riskValue;      // percent or lot depending on mode
   int    slippagePoints;
   double slDistPrice;    // geometry relative (entry - sl)
   double tpDistPrice[MM_MAX_TP_LEVELS]; // (tp - entry), indexed 0..N-1
   int    tpCount;
   void Reset()
   {
      id="default"; isBuy=true; sizingMode=SIZING_AUTO_RISK; riskValue=1.0; slippagePoints=30; slDistPrice=0; tpCount=1;
      for(int i=0;i<MM_MAX_TP_LEVELS;i++) tpDistPrice[i]=0;
   }
};

class CDragTool
{
private:
   long   m_chart;
   string m_prefix;
   string m_sym;
   bool   m_active;
   bool   m_ready;
   bool   m_isBuy;
   ENUM_MM_DRAG_ORDER_MODE m_mode;
   ENUM_MM_SIZING_MODE m_sizingMode;
   double m_riskValue; // % or lot
   int    m_slippage;
   bool   m_rrLock;
   double m_entry, m_sl;
   double m_tp[MM_MAX_TP_LEVELS];
   int    m_tpCount;
   bool   m_instabilityWarn;
   double m_lastSpread;
   datetime m_lastPriceTs;
   MM_DragTemplate m_tpl;

   string N(const string s){ return m_prefix+s; }
   string TpName(int i){ return N("TP"+IntegerToString(i+1)); }

   void SetHLine(const string name,double price,color clr,int style,int width,bool selectable=true,const string tooltip="")
   {
      if(ObjectFind(m_chart,name)<0) ObjectCreate(m_chart,name,OBJ_HLINE,0,0,price);
      ObjectSetDouble(m_chart,name,OBJPROP_PRICE,price);
      ObjectSetInteger(m_chart,name,OBJPROP_COLOR,clr);
      ObjectSetInteger(m_chart,name,OBJPROP_STYLE,style);
      ObjectSetInteger(m_chart,name,OBJPROP_WIDTH,width);
      ObjectSetInteger(m_chart,name,OBJPROP_SELECTABLE,selectable);
      ObjectSetInteger(m_chart,name,OBJPROP_SELECTED,selectable);
      ObjectSetInteger(m_chart,name,OBJPROP_BACK,false);
      ObjectSetInteger(m_chart,name,OBJPROP_HIDDEN,true);
      if(tooltip!="") ObjectSetString(m_chart,name,OBJPROP_TOOLTIP,tooltip);
   }
   double GetHLine(const string name,double defv)
   {
      if(ObjectFind(m_chart,name)<0) return defv;
      return ObjectGetDouble(m_chart,name,OBJPROP_PRICE);
   }
   void EnsureLines()
   {
      double ask=SymbolInfoDouble(m_sym,SYMBOL_ASK), bid=SymbolInfoDouble(m_sym,SYMBOL_BID);
      double pt=SymbolInfoDouble(m_sym,SYMBOL_POINT);
      if(m_entry==0) m_entry = m_isBuy?ask:bid;
      if(m_sl==0) m_sl = m_isBuy? m_entry-200*pt : m_entry+200*pt;
      for(int i=0;i<MM_MAX_TP_LEVELS;i++)
      {
         if(i < m_tpCount && m_tp[i]==0)
         {
            double step = 200.0 * (i+2); // TP1:+400, TP2:+600, ...
            m_tp[i] = m_isBuy? m_entry + step*pt : m_entry - step*pt;
         }
      }
      string dir = m_isBuy?"BUY":"SELL";
      SetHLine(N("Entry"),m_entry, m_isBuy?clrDodgerBlue:clrTomato, STYLE_SOLID, 2, true, dir+" Entry");
      SetHLine(N("SL"),   m_sl,    clrRed,    STYLE_SOLID, 2, true, "Stop Loss");
      for(int i=0;i<MM_MAX_TP_LEVELS;i++)
      {
         string nm=TpName(i);
         if(i < m_tpCount)
         {
            color clr = (i==0)?clrLimeGreen:clrGreen;
            int style = (i==0)?STYLE_DASH:STYLE_DOT;
            SetHLine(nm, m_tp[i], clr, style, 1, true, "Take Profit "+IntegerToString(i+1));
         }
         else if(ObjectFind(m_chart,nm)>=0) ObjectDelete(m_chart,nm);
      }
   }

public:
   CDragTool(){ m_chart=0; m_prefix="MM_D_"; m_sym=_Symbol; m_active=false; m_ready=false; m_isBuy=true; m_mode=MM_DRAG_AUTO; m_sizingMode=SIZING_AUTO_RISK; m_riskValue=1.0; m_slippage=30; m_rrLock=false; m_entry=0; m_sl=0; m_tpCount=1; m_instabilityWarn=false; m_lastSpread=0; m_lastPriceTs=0; m_tpl.Reset(); for(int i=0;i<MM_MAX_TP_LEVELS;i++) m_tp[i]=0; }

   void Init(long chart,const string symbol,const string prefix="MM_D_"){ m_chart=chart; m_sym=symbol; m_prefix=prefix; }
   bool Active(){ return m_active; }
   bool Ready(){ return m_active && m_ready; }
   bool IsBuy(){ return m_isBuy; }
   void SetBuy(bool buy){ m_isBuy=buy; if(m_active){ SyncFromLines(); m_entry=0; m_sl=0; for(int i=0;i<MM_MAX_TP_LEVELS;i++) m_tp[i]=0; EnsureLines(); } }
   void Reverse(){ SetBuy(!m_isBuy); }
   void SetMode(ENUM_MM_DRAG_ORDER_MODE m){ m_mode=m; }
   ENUM_MM_DRAG_ORDER_MODE Mode(){ return m_mode; }
   void SetSizingMode(ENUM_MM_SIZING_MODE m){ m_sizingMode=m; }
   ENUM_MM_SIZING_MODE SizingMode(){ return m_sizingMode; }
   void SetRiskValue(double v){ m_riskValue=v; }
   double RiskValue(){ return m_riskValue; }
   void AdjustRisk(double deltaPct){ m_riskValue=MathMax(0.01, m_riskValue+deltaPct); }
   void SetSlippage(int pts){ m_slippage=pts; }
   int Slippage(){ return m_slippage; }
   void SetTpCount(int n)
   {
      m_tpCount=MathMax(1,MathMin(MM_MAX_TP_LEVELS,n));
      if(m_active) EnsureLines();
   }
   int TpCount(){ return m_tpCount; }
   bool InstabilityWarn(){ return m_instabilityWarn; }

   void Activate(bool buy=true)
   {
      m_active=true; m_ready=true; m_isBuy=buy; m_entry=0; m_sl=0; for(int i=0;i<MM_MAX_TP_LEVELS;i++) m_tp[i]=0; m_instabilityWarn=false;
      EnsureLines(); ChartRedraw(m_chart);
   }
   void Deactivate(){ m_active=false; m_ready=false; Destroy(); }
   void Clear(){ m_entry=0; m_sl=0; for(int i=0;i<MM_MAX_TP_LEVELS;i++) m_tp[i]=0; m_instabilityWarn=false; if(m_active){ EnsureLines(); } }

   void Destroy()
   {
      if(ObjectFind(m_chart,N("Entry"))>=0) ObjectDelete(m_chart,N("Entry"));
      if(ObjectFind(m_chart,N("SL"))>=0) ObjectDelete(m_chart,N("SL"));
      for(int i=0;i<MM_MAX_TP_LEVELS;i++){ string nm=TpName(i); if(ObjectFind(m_chart,nm)>=0) ObjectDelete(m_chart,nm); }
      ChartRedraw(m_chart);
   }

   void SyncFromLines()
   {
      if(!m_active) return;
      m_entry=GetHLine(N("Entry"),m_entry);
      m_sl=GetHLine(N("SL"),m_sl);
      for(int i=0;i<m_tpCount;i++) m_tp[i]=GetHLine(TpName(i),m_tp[i]);
   }

   // Detect market vs pending and resolve order type
   void ResolveOrder(bool &isPending, ENUM_ORDER_TYPE &otype)
   {
      double ask=SymbolInfoDouble(m_sym,SYMBOL_ASK), bid=SymbolInfoDouble(m_sym,SYMBOL_BID);
      double pt=SymbolInfoDouble(m_sym,SYMBOL_POINT);
      double tol = MathMax(2*pt, (ask-bid));
      isPending=false; otype = m_isBuy?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
      if(m_mode==MM_DRAG_MARKET){ isPending=false; return; }
      if(m_mode==MM_DRAG_PENDING || m_mode==MM_DRAG_AUTO)
      {
         if(m_isBuy)
         {
            if(m_entry < bid - tol){ isPending=true; otype=ORDER_TYPE_BUY_LIMIT; }
            else if(m_entry > ask + tol){ isPending=true; otype=ORDER_TYPE_BUY_STOP; }
            else { isPending=false; otype=ORDER_TYPE_BUY; }
         }
         else
         {
            if(m_entry > ask + tol){ isPending=true; otype=ORDER_TYPE_SELL_LIMIT; }
            else if(m_entry < bid - tol){ isPending=true; otype=ORDER_TYPE_SELL_STOP; }
            else { isPending=false; otype=ORDER_TYPE_SELL; }
         }
      }
   }

   void CheckInstability()
   {
      double ask=SymbolInfoDouble(m_sym,SYMBOL_ASK), bid=SymbolInfoDouble(m_sym,SYMBOL_BID);
      double pt=SymbolInfoDouble(m_sym,SYMBOL_POINT); if(pt<=0) return;
      double sp=(ask-bid)/pt;
      m_instabilityWarn=false;
      if(m_lastSpread>0 && sp > m_lastSpread*1.8 && sp-m_lastSpread > 5) m_instabilityWarn=true; // spread jump
      m_lastSpread=sp;
   }

   // Call on chart events; returns true if event consumed/related
   bool OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
   {
      if(!m_active) return false;
      if(id==CHARTEVENT_OBJECT_DRAG)
      {
         if(StringFind(sparam,m_prefix)==0)
         {
            SyncFromLines();
            CheckInstability();
            ChartRedraw(m_chart);
            return true;
         }
      }
      if(id==CHARTEVENT_OBJECT_CHANGE)
      {
         if(StringFind(sparam,m_prefix)==0){ SyncFromLines(); return true; }
      }
      return false;
   }

   void OnTickUpdate(){ if(m_active){ SyncFromLines(); CheckInstability(); } }

   bool BuildPlan(MM_TradePlan &plan, const string templateId="")
   {
      plan.Reset();
      if(!m_active) return false;
      SyncFromLines();
      bool pending=false; ENUM_ORDER_TYPE ot=ORDER_TYPE_BUY; ResolveOrder(pending, ot);
      plan.symbol=m_sym; plan.side=m_isBuy?POSITION_TYPE_BUY:POSITION_TYPE_SELL;
      plan.isPending=pending; plan.orderType=ot;
      plan.entryPrice=m_entry; plan.slPrice=m_sl;
      plan.tpCount = MathMax(1, MathMin(MM_MAX_TP_LEVELS, m_tpCount));
      for(int i=0;i<MM_MAX_TP_LEVELS;i++) plan.tpPrice[i]=0;
      for(int i=0;i<plan.tpCount;i++) plan.tpPrice[i]=m_tp[i];
      plan.sizingMode=m_sizingMode;
      if(m_sizingMode==SIZING_MANUAL_LOT) plan.lot=m_riskValue; else plan.riskValue=m_riskValue;
      plan.slippagePoints=m_slippage;
      plan.templateId=templateId;
      plan.serverTime=TimeTradeServer();
      return true;
   }

   // Template helpers (geometry + risk/mode/slippage)
   MM_DragTemplate CaptureTemplate(const string id)
   {
      MM_DragTemplate t; t.Reset(); t.id=id; t.isBuy=m_isBuy; t.sizingMode=m_sizingMode; t.riskValue=m_riskValue; t.slippagePoints=m_slippage;
      double e=m_entry;
      t.slDistPrice = e-m_sl; // signed relative
      t.tpCount = m_tpCount;
      for(int i=0;i<MM_MAX_TP_LEVELS;i++) t.tpDistPrice[i] = (i<m_tpCount)?(m_tp[i]-e):0.0;
      return t;
   }
   void ApplyTemplate(const MM_DragTemplate &t, double entryPrice)
   {
      m_isBuy=t.isBuy; m_sizingMode=t.sizingMode; m_riskValue=t.riskValue; m_slippage=t.slippagePoints;
      m_entry=entryPrice; m_sl = m_entry - t.slDistPrice;
      m_tpCount = MathMax(1, MathMin(MM_MAX_TP_LEVELS, t.tpCount>0?t.tpCount:1));
      for(int i=0;i<MM_MAX_TP_LEVELS;i++) m_tp[i] = (i<m_tpCount && t.tpDistPrice[i]!=0.0) ? (m_entry + t.tpDistPrice[i]) : 0.0;
      if(m_active) EnsureLines();
   }

   double Entry(){ return m_entry; } double SL(){ return m_sl; }
   double TP(int i){ return (i>=0 && i<MM_MAX_TP_LEVELS)?m_tp[i]:0.0; }
   double TP1(){ return m_tp[0]; } double TP2(){ return m_tp[1]; } double TP3(){ return m_tp[2]; }
   double TP4(){ return m_tp[3]; } double TP5(){ return m_tp[4]; }
};

#endif // MM_DRAG_TOOL_MQH
