//+------------------------------------------------------------------+
//|                                                SimpleJson.mqh    |
//|       Minimal JSON builder/reader for State (Phase 1, known keys)|
//+------------------------------------------------------------------+
#ifndef MM_SIMPLE_JSON_MQH
#define MM_SIMPLE_JSON_MQH

// NOTE: Minimal serializer/parser for flat/tagged keys used by StateStore.
// Limitations documented in Docs/simplejson-limitations.md. Not a general JSON lib.

class CJsonBuilder
{
private:
   string m_s;
   bool   m_needComma;
   void Comma(){ if(m_needComma) m_s+=","; m_needComma=true; }
   string Esc(const string v)
   {
      string r=""; int len=StringLen(v);
      for(int i=0;i<len;i++)
      {
         ushort ch=StringGetCharacter(v,i);
         if(ch=='\\') r+="\\\\";
         else if(ch=='\"') r+="\\\"";
         else if(ch=='\n') r+="\\n";
         else if(ch=='\r') r+="\\r";
         else if(ch=='\t') r+="\\t";
         else if(ch<32) { /* drop other control chars */ }
         else r+=ShortToString(ch);
      }
      return r;
   }
public:
   void Reset(){ m_s=""; m_needComma=false; }
   void ObjStart(){ m_s+="{"; m_needComma=false; }
   void ObjEnd(){ m_s+="}"; m_needComma=true; }
   void ArrStart(const string key=""){ if(key!=""){Comma(); m_s+="\""+Esc(key)+"\":[";} else {Comma(); m_s+="[";} m_needComma=false; }
   void ArrEnd(){ m_s+="]"; m_needComma=true; }
   void KeyObjStart(const string key){ Comma(); m_s+="\""+Esc(key)+"\":{"; m_needComma=false; }
   void Key(const string key,const string val){ Comma(); m_s+="\""+Esc(key)+"\":\""+Esc(val)+"\""; }
   void Key(const string key,long val){ Comma(); m_s+="\""+Esc(key)+"\":"+ (string)val; }
   void Key(const string key,int val){ Comma(); m_s+="\""+Esc(key)+"\":"+ (string)val; }
   void Key(const string key,double val,int digits=8){ Comma(); m_s+="\""+Esc(key)+"\":"+DoubleToString(val,digits); }
   void KeyBool(const string key,bool val){ Comma(); m_s+="\""+Esc(key)+"\":"+(val?"true":"false"); }
   void Raw(const string key,const string rawJson){ Comma(); m_s+="\""+Esc(key)+"\":"+rawJson; }
   string Str(){ return m_s; }
};

// Minimal parser helpers for known flat/tagged key patterns inside a JSON string.
// For nested structures we use tagged keys (e.g. "sym.EURUSD.mode").
class CJsonReader
{
private:
   string m_s;
   int FindKey(const string key)
   {
      string pat="\""+key+"\"";
      return StringFind(m_s,pat);
   }
   string Unesc(const string v)
   {
      string r=""; int len=StringLen(v);
      for(int i=0;i<len;i++)
      {
         ushort ch=StringGetCharacter(v,i);
         if(ch=='\\' && i+1<len)
         {
            ushort n=StringGetCharacter(v,i+1);
            if(n=='\\'){ r+="\\"; i++; }
            else if(n=='\"'){ r+="\""; i++; }
            else if(n=='n'){ r+="\n"; i++; }
            else if(n=='r'){ r+="\r"; i++; }
            else if(n=='t'){ r+="\t"; i++; }
            else if(n=='/'){ r+="/"; i++; }
            else { r+=ShortToString(ch); }
         }
         else r+=ShortToString(ch);
      }
      return r;
   }
public:
   void Load(const string src){ m_s=src; }
   bool Has(const string key){ return FindKey(key)>=0; }
   string GetString(const string key,const string def="")
   {
      int p=FindKey(key); if(p<0) return def;
      int c=StringFind(m_s,":",p); if(c<0) return def;
      int q1=-1;
      for(int i=c+1;i<StringLen(m_s);i++){ ushort ch=StringGetCharacter(m_s,i); if(ch=='\"'){q1=i;break;} if(ch!=' '&&ch!='\n'&&ch!='\r'&&ch!='\t') return def; }
      if(q1<0) return def;
      // find closing quote respecting escapes
      string raw=""; bool esc=false;
      for(int i=q1+1;i<StringLen(m_s);i++)
      {
         ushort ch=StringGetCharacter(m_s,i);
         if(esc){ raw+=ShortToString('\\'); raw+=ShortToString(ch); esc=false; continue; }
         if(ch=='\\'){ esc=true; continue; }
         if(ch=='\"'){ return Unesc(raw); }
         raw+=ShortToString(ch);
      }
      return def;
   }
   long GetLong(const string key,long def=0)
   {
      int p=FindKey(key); if(p<0) return def;
      int c=StringFind(m_s,":",p); if(c<0) return def;
      int e=c+1; while(e<StringLen(m_s)){ ushort ch=StringGetCharacter(m_s,e); if(ch==' '||ch=='\n'||ch=='\r'||ch=='\t') e++; else break; }
      int end=e; while(end<StringLen(m_s)){ ushort ch=StringGetCharacter(m_s,end); if((ch>='0'&&ch<='9')||ch=='-' ) end++; else break; }
      if(end<=e) return def;
      return (long)StringToInteger(StringSubstr(m_s,e,end-e));
   }
   double GetDouble(const string key,double def=0)
   {
      int p=FindKey(key); if(p<0) return def;
      int c=StringFind(m_s,":",p); if(c<0) return def;
      int e=c+1; while(e<StringLen(m_s)){ ushort ch=StringGetCharacter(m_s,e); if(ch==' '||ch=='\n'||ch=='\r'||ch=='\t'||ch=='\"') e++; else break; }
      int end=e; while(end<StringLen(m_s)){ ushort ch=StringGetCharacter(m_s,end); if((ch>='0'&&ch<='9')||ch=='-'||ch=='.'||ch=='e'||ch=='E'||ch=='+') end++; else break; }
      if(end<=e) return def;
      return StringToDouble(StringSubstr(m_s,e,end-e));
   }
   bool GetBool(const string key,bool def=false)
   {
      int p=FindKey(key); if(p<0) return def;
      int c=StringFind(m_s,":",p); if(c<0) return def;
      int e=c+1; while(e<StringLen(m_s)){ ushort ch=StringGetCharacter(m_s,e); if(ch==' '||ch=='\n'||ch=='\r'||ch=='\t') e++; else break; }
      string tail=StringSubstr(m_s,e,5);
      if(StringFind(tail,"true")==0) return true;
      if(StringFind(tail,"false")==0) return false;
      return def;
   }
};

#endif // MM_SIMPLE_JSON_MQH
