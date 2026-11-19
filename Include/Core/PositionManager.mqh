#ifndef POSITION_MANAGER_MQH
#define POSITION_MANAGER_MQH
#include "../Utils/Common.mqh"

class CPositionManager
{
private:
   CTrade m_trade;
   string m_lastError;
   uint   m_lastRetcode;
   ulong  m_lastCloseTicket;
   datetime m_lastCloseTime;

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

   void SetError(const string reason, uint retcode=0)
   {
      m_lastError = reason;
      m_lastRetcode = retcode;
   }

public:
   void Init(){m_trade.SetExpertMagicNumber(MM_MAGIC_DEFAULT);m_trade.SetDeviationInPoints(MM_SLIPPAGE_DEFAULT);m_lastError="";m_lastRetcode=0;m_lastCloseTicket=0;m_lastCloseTime=0;}
   void SetMagic(int magic){m_trade.SetExpertMagicNumber(magic);}
   string LastError(){return m_lastError;}
   uint   LastRetcode(){return m_lastRetcode;}
   void   ClearError(){m_lastError="";m_lastRetcode=0;}

   bool MoveToBreakEven(ulong ticket,ENUM_BE_MODE mode,double extraPoints=0)
   {
      m_lastError=""; m_lastRetcode=0;
      if(!PositionSelectByTicket(ticket)) { SetError("position not found"); return false; }
      string sym = PositionGetString(POSITION_SYMBOL);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double point = SymbolInfoDouble(sym, SYMBOL_POINT);
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double currentPrice = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(sym,SYMBOL_BID) : SymbolInfoDouble(sym,SYMBOL_ASK);
      if(point <= 0) { SetError("invalid point size"); return false; }

      double newSL = sl;
      if(mode == BE_AT_BREAKEVEN) newSL = openPrice;
      else if(mode == BE_PLUS_SPREAD)
      {
         double ask = SymbolInfoDouble(sym,SYMBOL_ASK);
         double bid = SymbolInfoDouble(sym,SYMBOL_BID);
         double spread = ask - bid;
         newSL = (type == POSITION_TYPE_BUY) ? openPrice + spread : openPrice - spread;
      }
      else if(mode == BE_PLUS_POINTS)
      {
         newSL = (type == POSITION_TYPE_BUY) ? openPrice + extraPoints * point : openPrice - extraPoints * point;
      }

      int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      if(digits < 0) { SetError("invalid symbol digits"); return false; }
      newSL = NormalizeDouble(newSL, digits);

      // Never loosen an existing protective SL
      if(sl != 0)
      {
         if(type == POSITION_TYPE_BUY && newSL <= sl) { SetError("BE would loosen or not improve existing SL"); return false; }
         if(type == POSITION_TYPE_SELL && newSL >= sl) { SetError("BE would loosen or not improve existing SL"); return false; }
      }

      // Respect stops level: distance from current price to new SL
      if(!IsStopsLevelOK(sym, type, currentPrice, newSL, m_lastError)) { SetError(m_lastError); return false; }

      // Respect freeze level for volume
      double vol = PositionGetDouble(POSITION_VOLUME);
      if(!IsFreezeLevelOK(sym, vol, m_lastError)) { SetError(m_lastError); return false; }

      // Preserve TP
      if(!m_trade.PositionModify(ticket, newSL, tp))
      {
         uint rc = m_trade.ResultRetcode();
         SetError("PositionModify failed", rc);
         return false;
      }
      if(m_trade.ResultRetcode() != TRADE_RETCODE_DONE)
      {
         uint rc = m_trade.ResultRetcode();
         SetError("PositionModify not accepted by server", rc);
         return false;
      }
      return true;
   }

   bool TrailStop(ulong ticket,ENUM_TRAILING_MODE mode,double value,ENUM_TIMEFRAMES tf=PERIOD_H1)
   {
      m_lastError=""; m_lastRetcode=0;
      if(!PositionSelectByTicket(ticket)) { SetError("position not found"); return false; }
      string sym = PositionGetString(POSITION_SYMBOL);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double price = PositionGetDouble(POSITION_PRICE_CURRENT);
      double point = SymbolInfoDouble(sym, SYMBOL_POINT);
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double currentPrice = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(sym,SYMBOL_BID) : SymbolInfoDouble(sym,SYMBOL_ASK);
      if(point <= 0) { SetError("invalid point size"); return false; }

      double newSL = sl;
      if(mode == TRAIL_FIXED)
      {
         newSL = (type == POSITION_TYPE_BUY) ? price - value * point : price + value * point;
      }
      else if(mode == TRAIL_ATR)
      {
         double atr = GetATR(sym, tf, 14);
         if(atr <= 0) { SetError("ATR unavailable"); return false; }
         newSL = (type == POSITION_TYPE_BUY) ? price - value * atr : price + value * atr;
      }
      else if(mode == TRAIL_CANDLE)
      {
         if(tf <= 0) { SetError("invalid timeframe"); return false; }
         newSL = (type == POSITION_TYPE_BUY) ? iLow(sym, tf, 1) : iHigh(sym, tf, 1);
         if(newSL <= 0) { SetError("candle price invalid"); return false; }
      }
      else
      {
         SetError("unsupported trailing mode");
         return false;
      }

      int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      if(digits < 0) { SetError("invalid symbol digits"); return false; }
      newSL = NormalizeDouble(newSL, digits);

      // SL must only move in protective direction
      if(sl != 0)
      {
         if(type == POSITION_TYPE_BUY && newSL <= sl) { SetError("trail SL not above current SL"); return false; }
         if(type == POSITION_TYPE_SELL && newSL >= sl) { SetError("trail SL not below current SL"); return false; }
      }

      // Respect stops level
      if(!IsStopsLevelOK(sym, type, currentPrice, newSL, m_lastError)) { SetError(m_lastError); return false; }

      // Respect freeze level
      double vol = PositionGetDouble(POSITION_VOLUME);
      if(!IsFreezeLevelOK(sym, vol, m_lastError)) { SetError(m_lastError); return false; }

      // Preserve TP
      if(!m_trade.PositionModify(ticket, newSL, tp))
      {
         uint rc = m_trade.ResultRetcode();
         SetError("PositionModify failed", rc);
         return false;
      }
      if(m_trade.ResultRetcode() != TRADE_RETCODE_DONE)
      {
         uint rc = m_trade.ResultRetcode();
         SetError("PositionModify not accepted by server", rc);
         return false;
      }
      return true;
   }

   bool PartialClose(ulong ticket,double percent)
   {
      m_lastError=""; m_lastRetcode=0;
      if(!PositionSelectByTicket(ticket)) { SetError("position not found"); return false; }
      string sym = PositionGetString(POSITION_SYMBOL);
      double vol = PositionGetDouble(POSITION_VOLUME);
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      // Validate percentage: strictly greater than 0 and less than 100
      if(percent <= 0.0 || percent >= 100.0) { SetError("percent must be > 0 and < 100"); return false; }

      double closeVol = vol * percent / 100.0;
      closeVol = NormalizeVol(sym, closeVol, m_lastError);
      if(m_lastError != "") { SetError(m_lastError); return false; }

      // Ensure remaining volume is valid
      double remainingVol = vol - closeVol;
      double minVol = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
      if(remainingVol < minVol) { SetError("remaining volume below minimum"); return false; }

      // Check freeze level for close volume
      if(!IsFreezeLevelOK(sym, closeVol, m_lastError)) { SetError(m_lastError); return false; }

      if(!m_trade.PositionClosePartial(ticket, closeVol))
      {
         uint rc = m_trade.ResultRetcode();
         SetError("PositionClosePartial failed", rc);
         return false;
      }
      if(m_trade.ResultRetcode() != TRADE_RETCODE_DONE)
      {
         uint rc = m_trade.ResultRetcode();
         SetError("PositionClosePartial not accepted by server", rc);
         return false;
      }
      return true;
   }

   bool TimeBasedExit(ulong ticket,int maxMinutes)
   {
      m_lastError=""; m_lastRetcode=0;
      // maxMinutes <= 0 must never trigger a close
      if(maxMinutes <= 0) { SetError("time exit disabled"); return false; }

      // Avoid repeatedly submitting close requests after an unsuccessful attempt
      if(m_lastCloseTicket == ticket && m_lastCloseTime > 0)
      {
         datetime now = TimeCurrent();
         if(now - m_lastCloseTime < 60) { SetError("close already attempted recently"); return false; }
      }

      if(!PositionSelectByTicket(ticket)) { SetError("position not found"); return false; }
      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      if(openTime <= 0) { SetError("invalid open time"); return false; }

      datetime now = TimeCurrent();
      double elapsedMinutes = (double)(now - openTime) / 60.0;
      if(elapsedMinutes < (double)maxMinutes) { SetError("time threshold not reached"); return false; }

      if(!m_trade.PositionClose(ticket))
      {
         uint rc = m_trade.ResultRetcode();
         m_lastCloseTicket = ticket;
         m_lastCloseTime = now;
         SetError("PositionClose failed", rc);
         return false;
      }
      if(m_trade.ResultRetcode() != TRADE_RETCODE_DONE)
      {
         uint rc = m_trade.ResultRetcode();
         m_lastCloseTicket = ticket;
         m_lastCloseTime = now;
         SetError("PositionClose not accepted by server", rc);
         return false;
      }
      m_lastCloseTicket = 0;
      m_lastCloseTime = 0;
      return true;
   }

   int CloseAll(int magic=0,string symbol="")
   {
      int closed = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong t = PositionGetTicket(i);
         if(t == 0) continue;
         if(!PositionSelectByTicket(t)) continue;
         if(magic != 0 && (int)PositionGetInteger(POSITION_MAGIC) != magic) continue;
         if(symbol != "" && PositionGetString(POSITION_SYMBOL) != symbol) continue;
         if(m_trade.PositionClose(t)) closed++;
      }
      return closed;
   }

   int CloseProfit(int magic=0)
   {
      int c = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong t = PositionGetTicket(i);
         if(t == 0) continue;
         if(!PositionSelectByTicket(t)) continue;
         if(magic != 0 && (int)PositionGetInteger(POSITION_MAGIC) != magic) continue;
         if(PositionGetDouble(POSITION_PROFIT) > 0 && m_trade.PositionClose(t)) c++;
      }
      return c;
   }

   int CloseLoss(int magic=0)
   {
      int c = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong t = PositionGetTicket(i);
         if(t == 0) continue;
         if(!PositionSelectByTicket(t)) continue;
         if(magic != 0 && (int)PositionGetInteger(POSITION_MAGIC) != magic) continue;
         if(PositionGetDouble(POSITION_PROFIT) < 0 && m_trade.PositionClose(t)) c++;
      }
      return c;
   }
};
#endif
