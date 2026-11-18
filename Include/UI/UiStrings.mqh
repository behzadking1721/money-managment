//+------------------------------------------------------------------+
//|                                                   UiStrings.mqh  |
//|                    Bilingual UI strings EN/FA (Phase 4/6)        |
//+------------------------------------------------------------------+
#ifndef MM_UI_STRINGS_MQH
#define MM_UI_STRINGS_MQH

enum ENUM_MM_UI_LANG { MM_LANG_EN=0, MM_LANG_FA=1 };

class CUiStrings
{
private:
   ENUM_MM_UI_LANG m_lang;
public:
   CUiStrings(){ m_lang=MM_LANG_EN; }
   void SetLang(ENUM_MM_UI_LANG lang){ m_lang=lang; }
   ENUM_MM_UI_LANG Lang(){ return m_lang; }
   string T(const string en,const string fa){ return (m_lang==MM_LANG_FA)?fa:en; }

   string S_Spread(){ return T("Spread","Spread"); }
   string S_Risk(){ return T("Risk","Risk"); }
   string S_Lot(){ return T("Lot","Lot"); }
   string S_RR(){ return T("R:R","R:R"); }
   string S_Entry(){ return T("Entry","Entry"); }
   string S_SL(){ return T("SL","SL"); }
   string S_TP(){ return T("TP","TP"); }
   string S_Buy(){ return T("BUY","BUY"); }
   string S_Sell(){ return T("SELL","SELL"); }
   string S_Market(){ return T("Market","Market"); }
   string S_Pending(){ return T("Pending","Pending"); }
   string S_Ready(){ return T("Ready","Ready"); }
   string S_Blocked(){ return T("BLOCKED","BLOCKED"); }
   string S_Warn(){ return T("WARN","WARN"); }
   string S_Confirm(){ return T("Confirm send?","Confirm send?"); }
   string S_Cancelled(){ return T("Cancelled","Cancelled"); }
   string S_Sent(){ return T("Sent","Sent"); }
   string S_News(){ return T("News","News"); }
   string S_Session(){ return T("Session","Session"); }
   string S_Connection(){ return T("Conn","Conn"); }
   string S_Status(){ return T("Status","Status"); }
   string S_DragMode(){ return T("Drag","Drag"); }
   string S_Mini(){ return T("Mini","Mini"); }
   string S_Drawer(){ return T("Drawer","Drawer"); }
   string S_Template(){ return T("Template","Template"); }
   string S_Help(){ return T("Enter=Send Esc=Cancel H=Hide D=Drag R=Risk P=Pos","Enter=Send Esc=Cancel H=Hide D=Drag R=Risk P=Pos"); }

   // Phase 6
   string S_Stats(){ return T("Stats","Stats"); }
   string S_Main(){ return T("Main","Main"); }
   string S_Trades(){ return T("Trades","Trades"); }
   string S_WinRate(){ return T("WR","WR"); }
   string S_PF(){ return T("PF","PF"); }
   string S_Exp(){ return T("Exp","Exp"); }
   string S_AvgR(){ return T("AvgR","AvgR"); }
   string S_MaxDD(){ return T("MaxDD","MaxDD"); }
   string S_Net(){ return T("Net","Net"); }
   string S_Dur(){ return T("Dur","Dur"); }
   string S_Profile(){ return T("Profile","Profile"); }
   string S_Export(){ return T("Export","Export"); }
   string S_Import(){ return T("Import","Import"); }
   string S_CSV(){ return T("CSV","CSV"); }
   string S_Next(){ return T("Next","Next"); }
};

#endif // MM_UI_STRINGS_MQH
