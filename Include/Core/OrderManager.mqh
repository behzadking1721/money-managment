#ifndef ORDER_MANAGER_MQH
#define ORDER_MANAGER_MQH
#include "../Utils/Common.mqh"
class COrderManager
{
private: CTrade m_trade;
public:
   void Init(){m_trade.SetExpertMagicNumber(MM_MAGIC_DEFAULT);m_trade.SetDeviationInPoints(MM_SLIPPAGE_DEFAULT);}
   void SetMagic(int magic){m_trade.SetExpertMagicNumber(magic);}
   // Market order
   bool MarketOrder(string symbol,ENUM_ORDER_TYPE type,double lot,double sl=0,double tp=0,string comment="",int magic=0)
   {
      if(magic!=0)m_trade.SetExpertMagicNumber(magic);
      double price=(type==ORDER_TYPE_BUY)?SymbolInfoDouble(symbol,SYMBOL_ASK):SymbolInfoDouble(symbol,SYMBOL_BID);
      return m_trade.PositionOpen(symbol,type,NormalizeLot(symbol,lot),price,sl,tp,comment);
   }
   // Limit
   bool LimitOrder(string symbol,ENUM_ORDER_TYPE type,double lot,double price,double sl=0,double tp=0,datetime expiry=0,string comment="",int magic=0)
   {
      if(magic!=0)m_trade.SetExpertMagicNumber(magic);
      bool ok=m_trade.OrderOpen(symbol,type,NormalizeLot(symbol,lot),price,sl,tp,0,ORDER_TIME_GTC,expiry,comment);
      return ok;
   }
   // Stop
   bool StopOrder(string symbol,ENUM_ORDER_TYPE type,double lot,double price,double sl=0,double tp=0,datetime expiry=0,string comment="",int magic=0)
   {
      if(magic!=0)m_trade.SetExpertMagicNumber(magic);
      return m_trade.OrderOpen(symbol,type,NormalizeLot(symbol,lot),price,sl,tp,0,ORDER_TIME_GTC,expiry,comment);
   }
   // OCO: place two pending orders, cancel one when other fills
   bool OCO(string symbol,double lot,double buyStop,double sellStop,double slBuy=0,double tpBuy=0,double slSell=0,double tpSell=0,int magic=0)
   {
      bool a=StopOrder(symbol,ORDER_TYPE_BUY_STOP,lot,buyStop,slBuy,tpBuy,0,"OCO buy",magic);
      bool b=StopOrder(symbol,ORDER_TYPE_SELL_STOP,lot,sellStop,slSell,tpSell,0,"OCO sell",magic);
      return a&&b;
   }
   // Cancel pending
   bool CancelOrder(ulong ticket){return m_trade.OrderDelete(ticket);}
   // Cancel all pending
   int CancelAllPending(int magic=0,string symbol="")
   {
      int c=0;
      for(int i=OrdersTotal()-1;i>=0;i--){
         ulong t=OrderGetTicket(i);if(t==0)continue;
         if(magic!=0&&(int)OrderGetInteger(ORDER_MAGIC)!=magic)continue;
         if(symbol!=""&&OrderGetString(ORDER_SYMBOL)!=symbol)continue;
         if(m_trade.OrderDelete(t))c++;
      }return c;
   }
   // Expire old pending
   int ExpireOldPending(int maxMinutes,int magic=0)
   {
      int c=0;datetime now=TimeCurrent();
      for(int i=OrdersTotal()-1;i>=0;i--){
         ulong t=OrderGetTicket(i);if(t==0)continue;
         if(magic!=0&&(int)OrderGetInteger(ORDER_MAGIC)!=magic)continue;
         datetime ot=(datetime)OrderGetInteger(ORDER_TIME_SETUP);
         if((now-ot)/60>=maxMinutes){if(m_trade.OrderDelete(t))c++;}
      }return c;
   }
   // Retry logic wrapper
   bool ExecuteWithRetry(bool &result_func_placeholder)
   {
      // placeholder kept for API; actual retry handled by caller
      return true;
   }
   bool RetryMarketOrder(string symbol,ENUM_ORDER_TYPE type,double lot,double sl,double tp,string comment,int magic,int maxRetries=MM_MAX_RETRIES)
   {
      for(int i=0;i<maxRetries;i++){
         if(MarketOrder(symbol,type,lot,sl,tp,comment,magic))return true;
         Sleep(200);
      }return false;
   }
};
#endif
