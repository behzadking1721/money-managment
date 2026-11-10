#ifndef ALERTS_MQH
#define ALERTS_MQH
#include "../Utils/Common.mqh"
class CAlertManager
{
private:
   bool m_sound;bool m_push;bool m_email;bool m_popup;
   string m_soundFile;
public:
   void Init(){m_sound=true;m_push=false;m_email=false;m_popup=true;m_soundFile="alert.wav";}
   void Configure(bool sound,bool push,bool email,bool popup){m_sound=sound;m_push=push;m_email=email;m_popup=popup;}
   void SetSoundFile(string f){m_soundFile=f;}
   void Fire(string message,ENUM_ALERT_TYPE type=ALERT_SOUND)
   {
      if(m_sound&&(type==ALERT_SOUND||type==ALERT_POPUP))PlaySound(m_soundFile);
      if(m_push)SendNotification(message);
      if(m_email)SendMail("Money Manager Alert",message);
      if(m_popup)Alert(message);
   }
   void AlertTradeOpened(string sym,double lot,double price){Fire("Trade opened: "+sym+" "+DoubleToString(lot,2)+" @ "+DoubleToString(price,_Digits));}
   void AlertTradeClosed(string sym,double profit){Fire("Trade closed: "+sym+" profit="+DoubleToString(profit,2));}
   void AlertSLHit(string sym){Fire("SL hit: "+sym);}
   void AlertTPHit(string sym,int n){Fire("TP"+(string)n+" hit: "+sym);}
   void AlertDailyLimit(){Fire("Daily limit reached!");}
   void AlertDrawdown(){Fire("Max drawdown reached!");}
   void AlertConnectionLost(){Fire("Connection lost!");}
   void AlertNews(){Fire("News blackout active!");}
};
#endif
