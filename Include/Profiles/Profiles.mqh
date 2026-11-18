//+------------------------------------------------------------------+
//|                                                    Profiles.mqh  |
//|           Phase 6: ProfileService (Personal/Prop/Crypto)         |
//+------------------------------------------------------------------+
#ifndef MM_PROFILES_MQH
#define MM_PROFILES_MQH

#include "../Core/Contracts.mqh"
#include "../Core/SimpleJson.mqh"
#include "../Utils/Common.mqh"

#define MM_MAX_PROFILES 16

struct MM_ProfileRecord
{
   MM_Profile profile;
   double dailyLossLimitPct;
   double dailyProfitLimitPct;
   double weeklyLossLimitPct;
   double monthlyLossLimitPct;
   double maxDrawdownPct;
   int    maxTradesPerDay;
   int    maxConsecLoss;
   int    cooldownMinutes;
   double maxSpreadPoints;
   bool   newsEnabled;
   bool   newsBlackoutHigh;
   bool   newsOfflineBlock;
   int    newsBeforeMin;
   int    newsAfterMin;
   void Reset()
   {
      profile.Reset();
      dailyLossLimitPct=5.0; dailyProfitLimitPct=0; weeklyLossLimitPct=0; monthlyLossLimitPct=0; maxDrawdownPct=10.0;
      maxTradesPerDay=0; maxConsecLoss=3; cooldownMinutes=60; maxSpreadPoints=0;
      newsEnabled=true; newsBlackoutHigh=false; newsOfflineBlock=false; newsBeforeMin=15; newsAfterMin=15;
   }
};

class CProfileManager
{
private:
   MM_ProfileRecord m_profiles[MM_MAX_PROFILES];
   int              m_count;
   int              m_activeIdx;
   string           m_dir;
   long             m_login;

   int FindById(const string id)
   {
      for(int i=0;i<m_count;i++) if(m_profiles[i].profile.id==id) return i;
      return -1;
   }
   void EnsureDir(){ if(!FileIsExist(m_dir, FILE_COMMON)) FolderCreate(m_dir, FILE_COMMON); }

   void Defaults()
   {
      m_count=0;
      MM_ProfileRecord p; p.Reset();
      p.profile.id="personal"; p.profile.name="Personal"; p.profile.accountMode=ACCOUNT_PERSONAL;
      p.profile.riskBasis="Equity"; p.profile.defaultRiskPercent=1.0; p.profile.maxRiskPercent=2.0; p.profile.minRiskPercent=0.25; p.profile.autoRiskDefault=true;
      p.dailyLossLimitPct=5.0; p.maxDrawdownPct=10.0; m_profiles[m_count++]=p;
      p.Reset(); p.profile.id="prop"; p.profile.name="Prop"; p.profile.accountMode=ACCOUNT_PROP;
      p.profile.riskBasis="AllowedDD"; p.profile.defaultRiskPercent=0.5; p.profile.maxRiskPercent=1.0; p.profile.minRiskPercent=0.1; p.profile.autoRiskDefault=true;
      p.dailyLossLimitPct=4.0; p.maxDrawdownPct=8.0; p.maxTradesPerDay=5; p.newsBlackoutHigh=true; m_profiles[m_count++]=p;
      p.Reset(); p.profile.id="crypto"; p.profile.name="Crypto"; p.profile.accountMode=ACCOUNT_CRYPTO;
      p.profile.riskBasis="Equity"; p.profile.defaultRiskPercent=0.75; p.profile.maxRiskPercent=2.0; p.profile.minRiskPercent=0.1; p.profile.autoRiskDefault=true;
      p.dailyLossLimitPct=6.0; p.maxDrawdownPct=15.0; m_profiles[m_count++]=p;
      m_activeIdx=0;
   }

   void BuildInto(CJsonBuilder &jb, const string prefix, const MM_ProfileRecord &r)
   {
      string p=prefix;
      jb.Key(p+"version", r.profile.version);
      jb.Key(p+"id", r.profile.id);
      jb.Key(p+"name", r.profile.name);
      jb.Key(p+"accountMode", (int)r.profile.accountMode);
      jb.Key(p+"riskBasis", r.profile.riskBasis);
      jb.Key(p+"defaultRiskPercent", r.profile.defaultRiskPercent, 6);
      jb.Key(p+"maxRiskPercent", r.profile.maxRiskPercent, 6);
      jb.Key(p+"minRiskPercent", r.profile.minRiskPercent, 6);
      jb.KeyBool(p+"autoRiskDefault", r.profile.autoRiskDefault);
      jb.Key(p+"dailyLossLimitPct", r.dailyLossLimitPct, 6);
      jb.Key(p+"dailyProfitLimitPct", r.dailyProfitLimitPct, 6);
      jb.Key(p+"weeklyLossLimitPct", r.weeklyLossLimitPct, 6);
      jb.Key(p+"monthlyLossLimitPct", r.monthlyLossLimitPct, 6);
      jb.Key(p+"maxDrawdownPct", r.maxDrawdownPct, 6);
      jb.Key(p+"maxTradesPerDay", r.maxTradesPerDay);
      jb.Key(p+"maxConsecLoss", r.maxConsecLoss);
      jb.Key(p+"cooldownMinutes", r.cooldownMinutes);
      jb.Key(p+"maxSpreadPoints", r.maxSpreadPoints, 6);
      jb.KeyBool(p+"newsEnabled", r.newsEnabled);
      jb.KeyBool(p+"newsBlackoutHigh", r.newsBlackoutHigh);
      jb.KeyBool(p+"newsOfflineBlock", r.newsOfflineBlock);
      jb.Key(p+"newsBeforeMin", r.newsBeforeMin);
      jb.Key(p+"newsAfterMin", r.newsAfterMin);
   }

   bool ParseFrom(CJsonReader &jr, const string prefix, MM_ProfileRecord &out)
   {
      string p=prefix;
      string id=jr.GetString(p+"id","");
      if(id=="") return false;
      out.Reset();
      out.profile.version=(int)jr.GetLong(p+"version", MM_CONTRACT_VERSION);
      out.profile.id=id;
      out.profile.name=jr.GetString(p+"name", id);
      out.profile.accountMode=(ENUM_MM_ACCOUNT_MODE)(int)jr.GetLong(p+"accountMode", (int)ACCOUNT_PERSONAL);
      out.profile.riskBasis=jr.GetString(p+"riskBasis","Equity");
      out.profile.defaultRiskPercent=jr.GetDouble(p+"defaultRiskPercent", 1.0);
      out.profile.maxRiskPercent=jr.GetDouble(p+"maxRiskPercent", 2.0);
      out.profile.minRiskPercent=jr.GetDouble(p+"minRiskPercent", 0.25);
      out.profile.autoRiskDefault=jr.GetBool(p+"autoRiskDefault", true);
      out.dailyLossLimitPct=jr.GetDouble(p+"dailyLossLimitPct",5.0);
      out.dailyProfitLimitPct=jr.GetDouble(p+"dailyProfitLimitPct",0);
      out.weeklyLossLimitPct=jr.GetDouble(p+"weeklyLossLimitPct",0);
      out.monthlyLossLimitPct=jr.GetDouble(p+"monthlyLossLimitPct",0);
      out.maxDrawdownPct=jr.GetDouble(p+"maxDrawdownPct",10.0);
      out.maxTradesPerDay=(int)jr.GetLong(p+"maxTradesPerDay",0);
      out.maxConsecLoss=(int)jr.GetLong(p+"maxConsecLoss",3);
      out.cooldownMinutes=(int)jr.GetLong(p+"cooldownMinutes",60);
      out.maxSpreadPoints=jr.GetDouble(p+"maxSpreadPoints",0);
      out.newsEnabled=jr.GetBool(p+"newsEnabled",true);
      out.newsBlackoutHigh=jr.GetBool(p+"newsBlackoutHigh",false);
      out.newsOfflineBlock=jr.GetBool(p+"newsOfflineBlock",false);
      out.newsBeforeMin=(int)jr.GetLong(p+"newsBeforeMin",15);
      out.newsAfterMin=(int)jr.GetLong(p+"newsAfterMin",15);
      return true;
   }

   string StorePath(){ return m_dir+"\\profiles_"+(string)m_login+".json"; }

public:
   CProfileManager(){ m_count=0; m_activeIdx=0; m_login=0; m_dir="MoneyManager"; }

   void Init(long login=-1)
   {
      if(login<0) login=AccountInfoInteger(ACCOUNT_LOGIN);
      m_login=login; m_dir="MoneyManager"; EnsureDir();
      Defaults();
      LoadAll();
   }

   int Count(){ return m_count; }
   bool Get(int idx, MM_ProfileRecord &out){ if(idx<0||idx>=m_count) return false; out=m_profiles[idx]; return true; }
   int ActiveIndex(){ return m_activeIdx; }
   bool GetActive(MM_ProfileRecord &out){ return Get(m_activeIdx,out); }
   string ActiveId(){ if(m_activeIdx>=0 && m_activeIdx<m_count) return m_profiles[m_activeIdx].profile.id; return ""; }

   bool SetActiveById(const string id)
   {
      int idx=FindById(id); if(idx<0) return false; m_activeIdx=idx; SaveAll(); return true;
   }
   bool SetActiveByMode(ENUM_MM_ACCOUNT_MODE mode)
   {
      for(int i=0;i<m_count;i++) if(m_profiles[i].profile.accountMode==mode){ m_activeIdx=i; SaveAll(); return true; }
      return false;
   }
   bool NextProfile()
   {
      if(m_count<=0) return false;
      m_activeIdx=(m_activeIdx+1)%m_count; SaveAll(); return true;
   }

   bool Upsert(const MM_ProfileRecord &r)
   {
      int idx=FindById(r.profile.id);
      if(idx>=0){ m_profiles[idx]=r; return true; }
      if(m_count>=MM_MAX_PROFILES) return false;
      m_profiles[m_count++]=r; return true;
   }

   bool SaveAll()
   {
      EnsureDir();
      CJsonBuilder jb; jb.Reset(); jb.ObjStart();
      jb.Key("storeVersion", 1);
      jb.Key("activeId", ActiveId());
      jb.Key("count", m_count);
      for(int i=0;i<m_count;i++) BuildInto(jb, "p."+m_profiles[i].profile.id+".", m_profiles[i]);
      jb.ObjEnd();
      string path=StorePath();
      int h=FileOpen(path, FILE_WRITE|FILE_TXT|FILE_COMMON|FILE_ANSI);
      if(h==INVALID_HANDLE){ Print("Profiles: save failed ",path); return false; }
      FileWriteString(h,jb.Str()); FileClose(h);
      return true;
   }

   bool LoadAll()
   {
      string path=StorePath();
      if(!FileIsExist(path, FILE_COMMON)) return false;
      int h=FileOpen(path, FILE_READ|FILE_TXT|FILE_COMMON|FILE_ANSI|FILE_SHARE_READ);
      if(h==INVALID_HANDLE) return false;
      string content=""; while(!FileIsEnding(h)) content+=FileReadString(h);
      FileClose(h);
      CJsonReader jr; jr.Load(content);
      string active=jr.GetString("activeId","");
      // try known default ids plus any present
      string ids[3]={"personal","prop","crypto"};
      int found=0;
      for(int k=0;k<3;k++)
      {
         MM_ProfileRecord r;
         if(ParseFrom(jr, "p."+ids[k]+".", r))
         {
            int ex=FindById(r.profile.id);
            if(ex>=0) m_profiles[ex]=r; else if(m_count<MM_MAX_PROFILES) m_profiles[m_count++]=r;
            found++;
         }
      }
      if(active!=""){ int idx=FindById(active); if(idx>=0) m_activeIdx=idx; }
      return (found>0);
   }

   bool ExportProfile(const string profileId, const string filename)
   {
      int idx=FindById(profileId); if(idx<0) idx=m_activeIdx;
      if(idx<0 || idx>=m_count) return false;
      string path = filename;
      if(path=="") path = "MoneyManager\\profile_"+m_profiles[idx].profile.id+".json";
      EnsureDir();
      CJsonBuilder jb; jb.Reset(); jb.ObjStart();
      BuildInto(jb, "", m_profiles[idx]);
      jb.ObjEnd();
      int h=FileOpen(path, FILE_WRITE|FILE_TXT|FILE_COMMON|FILE_ANSI);
      if(h==INVALID_HANDLE){ Print("Profiles: export failed ",path); return false; }
      FileWriteString(h,jb.Str()); FileClose(h);
      Print("Profiles: exported ",path);
      return true;
   }

   bool ImportProfile(const string filename)
   {
      string path=filename;
      if(path=="") path="MoneyManager\\profile_import.json";
      if(!FileIsExist(path, FILE_COMMON)) { Print("Profiles: import not found ",path); return false; }
      int h=FileOpen(path, FILE_READ|FILE_TXT|FILE_COMMON|FILE_ANSI|FILE_SHARE_READ);
      if(h==INVALID_HANDLE) return false;
      string content=""; while(!FileIsEnding(h)) content+=FileReadString(h);
      FileClose(h);
      CJsonReader jr; jr.Load(content);
      MM_ProfileRecord r;
      if(!ParseFrom(jr, "", r)){ Print("Profiles: import parse failed"); return false; }
      bool ok=Upsert(r);
      if(ok){ SetActiveById(r.profile.id); SaveAll(); Print("Profiles: imported ",r.profile.id); }
      return ok;
   }
};

#endif // MM_PROFILES_MQH
