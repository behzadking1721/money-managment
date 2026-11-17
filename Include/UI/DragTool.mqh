//+------------------------------------------------------------------+
//|                                                     DragTool.mqh |
//|             Chart drag lines for Entry/SL/TP (Phase 4)           |
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
   double slDistPrice;    // geometry relative
   double tp1DistPrice;
   double tp2DistPrice;
   double tp3DistPrice;
   void Reset(){ id="default"; isBuy=true; sizingMode=SIZING_AUTO_RISK; riskValue=1.0; slippagePoints=30; slDistPrice=0; tp1DistPrice=0; tp2DistPrice=0; tp3DistPrice=0; }
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
   double m_entry, m_sl, m_tp1, m_tp2, m_tp3;
   int    m_tpCount;
   bool   m_instabilityWarn;
   double m_lastSpread;
   datetime m_lastPriceTs;
   MM_DragTemplate m_tpl;

   string N(const string s){ return m_prefix+s; }
   void SetHLine(const string name,double price,color clr,int style,int width,bool selectable=true)
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
      if(m_tp1==0) m_tp1 = m_isBuy? m_entry+400*pt : m_entry-400*pt;
      if(m_tpCount>=2 && m_tp2==0) m_tp2 = m_isBuy? m_entry+600*pt : m_entry-600*pt;
      if(m_tpCount>=3 && m_tp3==0) m_tp3 = m_isBuy? m_entry+800*pt : m_entry-800*pt;
      SetHLine(N("Entry"),m_entry, m_isBuy?clrDodgerBlue:clrTomato, STYLE_SOLID, 2, true);
      SetHLine(N("SL"),   m_sl,    clrRed,    STYLE_SOLID, 2, true);
      SetHLine(N("TP1"),  m_tp1,   clrLimeGreen, STYLE_DASH, 1, true);
      if(m_tpCount>=2) SetHLine(N("TP2"),m_tp2,clrGreen,STYLE_DOT,1,true); else if(ObjectFind(m_chart,N("TP2"))>=0) ObjectDelete(m_chart,N("TP2"));
      if(m_tpCount>=3) SetHLine(N("TP3"),m_tp3,clrGreen,STYLE_DOT,1,true); else if(ObjectFind(m_chart,N("TP3"))>=0) ObjectDelete(m_chart,N("TP3"));
   }

public:
   CDragTool(){ m_chart=0; m_prefix="MM_D_"; m_sym=_Symbol; m_active=false; m_ready=false; m_isBuy=true; m_mode=MM_DRAG_AUTO; m_sizingMode=SIZING_AUTO_RISK; m_riskValue=1.0; m_slippage=30; m_rrLock=false; m_entry=0; m_sl=0; m_tp1=0; m_tp2=0; m_tp3=0; m_tpCount=1; m_instabilityWarn=false; m_lastSpread=0; m_lastPriceTs=0; m_tpl.Reset(); }

   void Init(long chart,const string symbol,const string prefix="MM_D_"){ m_chart=chart; m_sym=symbol; m_prefix=prefix; }
   bool Active(){ return m_active; }
   bool Ready(){ return m_active && m_ready; }
   bool IsBuy(){ return m_isBuy; }
   void SetBuy(bool buy){ m_isBuy=buy; if(m_active){ SyncFromLines(); m_entry=0; m_sl=0; m_tp1=0; m_tp2=0; m_tp3=0; EnsureLines(); } }
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
   void SetTpCount(int n){ m_tpCount=MathMax(1,MathMin(3,n)); if(m_active) EnsureLines(); }
   int TpCount(){ return m_tpCount; }
   bool InstabilityWarn(){ return m_instabilityWarn; }

   void Activate(bool buy=true)
   {
      m_active=true; m_ready=true; m_isBuy=buy; m_entry=0; m_sl=0; m_tp1=0; m_tp2=0; m_tp3=0; m_instabilityWarn=false;
      EnsureLines(); ChartRedraw(m_chart);
   }
   void Deactivate(){ m_active=false; m_ready=false; Destroy(); }
   void Clear(){ m_entry=0; m_sl=0; m_tp1=0; m_tp2=0; m_tp3=0; m_instabilityWarn=false; if(m_active){ EnsureLines(); } }

   void Destroy()
   {
      string names[5]={N("Entry"),N("SL"),N("TP1"),N("TP2"),N("TP3")};
      for(int i=0;i<5;i++) if(ObjectFind(m_chart,names[i])>=0) ObjectDelete(m_chart,names[i]);
      ChartRedraw(m_chart);
   }

   void SyncFromLines()
   {
      if(!m_active) return;
      m_entry=GetHLine(N("Entry"),m_entry);
      m_sl=GetHLine(N("SL"),m_sl);
      m_tp1=GetHLine(N("TP1"),m_tp1);
      if(m_tpCount>=2) m_tp2=GetHLine(N("TP2"),m_tp2);
      if(m_tpCount>=3) m_tp3=GetHLine(N("TP3"),m_tp3);
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
         if(m_mode==MM_DRAG_PENDING && !isPending)
         {
            // force pending by nudging interpretation: keep detected as market-zone but caller may warn
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
      plan.tpCount=m_tpCount;
      plan.tpPrice[0]=m_tp1; plan.tpPrice[1]=m_tp2; plan.tpPrice[2]=m_tp3;
      plan.sizingMode=m_sizingMode;
      if(m_sizingMode==SIZING_MANUAL_LOT) plan.lot=m_riskValue; else plan.riskValue=m_riskValue;
      plan.slippagePoints=m_slippage;
      plan.templateId=templateId;
      plan.serverTime=TimeTradeServer();
      return true;
   }

   // Template helpers (geometry + risk/mode/slippage) per frozen spec
   MM_DragTemplate CaptureTemplate(const string id)
   {
      MM_DragTemplate t; t.Reset(); t.id=id; t.isBuy=m_isBuy; t.sizingMode=m_sizingMode; t.riskValue=m_riskValue; t.slippagePoints=m_slippage;
      double e=m_entry;
      t.slDistPrice = e-m_sl; // signed relative
      t.tp1DistPrice = m_tp1-e; t.tp2DistPrice=m_tp2-e; t.tp3DistPrice=m_tp3-e;
      return t;
   }
   void ApplyTemplate(const MM_DragTemplate &t, double entryPrice)
   {
      m_isBuy=t.isBuy; m_sizingMode=t.sizingMode; m_riskValue=t.riskValue; m_slippage=t.slippagePoints;
      m_entry=entryPrice; m_sl = m_entry - t.slDistPrice;
      m_tp1 = m_entry + t.tp1DistPrice; m_tp2 = m_entry + t.tp2DistPrice; m_tp3 = m_entry + t.tp3DistPrice;
      if(m_active) EnsureLines();
   }

   double Entry(){ return m_entry; } double SL(){ return m_sl; } double TP1(){ return m_tp1; }
   double TP2(){ return m_tp2; } double TP3(){ return m_tp3; }
};

#endif // MM_DRAG_TOOL_MQH
