//+------------------------------------------------------------------+
//|                                                    UiStrings.mqh |
//|                 Bilingual UI strings EN/FA (Phase 4/6/7)         |
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

   // Core labels
   string S_Spread(){ return T("Spread","اسپرد"); }
   string S_Risk(){ return T("Risk","ریسک"); }
   string S_Lot(){ return T("Lot","لات"); }
   string S_RR(){ return T("R:R","نسبت R"); }
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
   string S_Confirm(){ return T("Confirm send?","ارسال تایید شود؟"); }
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
   string S_Help(){ return T("H=Hide D=Drag B/S Enter=Send Esc=Cancel R=Risk P=Pos K=Stats","H=پنهان D=درگ B/S Enter=ارسال Esc=لغو R=ریسک P=پوزیشن K=آمار"); }

   // Phase 6/7
   string S_Stats(){ return T("Stats","آمار"); }
   string S_Main(){ return T("Main","اصلی"); }
   string S_Trades(){ return T("Trades","معاملات"); }
   string S_WinRate(){ return T("WR","وین‌ریت"); }
   string S_PF(){ return T("PF","PF"); }
   string S_Exp(){ return T("Exp","انتظار"); }
   string S_AvgR(){ return T("AvgR","میانگین R"); }
   string S_MaxDD(){ return T("MaxDD","حداکثر افت"); }
   string S_Net(){ return T("Net","خالص"); }
   string S_Dur(){ return T("Dur","مدت"); }
   string S_Profile(){ return T("Profile","پروفایل"); }
   string S_Export(){ return T("Export","خروجی"); }
   string S_Import(){ return T("Import","ورودی"); }
   string S_CSV(){ return T("CSV","CSV"); }
   string S_Next(){ return T("Next","بعدی"); }
   string S_Mode(){ return T("Mode","حالت"); }
   string S_Idle(){ return T("Idle","آماده"); }
   string S_Send(){ return T("Send","ارسال"); }
   string S_Clear(){ return T("Clr","پاک"); }
   string S_Save(){ return T("Save","ذخیره"); }
   string S_CloseAll(){ return T("All","همه"); }
   string S_Pos(){ return T("Pos","پوزیشن"); }
   string S_Trail(){ return T("Trl","تریل"); }
   string S_BE(){ return T("BE","سر‌به‌سر"); }
   string S_Partial(){ return T("50%","۵۰٪"); }

   // Tooltips
   string Tip_Buy(){ return T("Start BUY drag plan (B)","شروع پلان خرید با درگ (B)"); }
   string Tip_Sell(){ return T("Start SELL drag plan (S)","شروع پلان فروش با درگ (S)"); }
   string Tip_Drag(){ return T("Toggle drag mode (D)","تغییر حالت درگ (D)"); }
   string Tip_Send(){ return T("Preflight and send plan (Enter)","بررسی و ارسال پلان (Enter)"); }
   string Tip_Clear(){ return T("Clear drag plan (Esc)","پاک کردن پلان (Esc)"); }
   string Tip_Lang(){ return T("Toggle language","تغییر زبان"); }
   string Tip_Mini(){ return T("Toggle mini/drawer","تغییر نمای مینی/کشو"); }
   string Tip_RiskUp(){ return T("Increase risk value","افزایش مقدار ریسک"); }
   string Tip_RiskDn(){ return T("Decrease risk value","کاهش مقدار ریسک"); }
   string Tip_Save(){ return T("Save/apply template (T)","ذخیره/اعمال قالب (T)"); }
   string Tip_Pos(){ return T("Select open position (P)","انتخاب پوزیشن باز (P)"); }
   string Tip_BE(){ return T("Move SL to breakeven","انتقال حد ضرر به سر‌به‌سر"); }
   string Tip_Trail(){ return T("Apply trailing step","اعمال گام تریل"); }
   string Tip_Partial(){ return T("Close 50% of selected position","بستن ۵۰٪ پوزیشن انتخابی"); }
   string Tip_CloseAll(){ return T("Close all positions on symbol (confirm)","بستن همه پوزیشن‌های نماد (با تایید)"); }
   string Tip_TabMain(){ return T("Main tab","تب اصلی"); }
   string Tip_TabStats(){ return T("Stats tab (K)","تب آمار (K)"); }
   string Tip_CSV(){ return T("Export trade history CSV","خروجی CSV تاریخچه معاملات"); }
   string Tip_ProfileNext(){ return T("Switch to next profile","تغییر به پروفایل بعدی"); }
   string Tip_ProfileExport(){ return T("Export active profile","خروجی پروفایل فعال"); }
   string Tip_ProfileImport(){ return T("Import profile from MoneyManager\\profile_import.json","ورود پروفایل از MoneyManager\\profile_import.json"); }
};

#endif // MM_UI_STRINGS_MQH
