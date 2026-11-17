#ifndef MM_POSITION_DRAG_TOOL_MQH
#define MM_POSITION_DRAG_TOOL_MQH

#include "../Core/Contracts.mqh"
#include <Trade/Trade.mqh>

struct MM_PosDragState
{
   ulong  ticket;
   string symbol;
   bool   isBuy;
   double openPrice;
   double sl;
   double tp;
   double volume;
   bool   active;
   bool   dirty;
   void Reset(){ ticket=0; symbol=""; isBuy=true; openPrice=0; sl=0; tp=0; volume=0; active=false; dirty=false; }
};

class CPositionDragTool
{
private:
   long   m_chart;
   string m_pfx;
   CTrade m_trade;
   MM_PosDragState m_pos;
   bool   m_optInMulti;
   bool   m_pendingApply;

   string N(const string s){ return m_pfx+s; }
   void SetHLine(const string name,double price,color clr,int style,int width)
   {
      if(price<=0){ if(ObjectFind(m_chart,name)>=0) ObjectDelete(m_chart,name); return; }
      if(ObjectFind(m_chart,name)<0) ObjectCreate(m_chart,name,OBJ_HLINE,0,0,price);
      ObjectSetDouble(m_chart,name,OBJPROP_PRICE,price);
      ObjectSetInteger(m_chart,name,OBJPROP_COLOR,clr);
      ObjectSetInteger(m_chart,name,OBJPROP_STYLE,style);
      ObjectSetInteger(m_chart,name,OBJPROP_WIDTH,width);
      ObjectSetInteger(m_chart,name,OBJPROP_SELECTABLE,true);
      ObjectSetInteger(m_chart,name,OBJPROP_SELECTED,false);
      ObjectSetInteger(m_chart,name,OBJPROP_BACK,false);
      ObjectSetInteger(m_chart,name,OBJPROP_HIDDEN,true);
   }
   double GetHLine(const string name,double defv)
   { if(ObjectFind(m_chart,name)<0) return defv; return ObjectGetDouble(m_chart,name,OBJPROP_PRICE); }

public:
   CPositionDragTool(){ m_chart=0; m_pfx="MM_PD_"; m_optInMulti=false; m_pendingApply=false; m_pos.Reset(); }

   void Init(long chart,long magic=0,const string prefix="MM_PD_")
   {
      m_chart=chart; m_pfx=prefix; if(magic!=0) m_trade.SetExpertMagicNumber(magic);
   }
   bool Active(){ return m_pos.active; }
   ulong Ticket(){ return m_pos.ticket; }
   bool MultiOptIn(){ return m_optInMulti; }
   void SetMultiOptIn(bool v){ m_optInMulti=v; }
   MM_PosDragState State(){ return m_pos; }

   bool SelectTicket(ulong ticket)
   {
      Clear();
      if(!PositionSelectByTicket(ticket)) return false;
      m_pos.ticket=ticket;
      m_pos.symbol=PositionGetString(POSITION_SYMBOL);
      m_pos.isBuy=((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
      m_pos.openPrice=PositionGetDouble(POSITION_PRICE_OPEN);
      m_pos.sl=PositionGetDouble(POSITION_SL);
      m_pos.tp=PositionGetDouble(POSITION_TP);
      m_pos.volume=PositionGetDouble(POSITION_VOLUME);
      m_pos.active=true; m_pos.dirty=false; m_pendingApply=false;
      SyncLinesFromState();
      return true;
   }

   bool SelectCurrent(const string symbol="", long magic=0)
   {
      for(int i=0;i<PositionsTotal();i++)
      {
         ulong t=PositionGetTicket(i); if(t==0) continue;
         if(symbol!="" && PositionGetString(POSITION_SYMBOL)!=symbol) continue;
         if(magic!=0 && (long)PositionGetInteger(POSITION_MAGIC)!=magic) continue;
         return SelectTicket(t);
      }
      return false;
   }

   void SyncLinesFromState()
   {
      if(!m_pos.active) return;
      SetHLine(N("SL"), m_pos.sl, clrOrangeRed, STYLE_SOLID, 2);
      SetHLine(N("TP"), m_pos.tp, clrMediumSeaGreen, STYLE_SOLID, 2);
      ChartRedraw(m_chart);
   }

   void SyncFromServer()
   {
      if(!m_pos.active) return;
      if(!PositionSelectByTicket(m_pos.ticket)){ Clear(); return; }
      double sl=PositionGetDouble(POSITION_SL), tp=PositionGetDouble(POSITION_TP);
      double eps=SymbolInfoDouble(m_pos.symbol,SYMBOL_POINT)*0.1;
      bool changed = (MathAbs(sl-m_pos.sl)>eps || MathAbs(tp-m_pos.tp)>eps);
      m_pos.sl=sl; m_pos.tp=tp; m_pos.volume=PositionGetDouble(POSITION_VOLUME);
      if(changed && !m_pos.dirty) SyncLinesFromState();
   }

   void ReadLinesToState()
   {
      if(!m_pos.active) return;
      m_pos.sl = GetHLine(N("SL"), m_pos.sl);
      m_pos.tp = GetHLine(N("TP"), m_pos.tp);
   }

   bool ApplyModify()
   {
      if(!m_pos.active) return false;
      ReadLinesToState();
      if(!PositionSelectByTicket(m_pos.ticket)){ Clear(); return false; }
      bool ok = m_trade.PositionModify(m_pos.ticket, m_pos.sl, m_pos.tp);
      if(ok){ m_pos.dirty=false; m_pendingApply=false; SyncFromServer(); }
      return ok;
   }

   bool MoveToBE(double extraPoints=0)
   {
      if(!m_pos.active || !PositionSelectByTicket(m_pos.ticket)) return false;
      double point=SymbolInfoDouble(m_pos.symbol,SYMBOL_POINT);
      double be = m_pos.isBuy ? (m_pos.openPrice + extraPoints*point) : (m_pos.openPrice - extraPoints*point);
      if(m_pos.isBuy && m_pos.sl!=0 && be<=m_pos.sl) return false;
      if(!m_pos.isBuy && m_pos.sl!=0 && be>=m_pos.sl) return false;
      m_pos.sl=be; m_pos.dirty=false; SyncLinesFromState();
      return m_trade.PositionModify(m_pos.ticket, m_pos.sl, m_pos.tp);
   }

   bool ApplyTrailOnce(ENUM_TRAILING_MODE mode,double value,ENUM_TIMEFRAMES tf=PERIOD_H1)
   {
      if(!m_pos.active || !PositionSelectByTicket(m_pos.ticket)) return false;
      double point=SymbolInfoDouble(m_pos.symbol,SYMBOL_POINT);
      double price=PositionGetDouble(POSITION_PRICE_CURRENT);
      double newSL=m_pos.sl;
      if(mode==TRAIL_FIXED) newSL = m_pos.isBuy ? price-value*point : price+value*point;
      else if(mode==TRAIL_ATR){ double atr=GetATR(m_pos.symbol,tf,14); newSL = m_pos.isBuy ? price-value*atr : price+value*atr; }
      else if(mode==TRAIL_CANDLE) newSL = m_pos.isBuy ? iLow(m_pos.symbol,tf,1) : iHigh(m_pos.symbol,tf,1);
      else return false;
      if(m_pos.isBuy){ if(m_pos.sl!=0 && newSL<=m_pos.sl) return false; }
      else { if(m_pos.sl!=0 && newSL>=m_pos.sl) return false; }
      m_pos.sl=newSL; m_pos.dirty=false; SyncLinesFromState();
      return m_trade.PositionModify(m_pos.ticket, m_pos.sl, m_pos.tp);
   }

   bool PartialClose(double percent)
   {
      if(!m_pos.active || !PositionSelectByTicket(m_pos.ticket)) return false;
      double vol=SymbolInfoDouble(m_pos.symbol, SYMBOL_VOLUME_MIN); // unused guard
      vol=PositionGetDouble(POSITION_VOLUME);
      double closeVol=NormalizeLot(m_pos.symbol, vol*percent/100.0);
      if(closeVol<=0 || closeVol>=vol) return false;
      bool ok = m_trade.PositionClosePartial(m_pos.ticket, closeVol);
      if(ok) SyncFromServer();
      return ok;
   }

   bool CloseSelected(){ if(!m_pos.active) return false; bool ok=m_trade.PositionClose(m_pos.ticket); if(ok) Clear(); return ok; }

   bool OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
   {
      if(!m_pos.active) return false;
      if(id==CHARTEVENT_OBJECT_CHANGE && StringFind(sparam,m_pfx)==0)
      {
         ReadLinesToState(); m_pos.dirty=true; m_pendingApply=true; return true;
      }
      if(id==CHARTEVENT_OBJECT_DRAG && StringFind(sparam,m_pfx)==0)
      {
         ReadLinesToState(); m_pos.dirty=true; ApplyModify(); return true;
      }
      return false;
   }

   void OnTick(){ if(m_pendingApply){ ApplyModify(); } SyncFromServer(); }

   void Clear()
   {
      if(ObjectFind(m_chart,N("SL"))>=0) ObjectDelete(m_chart,N("SL"));
      if(ObjectFind(m_chart,N("TP"))>=0) ObjectDelete(m_chart,N("TP"));
      m_pos.Reset(); m_pendingApply=false;
      ChartRedraw(m_chart);
   }
};

#endif // MM_POSITION_DRAG_TOOL_MQH
