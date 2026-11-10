#ifndef PROFILES_MQH
#define PROFILES_MQH
#include "../Utils/Common.mqh"
class CProfileManager
{
private:
   SProfile m_current; SProfile m_presets[3]; string m_savedNames[]; int m_savedCount;
public:
   void Init()
   {
      // Conservative
      m_presets[0].name="Conservative";m_presets[0].lotMethod=LOT_RISK_PERCENT;m_presets[0].lotValue=0.5;
      m_presets[0].slMethod=SL_ATR;m_presets[0].slValue=2.0;m_presets[0].tpMethod=TP_RR;m_presets[0].tpValue=2.0;
      m_presets[0].maxRiskPercent=1;m_presets[0].minRiskPercent=0.25;m_presets[0].magic=MM_MAGIC_DEFAULT;
      m_presets[0].useCommission=true;m_presets[0].useSlippage=true;m_presets[0].maxSlippage=3;m_presets[0].retries=3;
      // Moderate
      m_presets[1].name="Moderate";m_presets[1].lotMethod=LOT_RISK_PERCENT;m_presets[1].lotValue=1.0;
      m_presets[1].slMethod=SL_ATR;m_presets[1].slValue=1.5;m_presets[1].tpMethod=TP_RR;m_presets[1].tpValue=2.0;
      m_presets[1].maxRiskPercent=2;m_presets[1].minRiskPercent=0.5;m_presets[1].magic=MM_MAGIC_DEFAULT;
      m_presets[1].useCommission=true;m_presets[1].useSlippage=true;m_presets[1].maxSlippage=3;m_presets[1].retries=3;
      // Aggressive
      m_presets[2].name="Aggressive";m_presets[2].lotMethod=LOT_RISK_PERCENT;m_presets[2].lotValue=2.0;
      m_presets[2].slMethod=SL_ATR;m_presets[2].slValue=1.0;m_presets[2].tpMethod=TP_RR;m_presets[2].tpValue=1.5;
      m_presets[2].maxRiskPercent=5;m_presets[2].minRiskPercent=1;m_presets[2].magic=MM_MAGIC_DEFAULT;
      m_presets[2].useCommission=true;m_presets[2].useSlippage=true;m_presets[2].maxSlippage=5;m_presets[2].retries=5;
      m_current=m_presets[1];m_savedCount=0;
   }
   SProfile GetPreset(int i){if(i<0||i>2)i=1;return m_presets[i];}
   void ApplyPreset(int i){if(i>=0&&i<=2)m_current=m_presets[i];}
   SProfile Current(){return m_current;}
   void SetCurrent(SProfile &p){m_current=p;}
   // Save custom profile by name
   void SaveProfile(string name,SProfile &p){p.name=name;ArrayResize(m_savedNames,m_savedCount+1);m_savedNames[m_savedCount++]=name;}
   // Export .set
   bool ExportSet(string filename,SProfile &p)
   {
      int h=FileOpen(filename,FILE_WRITE|FILE_TXT|FILE_COMMON);if(h==INVALID_HANDLE)return false;
      FileWrite(h,"; Money Manager profile");FileWrite(h,"LotMethod="+(string)p.lotMethod);FileWrite(h,"LotValue="+DoubleToString(p.lotValue,4));
      FileWrite(h,"SLMethod="+(string)p.slMethod);FileWrite(h,"SLValue="+DoubleToString(p.slValue,4));
      FileWrite(h,"TPMethod="+(string)p.tpMethod);FileWrite(h,"TPValue="+DoubleToString(p.tpValue,4));
      FileWrite(h,"Magic="+(string)p.magic);FileWrite(h,"MaxRisk="+DoubleToString(p.maxRiskPercent,4));
      FileClose(h);return true;
   }
   bool ImportSet(string filename,SProfile &p)
   {
      int h=FileOpen(filename,FILE_READ|FILE_TXT|FILE_COMMON);if(h==INVALID_HANDLE)return false;
      while(!FileIsEnding(h)){string line=FileReadString(h);int eq=StringFind(line,"=");if(eq<0)continue;string key=StringSubstr(line,0,eq);string val=StringSubstr(line,eq+1);
         if(key=="LotMethod")p.lotMethod=(ENUM_LOT_METHOD)StringToInteger(val);
         else if(key=="LotValue")p.lotValue=StringToDouble(val);
         else if(key=="SLMethod")p.slMethod=(ENUM_SL_METHOD)StringToInteger(val);
         else if(key=="SLValue")p.slValue=StringToDouble(val);
         else if(key=="TPMethod")p.tpMethod=(ENUM_TP_METHOD)StringToInteger(val);
         else if(key=="TPValue")p.tpValue=StringToDouble(val);
         else if(key=="Magic")p.magic=(int)StringToInteger(val);
         else if(key=="MaxRisk")p.maxRiskPercent=StringToDouble(val);
      }
      FileClose(h);m_current=p;return true;
   }
};
#endif
