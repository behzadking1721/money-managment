//+------------------------------------------------------------------+
//|                                                      Alerts.mqh  |
//|                  Phase 6: news/guard/connection/DD alerts        |
//+------------------------------------------------------------------+
#ifndef MM_ALERTS_MQH
#define MM_ALERTS_MQH

#include "../Core/Contracts.mqh"
#include "../Utils/Common.mqh"

class CAlertManager
{
private:
   bool     m_sound;
   bool     m_push;
   bool     m_popup;
   bool     m_logPrint;
   string   m_soundFile;
   datetime m_lastConnAlert;
   datetime m_lastDdAlert;
   datetime m_lastNewsAlert;
   int      m_connCooldownSec;
   int      m_ddCooldownSec;
   int      m_newsCooldownSec;

   bool Cooldown(datetime &last,int sec)
   {
      datetime now=TimeCurrent();
      if(last!=0 && (now-last) < sec) return false;
      last=now; return true;
   }

   void Emit(const string tag,const string msg)
   {
      if(m_logPrint) Print("MM ALERT [",tag,"]: ",msg);
      if(m_popup) Alert("MM [",tag,"]: ",msg);
      if(m_sound) PlaySound(m_soundFile);
      if(m_push) SendNotification("MM ["+tag+"] "+msg);
   }

public:
   CAlertManager()
   {
      m_sound=true; m_push=false; m_popup=false; m_logPrint=true; m_soundFile="alert.wav";
      m_lastConnAlert=0; m_lastDdAlert=0; m_lastNewsAlert=0;
      m_connCooldownSec=120; m_ddCooldownSec=300; m_newsCooldownSec=300;
   }

   void Init(){}
   void Configure(bool sound,bool push,bool popup,bool logPrint=true)
   { m_sound=sound; m_push=push; m_popup=popup; m_logPrint=logPrint; }
   void SetSoundFile(const string f){ m_soundFile=f; }

   void OnGuardEvent(const MM_GuardResult &gr,const string symbol)
   {
      if(gr.decision==GUARD_BLOCK)
      {
         string msg="BLOCK "+gr.guardId+"/"+gr.reasonCode+" "+symbol;
         Emit("GUARD", msg);
         // DD-cap related blocks also trigger DD alert channel
         if(StringFind(gr.reasonCode,"DD")>=0 || StringFind(gr.reasonCode,"LOSS")>=0 || StringFind(gr.reasonCode,"DRAWDOWN")>=0)
            AlertDDCap(gr.reasonCode+" "+symbol);
      }
      else if(gr.decision==GUARD_WARN)
      {
         if(m_logPrint) Print("MM ALERT [GUARD-WARN]: ",gr.guardId,"/",gr.reasonCode," ",symbol);
      }
   }

   void AlertNews(const string symbol,const string detail)
   {
      if(!Cooldown(m_lastNewsAlert,m_newsCooldownSec)) return;
      Emit("NEWS", detail+" "+symbol);
   }

   void AlertConnection(const string detail)
   {
      if(!Cooldown(m_lastConnAlert,m_connCooldownSec)) return;
      Emit("CONNECTION", detail);
   }
   void AlertConnectionLost(){ AlertConnection("Terminal disconnected or trade context unavailable"); }
   void AlertConnectionRestored(){ if(Cooldown(m_lastConnAlert,10)) Emit("CONNECTION","Connection restored"); }

   void AlertDDCap(const string detail)
   {
      if(!Cooldown(m_lastDdAlert,m_ddCooldownSec)) return;
      Emit("DD", detail);
   }
   void AlertDrawdown(){ AlertDDCap("Max drawdown limit reached"); }
   void AlertDailyLoss(){ AlertDDCap("Daily loss limit reached"); }

   // compatibility
   void AlertTradeOpened(string sym,double lot,double price){ Emit("TRADE","Opened "+sym+" "+DoubleToString(lot,2)+" @ "+DoubleToString(price,_Digits)); }
   void AlertTradeClosed(string sym,double profit){ Emit("TRADE","Closed "+sym+" P/L="+DoubleToString(profit,2)); }
   void AlertSLHit(string sym){ Emit("TRADE","SL hit "+sym); }
   void AlertTPHit(string sym,int n){ Emit("TRADE","TP"+(string)n+" hit "+sym); }
   void AlertDailyLimit(){ AlertDDCap("Daily limit reached"); }
   void Fire(string message,ENUM_ALERT_TYPE type=ALERT_SOUND){ Emit("INFO",message); }
};

#endif // MM_ALERTS_MQH
