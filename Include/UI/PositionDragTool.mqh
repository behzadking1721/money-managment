#ifndef MM_POSITION_DRAG_TOOL_MQH
#define MM_POSITION_DRAG_TOOL_MQH

#include "../Core/Contracts.mqh"
#include <Trade/Trade.mqh>
#include "../Utils/Common.mqh"

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
   string m_lastError;

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

   bool IsStopsLevelOK(string sym, ENUM_POSITION_TYPE type, double currentPrice, double newSL, string &reason)
   {
      double stopsLevel = (double)SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL);
      double point = SymbolInfoDouble(sym, SYMBOL_POINT);
      if(point <= 0) { reason = "invalid point size"; return false; }
      double minDist = stopsLevel * point;
      double dist = MathAbs(currentPrice - newSL);
      if(dist < minDist) { reason = "SL too close to price (stops level)"; return false; }
      return true;
   }

   bool IsFreezeLevelOK(string sym, double volume, string &reason)
   {
      double freezeLevel = (double)SymbolInfoInteger(sym, SYMBOL_TRADE_FREEZE_LEVEL);
      double point = SymbolInfoDouble(sym, SYMBOL_POINT);
      if(point <= 0) { reason = "invalid point size"; return false; }
      double minVol = freezeLevel * point;
      if(volume > 0 && volume < minVol) { reason = "volume below freeze level"; return false; }
      return true;
   }

   double NormalizePrice(string sym, double price, string &reason)
   {
      int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      if(digits < 0) { reason = "invalid symbol digits"; return 0; }
      return NormalizeDouble(price, digits);
   }

   double NormalizeVol(string sym, double vol, string &reason)
   {
      double v = NormalizeLot(sym, vol);
      double minV = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
      double maxV = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
      if(v < minV) { reason = "volume below minimum"; return 0; }
      if(v > maxV) { reason = "volume above maximum"; return 0; }
      return v;
   }

   bool CheckModifyResult(string sym, ENUM_POSITION_TYPE type, double currentPrice, double newSL, string &reason)
   {
      if(!IsStopsLevelOK(sym, type, currentPrice, newSL, reason)) return false;
      double vol = PositionGetDouble(POSITION_VOLUME);
      if(!IsFreezeLevelOK(sym, vol, reason)) return false;
      return true;
   }

public:
   CPositionDragTool(){ m_chart=0; m_pfx="MM_PD_"; m_optInMulti=false; m_pendingApply=false; m_pos.Reset(); m_lastError=""; }

   void Init(long chart,long magic=0,const string prefix="MM_PD_")
   {
      m_chart=chart; m_pfx=prefix; if(magic!=0) m_trade.SetExpertMagicNumber(magic);
   }
   bool Active(){ return m_pos.active; }
   ulong Ticket(){ return m_pos.ticket; }
   bool MultiOptIn(){ return m_optInMulti; }
   void SetMultiOptIn(bool v){ m_optInMulti=v; }
   MM_PosDragState State(){ return m_pos; }
   string LastError(){ return m_lastError; }

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
      m_lastError="";
      if(!m_pos.active) { m_lastError="position not active"; return false; }
      ReadLinesToState();
      if(!PositionSelectByTicket(m_pos.ticket)){ Clear(); m_lastError="position not found"; return false; }
      string sym = m_pos.symbol;
      ENUM_POSITION_TYPE type = m_pos.isBuy ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
      double currentPrice = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(sym,SYMBOL_BID) : SymbolInfoDouble(sym,SYMBOL_ASK);
      double newSL = NormalizePrice(sym, m_pos.sl, m_lastError);
      if(m_lastError != "") return false;
      double newTP = NormalizePrice(sym, m_pos.tp, m_lastError);
      if(m_lastError != "") return false;
      if(!CheckModifyResult(sym, type, currentPrice, newSL, m_lastError)) return false;
      bool ok = m_trade.PositionModify(m_pos.ticket, newSL, newTP);
      if(!ok) { uint rc = m_trade.ResultRetcode(); m_lastError = "PositionModify failed"; return false; }
      if(m_trade.ResultRetcode() != TRADE_RETCODE_DONE) { uint rc = m_trade.ResultRetcode(); m_lastError = "PositionModify not accepted"; return false; }
      m_pos.dirty=false; m_pendingApply=false; SyncFromServer();
      return true;
   }

   bool MoveToBE(double extraPoints=0)
   {
      m_lastError="";
      if(!m_pos.active || !PositionSelectByTicket(m_pos.ticket)) { m_lastError="position not found"; return false; }
      string sym = m_pos.symbol;
      double point = SymbolInfoDouble(sym, SYMBOL_POINT);
      if(point <= 0) { m_lastError = "invalid point size"; return false; }
      double be = m_pos.isBuy ? (m_pos.openPrice + extraPoints * point) : (m_pos.openPrice - extraPoints * point);
      if(m_pos.isBuy && m_pos.sl != 0 && be <= m_pos.sl) { m_lastError = "BE would not improve SL"; return false; }
      if(!m_pos.isBuy && m_pos.sl != 0 && be >= m_pos.sl) { m_lastError = "BE would not improve SL"; return false; }
      ENUM_POSITION_TYPE type = m_pos.isBuy ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
      double currentPrice = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(sym,SYMBOL_BID) : SymbolInfoDouble(sym,SYMBOL_ASK);
      int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      if(digits < 0) { m_lastError = "invalid symbol digits"; return false; }
      double newSL = NormalizeDouble(be, digits);
      if(!CheckModifyResult(sym, type, currentPrice, newSL, m_lastError)) return false;
      double newTP = NormalizePrice(sym, m_pos.tp, m_lastError);
      if(m_lastError != "") return false;
      m_pos.sl = newSL; m_pos.dirty = false; SyncLinesFromState();
      bool ok = m_trade.PositionModify(m_pos.ticket, newSL, newTP);
      if(!ok) { uint rc = m_trade.ResultRetcode(); m_lastError = "PositionModify failed"; return false; }
      if(m_trade.ResultRetcode() != TRADE_RETCODE_DONE) { uint rc = m_trade.ResultRetcode(); m_lastError = "PositionModify not accepted"; return false; }
      return true;
   }

   bool ApplyTrailOnce(ENUM_TRAILING_MODE mode,double value,ENUM_TIMEFRAMES tf=PERIOD_H1)
   {
      m_lastError="";
      if(!m_pos.active || !PositionSelectByTicket(m_pos.ticket)) { m_lastError="position not found"; return false; }
      string sym = m_pos.symbol;
      double point = SymbolInfoDouble(sym, SYMBOL_POINT);
      if(point <= 0) { m_lastError = "invalid point size"; return false; }
      double price = PositionGetDouble(POSITION_PRICE_CURRENT);
      ENUM_POSITION_TYPE type = m_pos.isBuy ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
      double currentPrice = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(sym,SYMBOL_BID) : SymbolInfoDouble(sym,SYMBOL_ASK);
      double newSL = m_pos.sl;
      if(mode == TRAIL_FIXED) newSL = m_pos.isBuy ? price - value * point : price + value * point;
      else if(mode == TRAIL_ATR)
      {
         double atr = GetATR(sym, tf, 14);
         if(atr <= 0) { m_lastError = "ATR unavailable"; return false; }
         newSL = m_pos.isBuy ? price - value * atr : price + value * atr;
      }
      else if(mode == TRAIL_CANDLE)
      {
         if(tf <= 0) { m_lastError = "invalid timeframe"; return false; }
         newSL = m_pos.isBuy ? iLow(sym, tf, 1) : iHigh(sym, tf, 1);
         if(newSL <= 0) { m_lastError = "candle price invalid"; return false; }
      }
      else { m_lastError = "unsupported trailing mode"; return false; }
      int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      if(digits < 0) { m_lastError = "invalid symbol digits"; return false; }
      newSL = NormalizeDouble(newSL, digits);
      if(m_pos.sl != 0)
      {
         if(m_pos.isBuy && newSL <= m_pos.sl) { m_lastError = "trail SL not above current SL"; return false; }
         if(!m_pos.isBuy && newSL >= m_pos.sl) { m_lastError = "trail SL not below current SL"; return false; }
      }
      if(!CheckModifyResult(sym, type, currentPrice, newSL, m_lastError)) return false;
      double newTP = NormalizePrice(sym, m_pos.tp, m_lastError);
      if(m_lastError != "") return false;
      m_pos.sl = newSL; m_pos.dirty = false; SyncLinesFromState();
      bool ok = m_trade.PositionModify(m_pos.ticket, newSL, newTP);
      if(!ok) { uint rc = m_trade.ResultRetcode(); m_lastError = "PositionModify failed"; return false; }
      if(m_trade.ResultRetcode() != TRADE_RETCODE_DONE) { uint rc = m_trade.ResultRetcode(); m_lastError = "PositionModify not accepted"; return false; }
      return true;
   }

   bool PartialClose(double percent)
   {
      m_lastError="";
      if(!m_pos.active || !PositionSelectByTicket(m_pos.ticket)) { m_lastError="position not found"; return false; }
      string sym = m_pos.symbol;
      double vol = PositionGetDouble(POSITION_VOLUME);
      if(percent <= 0.0 || percent >= 100.0) { m_lastError = "percent must be > 0 and < 100"; return false; }
      double closeVol = vol * percent / 100.0;
      closeVol = NormalizeVol(sym, closeVol, m_lastError);
      if(m_lastError != "") return false;
      double remainingVol = vol - closeVol;
      double minVol = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
      if(remainingVol < minVol) { m_lastError = "remaining volume below minimum"; return false; }
      ENUM_POSITION_TYPE type = m_pos.isBuy ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
      double currentPrice = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(sym,SYMBOL_BID) : SymbolInfoDouble(sym,SYMBOL_ASK);
      if(!IsFreezeLevelOK(sym, closeVol, m_lastError)) return false;
      bool ok = m_trade.PositionClosePartial(m_pos.ticket, closeVol);
      if(!ok) { uint rc = m_trade.ResultRetcode(); m_lastError = "PositionClosePartial failed"; return false; }
      if(m_trade.ResultRetcode() != TRADE_RETCODE_DONE) { uint rc = m_trade.ResultRetcode(); m_lastError = "PositionClosePartial not accepted"; return false; }
      SyncFromServer();
      return true;
   }

   bool CloseSelected()
   {
      m_lastError="";
      if(!m_pos.active) { m_lastError="position not active"; return false; }
      if(!PositionSelectByTicket(m_pos.ticket)) { m_lastError="position not found"; return false; }
      bool ok = m_trade.PositionClose(m_pos.ticket);
      if(!ok) { uint rc = m_trade.ResultRetcode(); m_lastError = "PositionClose failed"; return false; }
      if(m_trade.ResultRetcode() != TRADE_RETCODE_DONE) { uint rc = m_trade.ResultRetcode(); m_lastError = "PositionClose not accepted"; return false; }
      Clear();
      return ok;
   }

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
