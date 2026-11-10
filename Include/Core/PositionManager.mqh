#ifndef POSITION_MANAGER_MQH
#define POSITION_MANAGER_MQH
#include "../Utils/Common.mqh"
class CPositionManager
{
private: CTrade m_trade;
public:
   void Init(){m_trade.SetExpertMagicNumber(MM_MAGIC_DEFAULT);m_trade.SetDeviationInPoints(MM_SLIPPAGE_DEFAULT);}
   void SetMagic(int magic){m_trade.SetExpertMagicNumber(magic);}
   bool MoveToBreakEven(ulong ticket,ENUM_BE_MODE mode,double extraPoints=0)
   {
      if(!PositionSelectByTicket(ticket))return false;
      string sym=PositionGetString(POSITION_SYMBOL);
      double openPrice=PositionGetDouble(POSITION_PRICE_OPEN),point=SymbolInfoDouble(sym,SYMBOL_POINT);
      double sl=PositionGetDouble(POSITION_SL);ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double newSL=sl;
      if(mode==BE_AT_BREAKEVEN)newSL=openPrice;
      else if(mode==BE_PLUS_SPREAD){double ask=SymbolInfoDouble(sym,SYMBOL_ASK),bid=SymbolInfoDouble(sym,SYMBOL_BID);newSL=(type==POSITION_TYPE_BUY)?openPrice+(ask-bid):openPrice-(ask-bid);}
      else if(mode==BE_PLUS_POINTS)newSL=(type==POSITION_TYPE_BUY)?openPrice+extraPoints*point:openPrice-extraPoints*point;
      if(type==POSITION_TYPE_BUY&&newSL<=sl&&sl!=0)return false;
      if(type==POSITION_TYPE_SELL&&newSL>=sl&&sl!=0)return false;
      return m_trade.PositionModify(ticket,newSL,PositionGetDouble(POSITION_TP));
   }
   bool TrailStop(ulong ticket,ENUM_TRAILING_MODE mode,double value,ENUM_TIMEFRAMES tf=PERIOD_H1)
   {
      if(!PositionSelectByTicket(ticket))return false;
      string sym=PositionGetString(POSITION_SYMBOL);double point=SymbolInfoDouble(sym,SYMBOL_POINT);
      double sl=PositionGetDouble(POSITION_SL);double price=PositionGetDouble(POSITION_PRICE_CURRENT);
      ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);double newSL=sl;
      if(mode==TRAIL_FIXED)newSL=(type==POSITION_TYPE_BUY)?price-value*point:price+value*point;
      else if(mode==TRAIL_ATR){double atr=GetATR(sym,tf,14);newSL=(type==POSITION_TYPE_BUY)?price-value*atr:price+value*atr;}
      else if(mode==TRAIL_CANDLE)newSL=(type==POSITION_TYPE_BUY)?iLow(sym,tf,1):iHigh(sym,tf,1);
      if(type==POSITION_TYPE_BUY){if(sl!=0&&newSL<=sl)return false;}else{if(sl!=0&&newSL>=sl)return false;}
      return m_trade.PositionModify(ticket,newSL,PositionGetDouble(POSITION_TP));
   }
   bool PartialClose(ulong ticket,double percent)
   {
      if(!PositionSelectByTicket(ticket))return false;
      string sym=PositionGetString(POSITION_SYMBOL);double vol=PositionGetDouble(POSITION_VOLUME);
      double closeVol=NormalizeLot(sym,vol*percent/100.0);
      if(closeVol<=0||closeVol>=vol)return false;
      return m_trade.PositionClosePartial(ticket,closeVol);
   }
   bool TimeBasedExit(ulong ticket,int maxMinutes)
   {
      if(!PositionSelectByTicket(ticket))return false;
      datetime openTime=(datetime)PositionGetInteger(POSITION_TIME);
      if((TimeCurrent()-openTime)/60>=maxMinutes)return m_trade.PositionClose(ticket);
      return false;
   }
   int CloseAll(int magic=0,string symbol="")
   {
      int closed=0;
      for(int i=PositionsTotal()-1;i>=0;i--){
         ulong t=PositionGetTicket(i);if(t==0)continue;
         if(magic!=0&&(int)PositionGetInteger(POSITION_MAGIC)!=magic)continue;
         if(symbol!=""&&PositionGetString(POSITION_SYMBOL)!=symbol)continue;
         if(m_trade.PositionClose(t))closed++;
      }return closed;
   }
   int CloseProfit(int magic=0){int c=0;for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0)continue;if(magic!=0&&(int)PositionGetInteger(POSITION_MAGIC)!=magic)continue;if(PositionGetDouble(POSITION_PROFIT)>0&&m_trade.PositionClose(t))c++;}return c;}
   int CloseLoss(int magic=0){int c=0;for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0)continue;if(magic!=0&&(int)PositionGetInteger(POSITION_MAGIC)!=magic)continue;if(PositionGetDouble(POSITION_PROFIT)<0&&m_trade.PositionClose(t))c++;}return c;}
};
#endif
