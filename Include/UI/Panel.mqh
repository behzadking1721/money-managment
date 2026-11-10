#ifndef PANEL_MQH
#define PANEL_MQH
#include "../Utils/Common.mqh"
#include <Controls/Dialog.mqh>
#include <Controls/Button.mqh>
#include <Controls/Label.mqh>
#include <Controls/Edit.mqh>
#include <Controls/ComboBox.mqh>
class CMoneyPanel
{
private:
   CAppDialog m_dialog;
   CLabel m_lblSpread,m_lblTime,m_lblAccount,m_lblSession,m_lblLastTrade,m_lblRR;
   CButton m_btnRiskPlus,m_btnRiskMinus,m_btnTPPlus,m_btnTPMinus,m_btnXAll,m_btnXProfit,m_btnXLoss,m_btnBEAll,m_btnPartial,m_btnDrag;
   CButton m_btnHide;
   SPanelSettings m_settings;
   bool m_hidden; bool m_dragging;
   int m_x,m_y;
public:
   void Init(SPanelSettings &s){m_settings=s;m_hidden=false;m_dragging=false;m_x=s.defaultX;m_y=s.defaultY;}
   bool Create(long chartId,string name)
   {
      int w=260,h=120;
      if(m_settings.panelSize==PANEL_COMPACT){w=220;h=100;}
      if(m_settings.panelSize==PANEL_LARGE){w=320;h=150;}
      if(!m_dialog.Create(chartId,name,0,m_x,m_y,m_x+w,m_y+h))return false;
      // labels
      int y=5;
      m_lblSpread.Create(chartId,name+"sp",0,5,y,80,y+16);m_lblSpread.Text("Spread: 0");m_dialog.Add(m_lblSpread);y+=18;
      m_lblTime.Create(chartId,name+"tm",0,5,y,120,y+16);m_lblTime.Text("Server: --");m_dialog.Add(m_lblTime);y+=18;
      m_lblAccount.Create(chartId,name+"ac",0,5,y,120,y+16);m_lblAccount.Text("Account: Demo");m_dialog.Add(m_lblAccount);y+=18;
      m_lblSession.Create(chartId,name+"ss",0,5,y,120,y+16);m_lblSession.Text("Session: --");m_dialog.Add(m_lblSession);y+=18;
      m_lblLastTrade.Create(chartId,name+"lt",0,5,y,250,y+16);m_lblLastTrade.Text("Last trade: --");m_dialog.Add(m_lblLastTrade);y+=18;
      m_lblRR.Create(chartId,name+"rr",0,5,y,120,y+16);m_lblRR.Text("RR: --");m_dialog.Add(m_lblRR);
      // buttons
      int bx=5,by=y+20;
      m_btnRiskPlus.Create(chartId,name+"rp",0,bx,by,bx+22,by+20);m_btnRiskPlus.Text("+R");m_dialog.Add(m_btnRiskPlus);bx+=24;
      m_btnRiskMinus.Create(chartId,name+"rm",0,bx,by,bx+22,by+20);m_btnRiskMinus.Text("-R");m_dialog.Add(m_btnRiskMinus);bx+=24;
      m_btnTPPlus.Create(chartId,name+"tp",0,bx,by,bx+22,by+20);m_btnTPPlus.Text("+TP");m_dialog.Add(m_btnTPPlus);bx+=24;
      m_btnTPMinus.Create(chartId,name+"tm2",0,bx,by,bx+22,by+20);m_btnTPMinus.Text("-TP");m_dialog.Add(m_btnTPMinus);bx+=24;
      m_btnDrag.Create(chartId,name+"dr",0,bx,by,bx+40,by+20);m_btnDrag.Text("DRAG");m_dialog.Add(m_btnDrag);
      // quick actions
      bx=5;by+=24;
      m_btnXAll.Create(chartId,name+"xa",0,bx,by,bx+50,by+20);m_btnXAll.Text("X ALL");m_dialog.Add(m_btnXAll);bx+=52;
      m_btnXProfit.Create(chartId,name+"xp",0,bx,by,bx+60,by+20);m_btnXProfit.Text("X Profit");m_dialog.Add(m_btnXProfit);bx+=62;
      m_btnXLoss.Create(chartId,name+"xl",0,bx,by,bx+50,by+20);m_btnXLoss.Text("X Loss");m_dialog.Add(m_btnXLoss);bx+=52;
      m_btnBEAll.Create(chartId,name+"be",0,bx,by,bx+50,by+20);m_btnBEAll.Text("BE ALL");m_dialog.Add(m_btnBEAll);
      return true;
   }
   void Update(string spread,string time,string account,string session,string lastTrade,string rr)
   {m_lblSpread.Text(spread);m_lblTime.Text(time);m_lblAccount.Text(account);m_lblSession.Text(session);m_lblLastTrade.Text(lastTrade);m_lblRR.Text(rr);}
   void SetTheme(ENUM_PANEL_THEME t,ENUM_SESSION s){/* color adjustments */color bg=(t==THEME_DARK)?clrBlack:clrWhite;color fg=(t==THEME_DARK)?clrWhite:clrBlack;}
   void ToggleHide(){m_hidden=!m_hidden;if(m_hidden)m_dialog.Hide();else m_dialog.Show();}
   bool IsHidden(){return m_hidden;}
   void SetPosition(int x,int y){m_x=x;m_y=y;m_dialog.Move(x,y);}
   bool OnEvent(const int id,const long &lparam,const double &dparam,const string &sparam){return m_dialog.OnEvent(id,lparam,dparam,sparam);}
   void Destroy(){m_dialog.Destroy();}
};
#endif
