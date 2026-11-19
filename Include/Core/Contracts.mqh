//+------------------------------------------------------------------+
//|                                                   Contracts.mqh  |
//|                         Shared contracts (Phase 1, v1.0, frozen) |
//+------------------------------------------------------------------+
#ifndef MM_CONTRACTS_MQH
#define MM_CONTRACTS_MQH

#define MM_CONTRACT_VERSION 1
#define MM_MAX_TP_LEVELS    5
#define MM_MAX_CAPS         16
#define MM_MAX_WARNINGS     16
#define MM_MAX_REASON       128
#define MM_MAX_CTX          128

//--- enums
enum ENUM_MM_ACCOUNT_MODE
{
   ACCOUNT_PERSONAL = 0,
   ACCOUNT_PROP     = 1,
   ACCOUNT_CRYPTO   = 2
};

enum ENUM_MM_SIZING_MODE
{
   SIZING_AUTO_RISK  = 0,
   SIZING_MANUAL_LOT = 1
};

enum ENUM_MM_GUARD_DECISION
{
   GUARD_ALLOW = 0,
   GUARD_WARN  = 1,
   GUARD_BLOCK = 2
};

enum ENUM_MM_EVENT_TYPE
{
   MM_EVENT_OPEN         = 0,
   MM_EVENT_CLOSE        = 1,
   MM_EVENT_MODIFY       = 2,
   MM_EVENT_PARTIAL_FILL = 3,
   MM_EVENT_REJECT       = 4,
   MM_EVENT_DEAL_ADD     = 5,
   MM_EVENT_ORDER_ADD    = 6
};

//--- structs
struct MM_TradePlan
{
   int                version;
   string             symbol;
   ENUM_ORDER_TYPE    orderType;
   ENUM_POSITION_TYPE side;        // buy/sell intent
   double             entryPrice;
   double             slPrice;
   double             tpPrice[MM_MAX_TP_LEVELS];
   int                tpCount;
   double             lot;
   ENUM_MM_SIZING_MODE sizingMode;
   double             riskValue;   // percent or money depending on profile/template
   string             templateId;
   string             profileId;
   long               magic;
   int                slippagePoints;
   string             comment;
   bool               isPending;
   datetime           serverTime;
   void Reset()
   {
      version=MM_CONTRACT_VERSION; symbol=""; orderType=ORDER_TYPE_BUY; side=POSITION_TYPE_BUY;
      entryPrice=0; slPrice=0; tpCount=0; lot=0; sizingMode=SIZING_AUTO_RISK; riskValue=0;
      templateId=""; profileId=""; magic=0; slippagePoints=0; comment=""; isPending=false; serverTime=0;
      for(int i=0;i<MM_MAX_TP_LEVELS;i++) tpPrice[i]=0;
   }
};

struct MM_RiskResult
{
   int    version;
   bool   valid;
   bool   blocked;
   double lot;
   double riskMoney;
   double riskPercent;
   double rr;
   string basis;                 // Equity/Balance/AllowedDD
   string capsApplied[MM_MAX_CAPS];
   int    capsCount;
   string warnings[MM_MAX_WARNINGS];
   int    warningsCount;
   void Reset(){version=MM_CONTRACT_VERSION;valid=false;blocked=false;lot=0;riskMoney=0;riskPercent=0;rr=0;basis="";capsCount=0;warningsCount=0;}
   void AddCap(string c){ if(capsCount<MM_MAX_CAPS) capsApplied[capsCount++]=c; }
   void AddWarn(string w){ if(warningsCount<MM_MAX_WARNINGS) warnings[warningsCount++]=w; }
};

struct MM_GuardResult
{
   int               version;
   ENUM_MM_GUARD_DECISION decision;
   string            guardId;
   int               priority;
   string            reasonCode;
   string            messageEN;
   string            messageFA;
   string            context;
   void Reset(){version=MM_CONTRACT_VERSION;decision=GUARD_ALLOW;guardId="";priority=0;reasonCode="";messageEN="";messageFA="";context="";}
};

struct MM_TradeEvent
{
   int                version;
   ENUM_MM_EVENT_TYPE type;
   ulong              ticket;
   ulong              order;
   ulong              deal;
   long               positionId;
   string             symbol;
   ENUM_POSITION_TYPE side;
   double             volume;
   double             price;
   double             sl;
   double             tp;
   double             profit;
   double             commission;
   double             swap;
   datetime           timeServer;
   datetime           timeLocal;
   uint               retcode;
   string             reasonCode;
   string             reason;
   void Reset()
   {
      version=MM_CONTRACT_VERSION; type=MM_EVENT_OPEN; ticket=0; order=0; deal=0; positionId=0;
      symbol=""; side=POSITION_TYPE_BUY; volume=0; price=0; sl=0; tp=0; profit=0; commission=0; swap=0;
      timeServer=0; timeLocal=0; retcode=0; reasonCode=""; reason="";
   }
};

struct MM_Profile
{
   int              version;
   string           id;
   string           name;
   ENUM_MM_ACCOUNT_MODE accountMode;
   string           riskBasis;    // Equity/Balance/AllowedDD
   double           defaultRiskPercent;
   double           maxRiskPercent;
   double           minRiskPercent;
   bool             autoRiskDefault;
   void Reset(){version=MM_CONTRACT_VERSION;id="";name="";accountMode=ACCOUNT_PERSONAL;riskBasis="Equity";defaultRiskPercent=1.0;maxRiskPercent=2.0;minRiskPercent=0.25;autoRiskDefault=true;}
};

struct MM_Template
{
   int              version;
   string           id;
   string           name;
   string           symbol;       // empty = any
   ENUM_MM_SIZING_MODE sizingMode;
   double           riskValue;
   int              atrPeriod;
   ENUM_TIMEFRAMES  atrTF;
   int              maxSlippagePoints;
   bool             rrLock;
   void Reset(){version=MM_CONTRACT_VERSION;id="";name="";symbol="";sizingMode=SIZING_AUTO_RISK;riskValue=1.0;atrPeriod=14;atrTF=PERIOD_CURRENT;maxSlippagePoints=30;rrLock=false;}
};

//--- listener interface
class ITradeEventListener
{
public:
   virtual void OnTradeEvent(const MM_TradeEvent &event) = 0;
};

#endif // MM_CONTRACTS_MQH
