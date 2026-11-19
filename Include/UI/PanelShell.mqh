//+------------------------------------------------------------------+
//|                                                   PanelShell.mqh |
//|          Mini/Drawer panel shell + UI wiring (Phase 4/5/6)       |
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
#include "../Statistics/Statistics.mqh"
#include "../Profiles/Profiles.mqh"
#include "../Session/SessionManager.mqh"
#include "../News/NewsManager.mqh"

typedef void (*MM_StoreResolveHandler)();

class CPanelShell
{
private:
   long m_chart; string m_sym; string m_pfx;
   CUiStrings m_ui;
   bool m_mini;
   bool m_hidden;
   bool m_langFA;
   bool m_dragMode;
   int  m_tab; // 0=main, 1=stats
   int  m_x,m_y,m_wMini,m_hMini,m_wDrawer,m_hDrawer;
   CStatistics     *m_stats;
   CProfileManager *m_profiles;
   ENUM_MM_ACCOUNT_MODE m_accMode;
   bool m_storeBlocked;
   string m_storeBlockedReason;
   MM_StoreResolveHandler m_storeResolveHandler;

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
   void Lbl(const string name,int x,int y,const string text,color clr=clrWhite,int size=9,const string tip="")
   {
      if(ObjectFind(m_chart,name)<0) ObjectCreate(m_chart,name,OBJ_LABEL,0,0,0);
      ObjectSetInteger(m_chart,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(m_chart,name,OBJPROP_XDISTANCE,x); ObjectSetInteger(m_chart,name,OBJPROP_YDISTANCE,y);
      ObjectSetInteger(m_chart,name,OBJPROP_COLOR,clr); ObjectSetInteger(m_chart,name,OBJPROP_FONTSIZE,size);
      ObjectSetString(m_chart,name,OBJPROP_TEXT,text); ObjectSetString(m_chart,name,OBJPROP_FONT,"Arial");
      ObjectSetInteger(m_chart,name,OBJPROP_SELECTABLE,false); ObjectSetInteger(m_chart,name,OBJPROP_HIDDEN,true);
      if(tip!="") ObjectSetString(m_chart,name,OBJPROP_TOOLTIP,tip);
   }
   void Btn(const string name,int x,int y,int w,int h,const string text,color bg=clrSlateGray,color fg=clrWhite,const string tip="")
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
      if(tip!="") ObjectSetString(m_chart,name,OBJPROP_TOOLTIP,tip);
   }
   void ShowObj(const string name,bool show)
   { if(ObjectFind(m_chart,name)>=0) ObjectSetInteger(m_chart,name,OBJPROP_TIMEFRAMES, show?OBJ_ALL_PERIODS:OBJ_NO_PERIODS); }

public:
   CNewsBanner    banner;
   CSessionBadge  badge;
   CPreviewOverlay preview;
   CStatusLog     status;

   CPanelShell(){ m_chart=0; m_sym=_Symbol; m_pfx="MM_UI_"; m_mini=true; m_hidden=false; m_langFA=false; m_dragMode=false; m_tab=0; m_x=10; m_y=50; m_wMini=300; m_hMini=92; m_wDrawer=340; m_hDrawer=250; m_stats=NULL; m_profiles=NULL; m_accMode=ACCOUNT_PERSONAL; m_storeBlocked=false; m_storeBlockedReason=""; m_storeResolveHandler=NULL; }

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
   void SetStats(CStatistics &s){ m_stats=GetPointer(s); }
   void SetProfiles(CProfileManager &p){ m_profiles=GetPointer(p); }
   void SetAccountMode(ENUM_MM_ACCOUNT_MODE m){ m_accMode=m; }
   void SetStoreResolutionHandler(MM_StoreResolveHandler handler){ m_storeResolveHandler=handler; }
   void SetStoreBlockedState(bool blocked, const string reason){ m_storeBlocked=blocked; m_storeBlockedReason=reason; }
   bool StoreBlocked(){ return m_storeBlocked; }
   string StoreBlockedReason(){ return m_storeBlockedReason; }

   void Create()
   {
      int w = m_mini?m_wMini:m_wDrawer; int h = m_mini?m_hMini:m_hDrawer;
      Rect(N("BG"), m_x, m_y, w, h, C'28,32,38', C'60,70,85');
      Lbl(N("Title"), m_x+8, m_y+6, "Money Manager ["+ModeLabel()+"]", clrWhite, 10);
      Btn(N("Lang"), m_x+w-46, m_y+6, 38, 18, m_langFA?"FA":"EN", clrTeal, clrWhite, m_ui.Tip_Lang());
      Btn(N("Mini"), m_x+w-90, m_y+6, 38, 18, m_mini?m_ui.S_Drawer():m_ui.S_Mini(), clrSlateGray, clrWhite, m_ui.Tip_Mini());
      Lbl(N("Info1"), m_x+8, m_y+28, "", clrSilver, 9);
      Lbl(N("Info2"), m_x+8, m_y+44, "", clrSilver, 9);
      int by = m_y + 64;
      Btn(N("Buy"),  m_x+8,   by, 44, 20, m_ui.S_Buy(), clrSeaGreen, clrWhite, m_ui.Tip_Buy());
      Btn(N("Sell"), m_x+56,  by, 44, 20, m_ui.S_Sell(), clrIndianRed, clrWhite, m_ui.Tip_Sell());
      Btn(N("Drag"), m_x+104, by, 50, 20, m_ui.S_DragMode(), m_dragMode?clrDarkOrange:clrSlateGray, clrWhite, m_ui.Tip_Drag());
      Btn(N("Send"), m_x+158, by, 56, 20, m_ui.S_Send(), clrSteelBlue, clrWhite, m_ui.Tip_Send());
      Btn(N("Clr"),  m_x+218, by, 40, 20, m_ui.S_Clear(), clrDimGray, clrWhite, m_ui.Tip_Clear());
      Btn(N("Resolve"), m_x+262, by, 52, 20, m_ui.S_Resolve(), clrDarkOrange, clrWhite, m_ui.Tip_Resolve());
      if(!m_mini)
      {
         Btn(N("TabM"), m_x+262, m_y+28, 36, 16, m_ui.S_Main(), (m_tab==0)?clrDarkSlateBlue:clrSlateGray, clrWhite, m_ui.Tip_TabMain());
         Btn(N("TabS"), m_x+262, m_y+46, 36, 16, m_ui.S_Stats(), (m_tab==1)?clrDarkSlateBlue:clrSlateGray, clrWhite, m_ui.Tip_TabStats());

         Lbl(N("Info3"), m_x+8, m_y+88, "", clrSilver, 9);
         Lbl(N("Info4"), m_x+8, m_y+104, "", clrKhaki, 9);
         Lbl(N("Help"),  m_x+8, m_y+120, m_ui.S_Help(), clrGray, 8);

         Btn(N("RiskDn"), m_x+8,  m_y+142, 36, 18, "-R", clrSlateGray, clrWhite, m_ui.Tip_RiskDn());
         Btn(N("RiskUp"), m_x+48, m_y+142, 36, 18, "+R", clrSlateGray, clrWhite, m_ui.Tip_RiskUp());
         Btn(N("RRLock"), m_x+88, m_y+142, 50, 18, "RR", clrSlateGray, clrWhite, m_ui.T("Toggle RR lock","تغییر قفل نسبت R"));
         Btn(N("TplS"),   m_x+142,m_y+142, 44, 18, m_ui.S_Save(), clrSlateGray, clrWhite, m_ui.Tip_Save());
         Btn(N("PosSel"), m_x+190,m_y+142, 48, 18, m_ui.S_Pos(), clrDarkCyan, clrWhite, m_ui.Tip_Pos());
         Btn(N("BE"),     m_x+242,m_y+142, 28, 18, m_ui.S_BE(), clrTeal, clrWhite, m_ui.Tip_BE());
         Btn(N("Trail"),  m_x+274,m_y+142, 34, 18, m_ui.S_Trail(), clrTeal, clrWhite, m_ui.Tip_Trail());
         Btn(N("PClose"), m_x+8,  m_y+164, 48, 18, m_ui.S_Partial(), clrMaroon, clrWhite, m_ui.Tip_Partial());
         Btn(N("PCAll"),  m_x+60, m_y+164, 56, 18, m_ui.S_CloseAll(), clrMaroon, clrWhite, m_ui.Tip_CloseAll());

         Btn(N("CSV"),   m_x+8,   m_y+142, 44, 18, m_ui.S_CSV(), clrDarkOliveGreen, clrWhite, m_ui.Tip_CSV());
         Btn(N("ProfN"), m_x+56,  m_y+142, 52, 18, m_ui.S_Next(), clrDarkSlateBlue, clrWhite, m_ui.Tip_ProfileNext());
         Btn(N("PrEx"),  m_x+112, m_y+142, 52, 18, m_ui.S_Export(), clrDarkSlateBlue, clrWhite, m_ui.Tip_ProfileExport());
         Btn(N("PrIm"),  m_x+168, m_y+142, 52, 18, m_ui.S_Import(), clrDarkSlateBlue, clrWhite, m_ui.Tip_ProfileImport());

         Lbl(N("Log"), m_x+8, m_y+188, "", clrLightGray, 8);
         Lbl(N("State"), m_x+8, m_y+204, "", clrTomato, 8);
      }
      ApplyVisibility();
      ChartRedraw(m_chart);
   }

   void ApplyVisibility()
   {
      bool show = !m_hidden;
      string base[12]={N("BG"),N("Title"),N("Lang"),N("Mini"),N("Info1"),N("Info2"),N("Buy"),N("Sell"),N("Drag"),N("Send"),N("Clr"),N("Resolve")};
      for(int i=0;i<12;i++) ShowObj(base[i],show);
      ShowObj(N("Resolve"), show && m_storeBlocked);
      bool dr = show && !m_mini;
      string tabsAndInfo[7]={N("TabM"),N("TabS"),N("Info3"),N("Info4"),N("Help"),N("Log"),N("State")};
      for(int i=0;i<7;i++) ShowObj(tabsAndInfo[i],dr);
      bool mainTab = dr && (m_tab==0);
      bool statsTab = dr && (m_tab==1);
      string mainBtns[9]={N("RiskDn"),N("RiskUp"),N("RRLock"),N("TplS"),N("PosSel"),N("BE"),N("Trail"),N("PClose"),N("PCAll")};
      for(int i=0;i<9;i++) ShowObj(mainBtns[i],mainTab);
      string statsBtns[4]={N("CSV"),N("ProfN"),N("PrEx"),N("PrIm")};
      for(int i=0;i<4;i++) ShowObj(statsBtns[i],statsTab);
   }

   void ToggleHide(){ m_hidden=!m_hidden; ApplyVisibility(); preview.SetVisible(!m_hidden); ChartRedraw(m_chart); }
   void ToggleMini(){ m_mini=!m_mini; Create(); }
   void SetDragMode(bool on){ m_dragMode=on; }
   void SetTab(int t){ m_tab=(t==1)?1:0; Create(); }

   string ModeLabel()
   {
      if(m_accMode==ACCOUNT_PROP) return "PROP";
      if(m_accMode==ACCOUNT_CRYPTO) return "CRYPTO";
      return "PERSONAL";
   }

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
      string modeStr = drag.Active()? (drag.IsBuy()?m_ui.S_Buy():m_ui.S_Sell()) : m_ui.S_Idle();
      string smode = (drag.SizingMode()==SIZING_AUTO_RISK)? (m_ui.S_Risk()+"%") : m_ui.S_Lot();
      string blockedTag = m_storeBlocked ? ("  ["+m_ui.S_Blocked()+"]") : "";
      Lbl(N("Info2"), m_x+8, m_y+44, m_ui.S_Mode()+": "+modeStr+"  "+smode+": "+DoubleToString(drag.RiskValue(),2)+blockedTag, m_storeBlocked?clrTomato:clrSilver, 9);

      if(!m_mini)
      {
         if(m_tab==1)
         {
            MM_Kpi k; k.Reset();
            bool has=false;
            if(m_stats!=NULL){ m_stats.GetKpiForMode(m_accMode, k); if(k.trades==0) m_stats.GetKpi(k); has=true; }
            string prof = "-";
            if(m_profiles!=NULL){ MM_ProfileRecord pr; if(m_profiles.GetActive(pr)) prof=pr.profile.name; }
            // Phase 7: transparent, diagnosable personal/protection settings + baseline/peak context (server-time periods).
            string limDL = (gcfg.dailyLossLimitPct>0)?(DoubleToString(gcfg.dailyLossPct,1)+"/"+DoubleToString(gcfg.dailyLossLimitPct,1)+"%"):"off";
            string limWL = (gcfg.weeklyLossLimitPct>0)?(DoubleToString(gcfg.weeklyLossPct,1)+"/"+DoubleToString(gcfg.weeklyLossLimitPct,1)+"%"):"off";
            string limML = (gcfg.monthlyLossLimitPct>0)?(DoubleToString(gcfg.monthlyLossPct,1)+"/"+DoubleToString(gcfg.monthlyLossLimitPct,1)+"%"):"off";
            string limDD = (gcfg.maxDrawdownPct>0)?(DoubleToString(gcfg.currentDrawdownPct,1)+"/"+DoubleToString(gcfg.maxDrawdownPct,1)+"%"):"off";
            string limTr = (gcfg.maxTradesPerDay>0)?(IntegerToString(gcfg.tradesToday)+"/"+IntegerToString(gcfg.maxTradesPerDay)):(IntegerToString(gcfg.tradesToday)+"/-");
            string limCD = gcfg.inCooldown ? "ON" : "off";
            string limCL = (gcfg.maxConsecLoss>0)?(IntegerToString(gcfg.consecLosses)+"/"+IntegerToString(gcfg.maxConsecLoss)):(IntegerToString(gcfg.consecLosses)+"/-");

            string l3 = m_ui.S_Trades()+":"+(has?IntegerToString(k.trades):"0")+" "+m_ui.S_WinRate()+":"+DoubleToString(k.winRate,1)+"% "+m_ui.S_PF()+":"+DoubleToString(k.profitFactor,2)+" "+m_ui.S_Net()+":"+DoubleToString(k.netProfit,2);
            string l4 = "DL "+limDL+" WL "+limWL+" ML "+limML+" DD "+limDD;
            string l5 = "T "+limTr+" CL "+limCL+" CD "+limCD+" ["+ModeLabel()+"/"+prof+"]";
            Lbl(N("Info3"), m_x+8, m_y+88, l3, clrSilver, 9);
            Lbl(N("Info4"), m_x+8, m_y+104, l4, clrKhaki, 9);
            Lbl(N("Help"),  m_x+8, m_y+120, l5, clrLightGray, 8);
            Lbl(N("Log"),   m_x+8, m_y+188, status.LastLine(), clrLightGray, 8);
         }
         else
         {
            string tpDisp = drag.Active()? (drag.TpCount()>1?("x"+(string)drag.TpCount()):DoubleToString(drag.TP1(),(int)SymbolInfoInteger(m_sym,SYMBOL_DIGITS))) : "";
            string rs = drag.Active()? (m_ui.S_Entry()+"="+DoubleToString(drag.Entry(),(int)SymbolInfoInteger(m_sym,SYMBOL_DIGITS))+" SL="+DoubleToString(drag.SL(),(int)SymbolInfoInteger(m_sym,SYMBOL_DIGITS))+" TP="+tpDisp) : "";
            Lbl(N("Info3"), m_x+8, m_y+88, rs, clrSilver, 9);
            MM_RiskResult rr = preview.LastRisk();
            string rs2 = drag.Active()? (m_ui.S_Lot()+"="+DoubleToString(rr.lot,2)+" "+m_ui.S_Risk()+"="+DoubleToString(rr.riskPercent,2)+"% "+m_ui.S_RR()+"="+DoubleToString(rr.rr,2)) : "";
            color c = (!rr.valid || rr.blocked || preview.LastGuards().hasBlock)?clrTomato:(preview.LastGuards().hasWarn?clrKhaki:clrLightGreen);
            Lbl(N("Info4"), m_x+8, m_y+104, rs2, c, 9);
            // Phase 7: quick protection transparency even on main tab when idle.
            string prof = "-"; if(m_profiles!=NULL){ MM_ProfileRecord pr; if(m_profiles.GetActive(pr)) prof=pr.profile.name; }
            string lim = drag.Active()? m_ui.S_Help() : ("DL "+DoubleToString(gcfg.dailyLossPct,1)+"/"+(gcfg.dailyLossLimitPct>0?DoubleToString(gcfg.dailyLossLimitPct,1):"-")+" DD "+DoubleToString(gcfg.currentDrawdownPct,1)+"/"+(gcfg.maxDrawdownPct>0?DoubleToString(gcfg.maxDrawdownPct,1):"-")+" ["+ModeLabel()+"/"+prof+"]");
            Lbl(N("Help"),  m_x+8, m_y+120, lim, drag.Active()?clrGray:clrLightGray, 8);
            Lbl(N("Log"),   m_x+8, m_y+188, status.LastLine(), clrLightGray, 8);
         }
         string st = m_storeBlocked ? (m_ui.S_StateBlocked()+": "+m_storeBlockedReason) : "";
         Lbl(N("State"), m_x+8, m_y+204, st, clrTomato, 8);
         Btn(N("TabM"), m_x+262, m_y+28, 36, 16, m_ui.S_Main(), (m_tab==0)?clrDarkSlateBlue:clrSlateGray);
         Btn(N("TabS"), m_x+262, m_y+46, 36, 16, m_ui.S_Stats(), (m_tab==1)?clrDarkSlateBlue:clrSlateGray);
      }
      Btn(N("Drag"), m_x+104, m_y + 64, 50, 20, m_ui.S_DragMode(), m_dragMode?clrDarkOrange:clrSlateGray);
      Btn(N("Resolve"), m_x+262, m_y + 64, 52, 20, m_ui.S_Resolve(), m_storeBlocked?clrDarkOrange:clrSlateGray, clrWhite, m_ui.Tip_Resolve());
      ApplyVisibility();
      ChartRedraw(m_chart);
   }

   bool OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam,
                     CDragTool &drag, CExecutionRouter &router, MM_RiskContext &ctx, MM_GuardConfig &gcfg, MM_ExecPolicy &policy,
                     CPositionDragTool &posDrag)
   {
      drag.OnChartEvent(id,lparam,dparam,sparam);
      posDrag.OnChartEvent(id,lparam,dparam,sparam);

      if(id==CHARTEVENT_OBJECT_CLICK)
      {
         if(sparam==N("TabM")){ SetTab(0); return true; }
         if(sparam==N("TabS")){ SetTab(1); return true; }
         if(sparam==N("Buy")){ m_dragMode=true; drag.Activate(true); status.Info("UI","Buy drag"); return true; }
         if(sparam==N("Sell")){ m_dragMode=true; drag.Activate(false); status.Info("UI","Sell drag"); return true; }
         if(sparam==N("Drag")){ m_dragMode=!m_dragMode; status.Info("UI",m_dragMode?"Drag on":"Drag off"); return true; }
         if(sparam==N("Clr")){ drag.Clear(); status.Info("UI","Cleared"); return true; }
         if(sparam==N("Mini")){ ToggleMini(); return true; }
         if(sparam==N("Lang")){ SetLang(!m_langFA); Create(); return true; }
         if(sparam==N("RiskUp")){ drag.AdjustRisk(0.25); return true; }
         if(sparam==N("RiskDn")){ drag.AdjustRisk(-0.25); return true; }
         if(sparam==N("Send")){ TrySend(drag, router, ctx, gcfg, policy); return true; }
         if(sparam==N("Resolve")){
            status.Info("STATE","Explicit resolution requested");
            if(m_storeResolveHandler!=NULL) m_storeResolveHandler();
            else status.Warn("STATE","No resolution handler available");
            return true;
         }
         if(sparam==N("PosSel")){
            if(!posDrag.SelectCurrent(m_sym,0)) posDrag.SelectCurrent("",0);
            status.Info("POS", posDrag.Active()?("Selected #"+(string)posDrag.Ticket()):"No position");
            return true;
         }
         if(sparam==N("BE")){
            if(posDrag.Active()){ bool ok=posDrag.MoveToBE(0); status.Info("BE", ok?"BE applied":"BE not applied"); }
            else status.Warn("BE","No selected position");
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
         if(sparam==N("CSV")){
            if(m_stats!=NULL){ bool ok=m_stats.ExportCSV("MoneyManager_trades.csv", m_accMode, false); status.Info("CSV", ok?"CSV exported":"CSV export failed"); }
            else status.Warn("CSV","Stats not available");
            return true;
         }
         if(sparam==N("ProfN")){
            if(m_profiles!=NULL){ m_profiles.NextProfile(); MM_ProfileRecord pr; m_profiles.GetActive(pr); status.Info("PROFILE","Active: "+pr.profile.name); }
            return true;
         }
         if(sparam==N("PrEx")){
            if(m_profiles!=NULL){ bool ok=m_profiles.ExportProfile("", ""); status.Info("PROFILE", ok?"Profile exported":"Profile export failed"); }
            return true;
         }
         if(sparam==N("PrIm")){
            if(m_profiles!=NULL){ bool ok=m_profiles.ImportProfile("MoneyManager\\profile_import.json"); status.Info("PROFILE", ok?"Profile imported":"Import failed (MoneyManager\\profile_import.json)"); }
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
         if(k==84){ if(drag.Active()){ int n=drag.TpCount()+1; if(n>MM_MAX_TP_LEVELS) n=1; drag.SetTpCount(n); status.Info("TP","TP targets: "+IntegerToString(n)); } return true; } // T cycle TP count (1..max)
         if(k==80){ if(!posDrag.SelectCurrent(m_sym,0)) posDrag.SelectCurrent("",0); status.Info("POS", posDrag.Active()?"Selected":"No position"); return true; } // P
         if(k==75){ SetTab(m_tab==0?1:0); return true; } // K toggle stats
      }
      return false;
   }

   bool TrySend(CDragTool &drag, CExecutionRouter &router, MM_RiskContext &ctx, MM_GuardConfig &gcfg, MM_ExecPolicy &policy)
   {
      if(m_storeBlocked)
      {
         status.Warn("BLOCK", "STATE_NOT_OPERATIONAL: explicit resolution required");
         MessageBox(m_ui.Msg_StateBlocked()+"\n\n"+m_storeBlockedReason, "MoneyManager - "+m_ui.S_Blocked(), MB_OK|MB_ICONSTOP);
         return false;
      }
      if(!drag.Active() || !drag.Ready()){ status.Warn("SEND","No active plan"); return false; }
      if(drag.InstabilityWarn())
      {
         int r = MessageBox(m_ui.T("Spread/price unstable. Send anyway?","اسپرد/قیمت ناپایدار است. ارسال شود؟"), "MoneyManager", MB_YESNO|MB_ICONWARNING);
         if(r!=IDYES){ status.Info("SEND",m_ui.S_Cancelled()); return false; }
      }
      MM_ExecResult chk; MM_TradePlan plan; drag.BuildPlan(plan);
      if(!router.Preflight(plan, ctx, policy, chk, gcfg))
      {
         status.Warn("BLOCK", chk.reasonCode+": "+chk.messageEN);
         MessageBox(chk.reasonCode+"\n"+chk.messageEN, "MoneyManager - "+m_ui.S_Blocked(), MB_OK|MB_ICONSTOP);
         return false;
      }
      if(m_stats!=NULL) m_stats.RegisterPlannedRisk(plan.symbol, chk.risk.riskMoney, m_accMode);
      string tpSummary = "-";
      if(plan.tpCount==1) tpSummary = DoubleToString(plan.tpPrice[0],(int)SymbolInfoInteger(plan.symbol,SYMBOL_DIGITS));
      else if(plan.tpCount>1){ tpSummary = IntegerToString(plan.tpCount)+" TPs"; }
      string summary = (drag.IsBuy()?"BUY ":"SELL ")+DoubleToString(chk.risk.lot,2)+" "+plan.symbol+
                       "\nSL="+DoubleToString(plan.slPrice,(int)SymbolInfoInteger(plan.symbol,SYMBOL_DIGITS))+
                       " TP="+tpSummary+
                       "\n"+m_ui.S_Risk()+"="+DoubleToString(chk.risk.riskPercent,2)+"% ($"+DoubleToString(chk.risk.riskMoney,2)+") RR="+DoubleToString(chk.risk.rr,2)+
                       "\n"+m_ui.S_Confirm();
      int res = MessageBox(summary, "MoneyManager", MB_YESNO|MB_ICONQUESTION);
      if(res!=IDYES){ status.Info("SEND",m_ui.S_Cancelled()); return false; }
      MM_ExecResult out; drag.BuildPlan(plan);
      if(m_stats!=NULL) m_stats.RegisterPlannedRisk(plan.symbol, chk.risk.riskMoney, m_accMode);
      bool ok = router.Send(plan, ctx, policy, out, gcfg);
      if(ok){ status.Info("SEND",m_ui.S_Sent()+" "+out.reasonCode); drag.Deactivate(); m_dragMode=false; }
      else { status.Warn("SEND",out.reasonCode+": "+out.messageEN); MessageBox(out.reasonCode+"\n"+out.messageEN, "MoneyManager", MB_OK|MB_ICONERROR); }
      return ok;
   }

   void Destroy()
   {
      banner.Destroy(); badge.Destroy(); preview.Destroy();
      string objs[32]={N("BG"),N("Title"),N("Lang"),N("Mini"),N("Info1"),N("Info2"),N("Buy"),N("Sell"),N("Drag"),N("Send"),N("Clr"),N("Resolve"),N("Info3"),N("Info4"),N("Help"),N("RiskDn"),N("RiskUp"),N("RRLock"),N("TplS"),N("PosSel"),N("BE"),N("Trail"),N("PClose"),N("PCAll"),N("Log"),N("State"),N("TabM"),N("TabS"),N("CSV"),N("ProfN"),N("PrEx"),N("PrIm")};
      for(int i=0;i<32;i++) if(ObjectFind(m_chart,objs[i])>=0) ObjectDelete(m_chart,objs[i]);
      ChartRedraw(m_chart);
   }
};

#endif // MM_PANEL_SHELL_MQH
