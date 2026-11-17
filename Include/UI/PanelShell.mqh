//+------------------------------------------------------------------+
//|                                                   PanelShell.mqh |
//|              Mini/Drawer panel shell + UI wiring (Phase 4)       |
//+------------------------------------------------------------------+
#ifndef MM_PANEL_SHELL_MQH
#define MM_PANEL_SHELL_MQH

#include "UiStrings.mqh"
#include "StatusLog.mqh"
#include "NewsBanner.mqh"
#include "SessionBadge.mqh"
#include "PreviewOverlay.mqh"
#include "DragTool.mqh"
#include "PositionDragTool.mqh"
#include "../Core/ExecutionRouter.mqh"
#include "../Core/Contracts.mqh"
#include "../Core/ExecutionPolicy.mqh"
#include "../Guards/IGuard.mqh"
#include "../Guards/GuardEngine.mqh"
#include "../Session/SessionManager.mqh"
#include "../News/NewsManager.mqh"

class CPanelShell
{
private:
   long m_chart; string m_sym; string m_pfx;
   CUiStrings m_ui;
   bool m_mini;
   bool m_hidden;
   bool m_langFA;
   bool m_dragMode;
   int  m_x,m_y,m_wMini,m_hMini,m_wDrawer,m_hDrawer;

   string N(const string s){ return m_pfx+s; }
   void Rect(const string name,int x,int y,int w,int h,color bg,color border)
   {
      if(ObjectFind(m_chart,name)<0) ObjectCreate(m_chart,name,OBJ_RECTANGLE_LABEL,0,0,0);
      ObjectSetInteger(m_chart,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(m_chart,name,OBJPROP_XDISTANCE,x); ObjectSetInteger(m_chart,name,OBJPROP_YDISTANCE,y);
      ObjectSetInteger(m_chart,name,OBJPROP_XSIZE,w); ObjectSetInteger(m_chart,name,OBJPROP_YSIZE,h);
      ObjectSetInteger(m_chart,name,OBJPROP_BGCOLOR,bg); ObjectSetInteger(m_chart,name,OBJPROP_BORDER_TYPE,BORDER_FLAT);
      ObjectSetInteger(m_chart,name,OBJPROP_COLOR,border); ObjectSetInteger(m_chart,name,OBJPROP_BACK,false);
      ObjectSetInteger(m_chart,name,OBJPROP_SELECTABLE,false); ObjectSetInteger(m_chart,name,OBJPROP_HIDDEN,true);
      ObjectSetInteger(m_chart,name,OBJPROP_ZORDER,0);
   }
   void Lbl(const string name,int x,int y,const string text,color clr=clrWhite,int size=9)
   {
      if(ObjectFind(m_chart,name)<0) ObjectCreate(m_chart,name,OBJ_LABEL,0,0,0);
      ObjectSetInteger(m_chart,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(m_chart,name,OBJPROP_XDISTANCE,x); ObjectSetInteger(m_chart,name,OBJPROP_YDISTANCE,y);
      ObjectSetInteger(m_chart,name,OBJPROP_COLOR,clr); ObjectSetInteger(m_chart,name,OBJPROP_FONTSIZE,size);
      ObjectSetString(m_chart,name,OBJPROP_TEXT,text); ObjectSetString(m_chart,name,OBJPROP_FONT,"Arial");
      ObjectSetInteger(m_chart,name,OBJPROP_SELECTABLE,false); ObjectSetInteger(m_chart,name,OBJPROP_HIDDEN,true);
   }
   void Btn(const string name,int x,int y,int w,int h,const string text,color bg=clrSlateGray,color fg=clrWhite)
   {
      if(ObjectFind(m_chart,name)<0) ObjectCreate(m_chart,name,OBJ_BUTTON,0,0,0);
      ObjectSetInteger(m_chart,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(m_chart,name,OBJPROP_XDISTANCE,x); ObjectSetInteger(m_chart,name,OBJPROP_YDISTANCE,y);
      ObjectSetInteger(m_chart,name,OBJPROP_XSIZE,w); ObjectSetInteger(m_chart,name,OBJPROP_YSIZE,h);
      ObjectSetString(m_chart,name,OBJPROP_TEXT,text); ObjectSetInteger(m_chart,name,OBJPROP_BGCOLOR,bg);
      ObjectSetInteger(m_chart,name,OBJPROP_COLOR,fg); ObjectSetInteger(m_chart,name,OBJPROP_FONTSIZE,8);
      ObjectSetString(m_chart,name,OBJPROP_FONT,"Arial");
      ObjectSetInteger(m_chart,name,OBJPROP_SELECTABLE,false); ObjectSetInteger(m_chart,name,OBJPROP_HIDDEN,true);
      ObjectSetInteger(m_chart,name,OBJPROP_ZORDER,10);
   }
   void ShowObj(const string name,bool show)
   { if(ObjectFind(m_chart,name)>=0) ObjectSetInteger(m_chart,name,OBJPROP_TIMEFRAMES, show?OBJ_ALL_PERIODS:OBJ_NO_PERIODS); }

public:
   CNewsBanner    banner;
   CSessionBadge  badge;
   CPreviewOverlay preview;
   CStatusLog     status;

   CPanelShell(){ m_chart=0; m_sym=_Symbol; m_pfx="MM_UI_"; m_mini=true; m_hidden=false; m_langFA=false; m_dragMode=false; m_x=10; m_y=50; m_wMini=300; m_hMini=92; m_wDrawer=340; m_hDrawer=240; }

   void Init(long chart,const string symbol,int x=10,int y=50)
   {
      m_chart=chart; m_sym=symbol; m_x=x; m_y=y;
      banner.Init(chart, N("Banner"), m_x, 5);
      badge.Init(chart, N("Badge"), m_x, 28);
      preview.Init(chart, N("Preview"));
      m_ui.SetLang(m_langFA?MM_LANG_FA:MM_LANG_EN);
   }

   void SetLang(bool fa){ m_langFA=fa; m_ui.SetLang(fa?MM_LANG_FA:MM_LANG_EN); }
   bool LangFA(){ return m_langFA; }
   bool DragMode(){ return m_dragMode; }
   CUiStrings* Strings(){ return GetPointer(m_ui); }

   void Create()
   {
      int w = m_mini?m_wMini:m_wDrawer; int h = m_mini?m_hMini:m_hDrawer;
      Rect(N("BG"), m_x, m_y, w, h, C'28,32,38', C'60,70,85');
      Lbl(N("Title"), m_x+8, m_y+6, "Money Manager", clrWhite, 10);
      Btn(N("Lang"), m_x+w-46, m_y+6, 38, 18, m_langFA?"FA":"EN", clrTeal);
      Btn(N("Mini"), m_x+w-90, m_y+6, 38, 18, m_mini?m_ui.S_Drawer():m_ui.S_Mini(), clrSlateGray);
      Lbl(N("Info1"), m_x+8, m_y+28, "", clrSilver, 9);
      Lbl(N("Info2"), m_x+8, m_y+44, "", clrSilver, 9);
      // action buttons row
      int by = m_y + (m_mini?64:64);
      Btn(N("Buy"),  m_x+8,   by, 44, 20, m_ui.S_Buy(), clrSeaGreen);
      Btn(N("Sell"), m_x+56,  by, 44, 20, m_ui.S_Sell(), clrIndianRed);
      Btn(N("Drag"), m_x+104, by, 50, 20, m_ui.S_DragMode(), m_dragMode?clrDarkOrange:clrSlateGray);
      Btn(N("Send"), m_x+158, by, 56, 20, m_ui.T("Send","Send"), clrSteelBlue);
      Btn(N("Clr"),  m_x+218, by, 40, 20, m_ui.T("Clr","Clr"), clrDimGray);
      if(!m_mini)
      {
         Lbl(N("Info3"), m_x+8, m_y+88, "", clrSilver, 9);
         Lbl(N("Info4"), m_x+8, m_y+104, "", clrKhaki, 9);
         Lbl(N("Help"),  m_x+8, m_y+126, m_ui.S_Help(), clrGray, 8);
         Btn(N("RiskDn"), m_x+8,  m_y+150, 36, 20, "-R", clrSlateGray);
         Btn(N("RiskUp"), m_x+48, m_y+150, 36, 20, "+R", clrSlateGray);
         Btn(N("RRLock"), m_x+88, m_y+150, 50, 20, "RR", clrSlateGray);
      Btn(N("TplS"),   m_x+142,m_y+150, 44, 20, m_ui.T("Save","Save"), clrSlateGray);
      Btn(N("PosSel"), m_x+190,m_y+150, 48, 20, "Pos", clrDarkCyan);
      Btn(N("BE"),     m_x+242,m_y+150, 28, 20, "BE", clrTeal);
      Btn(N("Trail"),  m_x+274,m_y+150, 34, 20, "Trl", clrTeal);
      Btn(N("PClose"), m_x+8,  m_y+194, 48, 20, "50%", clrMaroon);
      Btn(N("PCAll"),  m_x+60, m_y+194, 56, 20, "All", clrMaroon);
      Lbl(N("Log"), m_x+120, m_y+198, "", clrLightGray, 8);
      }
      ApplyVisibility();
      ChartRedraw(m_chart);
   }

   void ApplyVisibility()
   {
      bool show = !m_hidden;
      string base[11]={N("BG"),N("Title"),N("Lang"),N("Mini"),N("Info1"),N("Info2"),N("Buy"),N("Sell"),N("Drag"),N("Send"),N("Clr")};
      for(int i=0;i<11;i++) ShowObj(base[i],show);
      bool dr = show && !m_mini;
      string ext[13]={N("Info3"),N("Info4"),N("Help"),N("RiskDn"),N("RiskUp"),N("RRLock"),N("TplS"),N("PosSel"),N("BE"),N("Trail"),N("PClose"),N("PCAll"),N("Log")};
      for(int i=0;i<13;i++) ShowObj(ext[i],dr);
   }

   void ToggleHide(){ m_hidden=!m_hidden; ApplyVisibility(); preview.SetVisible(!m_hidden); ChartRedraw(m_chart); }
   void ToggleMini(){ m_mini=!m_mini; Create(); }
   void SetDragMode(bool on){ m_dragMode=on; }

   void Update(CSessionManager &sess, CNewsManager &news, CDragTool &drag,
               CRiskEngine &riskEng, CStopsValidator &stops, CGuardEngine &guards,
               MM_RiskContext &ctx, MM_GuardConfig &gcfg)
   {
      if(m_hidden){ return; }
      sess.Update();
      banner.Update(news,m_ui);
      badge.Update(sess,m_ui);
      preview.Update(drag, riskEng, stops, guards, ctx, gcfg, m_ui);

      double ask=SymbolInfoDouble(m_sym,SYMBOL_ASK), bid=SymbolInfoDouble(m_sym,SYMBOL_BID);
      double pt=SymbolInfoDouble(m_sym,SYMBOL_POINT); double sp=(pt>0)?(ask-bid)/pt:0;
      string conn = TerminalInfoInteger(TERMINAL_CONNECTED)?"OK":"OFF";
      string perm = (TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) && MQLInfoInteger(MQL_TRADE_ALLOWED))?"OK":"NO";
      Lbl(N("Info1"), m_x+8, m_y+28, m_ui.S_Spread()+": "+DoubleToString(sp,1)+"  "+m_ui.S_Connection()+":"+conn+"/"+perm, clrSilver, 9);
      string modeStr = drag.Active()? (drag.IsBuy()?m_ui.S_Buy():m_ui.S_Sell()) : m_ui.T("Idle","Idle");
      string smode = (drag.SizingMode()==SIZING_AUTO_RISK)? (m_ui.S_Risk()+"%") : m_ui.S_Lot();
      Lbl(N("Info2"), m_x+8, m_y+44, m_ui.T("Mode","Mode")+": "+modeStr+"  "+smode+": "+DoubleToString(drag.RiskValue(),2), clrSilver, 9);
      if(!m_mini)
      {
         string rs = drag.Active()? (m_ui.S_Entry()+"="+DoubleToString(drag.Entry(),(int)SymbolInfoInteger(m_sym,SYMBOL_DIGITS))+" SL="+DoubleToString(drag.SL(),(int)SymbolInfoInteger(m_sym,SYMBOL_DIGITS))) : "";
         Lbl(N("Info3"), m_x+8, m_y+88, rs, clrSilver, 9);
         MM_RiskResult rr = preview.LastRisk();
         string rs2 = drag.Active()? (m_ui.S_Lot()+"="+DoubleToString(rr.lot,2)+" "+m_ui.S_Risk()+"="+DoubleToString(rr.riskPercent,2)+"% "+m_ui.S_RR()+"="+DoubleToString(rr.rr,2)) : "";
         color c = (!rr.valid || rr.blocked || preview.LastGuards().hasBlock)?clrTomato:(preview.LastGuards().hasWarn?clrKhaki:clrLightGreen);
         Lbl(N("Info4"), m_x+8, m_y+104, rs2, c, 9);
         Lbl(N("Log"), m_x+8, m_y+174, status.LastLine(), clrLightGray, 8);
      }
      Btn(N("Drag"), m_x+104, m_y + (m_mini?64:64), 50, 20, m_ui.S_DragMode(), m_dragMode?clrDarkOrange:clrSlateGray);
      ChartRedraw(m_chart);
   }

   // Handle UI button clicks & hotkeys. Returns true if event consumed.
   bool OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam,
                     CDragTool &drag, CExecutionRouter &router, MM_RiskContext &ctx, MM_GuardConfig &gcfg, MM_ExecPolicy &policy,
                     CPositionDragTool &posDrag)
   {
      // delegate drag object events first
      drag.OnChartEvent(id,lparam,dparam,sparam);
      posDrag.OnChartEvent(id,lparam,dparam,sparam);

      if(id==CHARTEVENT_OBJECT_CLICK)
      {
         if(sparam==N("Buy")){ m_dragMode=true; drag.Activate(true); status.Info("UI","Buy drag"); return true; }
         if(sparam==N("Sell")){ m_dragMode=true; drag.Activate(false); status.Info("UI","Sell drag"); return true; }
         if(sparam==N("Drag")){ m_dragMode=!m_dragMode; if(!m_dragMode){} status.Info("UI",m_dragMode?"Drag on":"Drag off"); return true; }
         if(sparam==N("Clr")){ drag.Clear(); status.Info("UI","Cleared"); return true; }
         if(sparam==N("Mini")){ ToggleMini(); return true; }
         if(sparam==N("Lang")){ SetLang(!m_langFA); Create(); return true; }
         if(sparam==N("RiskUp")){ drag.AdjustRisk(0.25); return true; }
         if(sparam==N("RiskDn")){ drag.AdjustRisk(-0.25); return true; }
         if(sparam==N("Send")){ TrySend(drag, router, ctx, gcfg, policy); return true; }
         if(sparam==N("PosSel")){
            if(!posDrag.SelectCurrent(m_sym,0)) posDrag.SelectCurrent("",0);
            status.Info("POS", posDrag.Active()?("Selected #"+(string)posDrag.Ticket()):"No position");
            return true;
         }
         if(sparam==N("BE")){
            if(posDrag.Active()){
               bool ok=posDrag.MoveToBE(0);
               status.Info("BE", ok?"BE applied":"BE not applied");
               if(!ok && posDrag.MultiOptIn()){
                  int r=MessageBox("Apply BE to all positions (symbol)?","MoneyManager",MB_YESNO|MB_ICONQUESTION);
                  if(r==IDYES){ /* multi apply requires opt-in+confirm; simple per-pos loop */
                     int c=0; for(int i=PositionsTotal()-1;i>=0;i--){ ulong t=PositionGetTicket(i); if(t==0) continue; if(PositionGetString(POSITION_SYMBOL)!=m_sym) continue; if(posDrag.SelectTicket(t) && posDrag.MoveToBE(0)) c++; }
                     status.Info("BE","Multi BE: "+(string)c);
                  }
               }
            } else status.Warn("BE","No selected position");
            return true;
         }
         if(sparam==N("Trail")){
            if(posDrag.Active()){ bool ok=posDrag.ApplyTrailOnce(TRAIL_FIXED,20); status.Info("TRAIL", ok?"Trail applied":"Trail not applied"); }
            else status.Warn("TRAIL","No selected position");
            return true;
         }
         if(sparam==N("PClose")){
            if(posDrag.Active()){
               int r=MessageBox("Close 50% of selected position?","MoneyManager",MB_YESNO|MB_ICONWARNING);
               if(r==IDYES){ bool ok=posDrag.PartialClose(50.0); status.Info("CLOSE", ok?"Partial close ok":"Partial close failed"); }
            } else status.Warn("CLOSE","No selected position");
            return true;
         }
         if(sparam==N("PCAll")){
            int r=MessageBox("Close ALL positions on current symbol? (opt-in action)","MoneyManager",MB_YESNO|MB_ICONWARNING);
            if(r==IDYES){
               int c=0; for(int i=PositionsTotal()-1;i>=0;i--){ ulong t=PositionGetTicket(i); if(t==0) continue; if(PositionGetString(POSITION_SYMBOL)!=m_sym) continue; if(posDrag.SelectTicket(t) && posDrag.CloseSelected()) c++; }
               status.Info("CLOSE","Closed: "+(string)c);
            }
            return true;
         }
      }

      if(id==CHARTEVENT_KEYDOWN)
      {
         int k=(int)lparam;
         if(k==72){ ToggleHide(); return true; } // H
         if(k==27){ drag.Deactivate(); m_dragMode=false; status.Info("UI","Cancel"); return true; } // Esc
         if(k==13){ TrySend(drag, router, ctx, gcfg, policy); return true; } // Enter
         if(k==68){ m_dragMode=!m_dragMode; if(m_dragMode && !drag.Active()) drag.Activate(true); return true; } // D
         if(k==66){ m_dragMode=true; drag.Activate(true); return true; } // B
         if(k==83){ m_dragMode=true; drag.Activate(false); return true; } // S
         if(k==80){ if(!posDrag.SelectCurrent(m_sym,0)) posDrag.SelectCurrent("",0); status.Info("POS", posDrag.Active()?"Selected":"No position"); return true; } // P
      }
      return false;
   }

   bool TrySend(CDragTool &drag, CExecutionRouter &router, MM_RiskContext &ctx, MM_GuardConfig &gcfg, MM_ExecPolicy &policy)
   {
      if(!drag.Active() || !drag.Ready()){ status.Warn("SEND","No active plan"); return false; }
      if(drag.InstabilityWarn())
      {
         int r = MessageBox(m_ui.T("Spread/price unstable. Send anyway?","Unstable. Send anyway?"), "MoneyManager", MB_YESNO|MB_ICONWARNING);
         if(r!=IDYES){ status.Info("SEND",m_ui.S_Cancelled()); return false; }
      }
      MM_ExecResult chk; MM_TradePlan plan; drag.BuildPlan(plan);
      // preflight preview (includes guards) to know if blocked
      if(!router.Preflight(plan, ctx, policy, chk, gcfg))
      {
         status.Warn("BLOCK", chk.reasonCode+": "+chk.messageEN);
         MessageBox(chk.reasonCode+"\n"+chk.messageEN, "MoneyManager - "+m_ui.S_Blocked(), MB_OK|MB_ICONSTOP);
         return false;
      }
      string summary = (drag.IsBuy()?"BUY ":"SELL ")+DoubleToString(chk.risk.lot,2)+" "+plan.symbol+
                       "\nSL="+DoubleToString(plan.slPrice,(int)SymbolInfoInteger(plan.symbol,SYMBOL_DIGITS))+
                       " TP="+(plan.tpCount>0?DoubleToString(plan.tpPrice[0],(int)SymbolInfoInteger(plan.symbol,SYMBOL_DIGITS)):"-")+
                       "\n"+m_ui.S_Risk()+"="+DoubleToString(chk.risk.riskPercent,2)+"% ($"+DoubleToString(chk.risk.riskMoney,2)+") RR="+DoubleToString(chk.risk.rr,2)+
                       "\n"+m_ui.S_Confirm();
      int res = MessageBox(summary, "MoneyManager", MB_YESNO|MB_ICONQUESTION);
      if(res!=IDYES){ status.Info("SEND",m_ui.S_Cancelled()); return false; }
      MM_ExecResult out; drag.BuildPlan(plan);
      bool ok = router.Send(plan, ctx, policy, out, gcfg);
      if(ok){ status.Info("SEND",m_ui.S_Sent()+" "+out.reasonCode); drag.Deactivate(); m_dragMode=false; }
      else { status.Warn("SEND",out.reasonCode+": "+out.messageEN); MessageBox(out.reasonCode+"\n"+out.messageEN, "MoneyManager", MB_OK|MB_ICONERROR); }
      return ok;
   }

   void Destroy()
   {
      banner.Destroy(); badge.Destroy(); preview.Destroy();
      string objs[24]={N("BG"),N("Title"),N("Lang"),N("Mini"),N("Info1"),N("Info2"),N("Buy"),N("Sell"),N("Drag"),N("Send"),N("Clr"),N("Info3"),N("Info4"),N("Help"),N("RiskDn"),N("RiskUp"),N("RRLock"),N("TplS"),N("PosSel"),N("BE"),N("Trail"),N("PClose"),N("PCAll"),N("Log")};
      for(int i=0;i<24;i++) if(ObjectFind(m_chart,objs[i])>=0) ObjectDelete(m_chart,objs[i]);
      ChartRedraw(m_chart);
   }
};

#endif // MM_PANEL_SHELL_MQH
