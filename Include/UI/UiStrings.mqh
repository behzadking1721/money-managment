//+------------------------------------------------------------------+
//|                                                   UiStrings.mqh  |
//|                         Bilingual UI strings EN/FA (Phase 4)     |
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

   string S_Spread(){ return T("Spread","اسپرد"); }
   string S_Risk(){ return T("Risk","ریسک"); }
   string S_Lot(){ return T("Lot","لات"); }
   string S_RR(){ return T("R:R","R:R"); }
   string S_Entry(){ return T("Entry","ورود"); }
   string S_SL(){ return T("SL","حد ضرر"); }
   string S_TP(){ return T("TP","حد سود"); }
   string S_Buy(){ return T("BUY","خرید"); }
   string S_Sell(){ return T("SELL","فروش"); }
   string S_Market(){ return T("Market","مارکت"); }
   string S_Pending(){ return T("Pending","پندینگ"); }
   string S_Ready(){ return T("Ready","آماده"); }
   string S_Blocked(){ return T("BLOCKED","مسدود"); }
   string S_Warn(){ return T("WARN","هشدار"); }
   string S_Confirm(){ return T("Confirm send?","تایید ارسال؟"); }
   string S_Cancelled(){ return T("Cancelled","لغو شد"); }
   string S_Sent(){ return T("Sent","ارسال شد"); }
   string S_News(){ return T("News","اخبار"); }
   string S_Session(){ return T("Session","سشن"); }
   string S_Connection(){ return T("Conn","اتصال"); }
   string S_Status(){ return T("Status","وضعیت"); }
   string S_DragMode(){ return T("Drag","درگ"); }
   string S_Mini(){ return T("Mini","مینی"); }
   string S_Drawer(){ return T("Drawer","کشو"); }
   string S_Template(){ return T("Template","قالب"); }
   string S_Help(){ return T("Enter=Send Esc=Cancel H=Hide D=Drag R=Risk","Enter=ارسال Esc=لغو H=مخفی D=درگ R=ریسک"); }
};

#endif // MM_UI_STRINGS_MQH
