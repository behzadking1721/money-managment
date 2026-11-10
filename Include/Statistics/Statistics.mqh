#ifndef STATISTICS_MQH
#define STATISTICS_MQH
#include "../Utils/Common.mqh"
class CStatistics
{
private:
   string m_csvFile; int m_handle;
   int m_totalTrades;int m_wins;int m_losses;double m_grossProfit;double m_grossLoss;
   double m_sumDuration;datetime m_lastOpen;double m_lastProfit;string m_lastSymbol;
   double m_peakBalance;double m_maxDD;double m_balanceStart;
   int m_consecWin;int m_consecLoss;int m_maxConsecWin;int m_maxConsecLoss;
public:
   void Init(string file="trades.csv"){m_csvFile=file;m_totalTrades=0;m_wins=0;m_losses=0;m_grossProfit=0;m_grossLoss=0;m_sumDuration=0;m_lastProfit=0;m_lastSymbol="";m_peakBalance=AccountInfoDouble(ACCOUNT_BALANCE);m_maxDD=0;m_balanceStart=AccountInfoDouble(ACCOUNT_BALANCE);m_consecWin=0;m_consecLoss=0;m_maxConsecWin=0;m_maxConsecLoss=0;OpenCSV();}
   void OpenCSV(){m_handle=FileOpen(m_csvFile,FILE_WRITE|FILE_CSV|FILE_COMMON,',');if(m_handle!=INVALID_HANDLE){FileWrite(m_handle,"Time","Symbol","Type","Lot","OpenPrice","ClosePrice","SL","TP","Profit","DurationMin","Magic");}}
   void CloseCSV(){if(m_handle!=INVALID_HANDLE)FileClose(m_handle);m_handle=INVALID_HANDLE;}
   void LogTrade(string sym,ENUM_POSITION_TYPE type,double lot,double openP,double closeP,double sl,double tp,double profit,datetime openTime)
   {
      m_totalTrades++;if(profit>0){m_wins++;m_grossProfit+=profit;m_consecWin++;m_consecLoss=0;if(m_consecWin>m_maxConsecWin)m_maxConsecWin=m_consecWin;}
      else if(profit<0){m_losses++;m_grossLoss+=-profit;m_consecLoss++;m_consecWin=0;if(m_consecLoss>m_maxConsecLoss)m_maxConsecLoss=m_consecLoss;}
      double dur=(TimeCurrent()-openTime)/60.0;m_sumDuration+=dur;m_lastProfit=profit;m_lastSymbol=sym;
      if(m_handle!=INVALID_HANDLE)FileWrite(m_handle,TimeToString(TimeCurrent()),sym,(type==POSITION_TYPE_BUY)?"BUY":"SELL",DoubleToString(lot,2),DoubleToString(openP,_Digits),DoubleToString(closeP,_Digits),DoubleToString(sl,_Digits),DoubleToString(tp,_Digits),DoubleToString(profit,2),DoubleToString(dur,1),"");
      // drawdown
      double bal=AccountInfoDouble(ACCOUNT_BALANCE);if(bal>m_peakBalance)m_peakBalance=bal;double dd=(m_peakBalance-bal)/m_peakBalance*100.0;if(dd>m_maxDD)m_maxDD=dd;
   }
   // metrics
   double WinRate(){if(m_totalTrades==0)return 0;return (double)m_wins/m_totalTrades*100.0;}
   double ProfitFactor(){if(m_grossLoss==0)return m_grossProfit>0?999:0;return m_grossProfit/m_grossLoss;}
   double AvgTradeDuration(){if(m_totalTrades==0)return 0;return m_sumDuration/m_totalTrades;}
   double RecoveryFactor(){if(m_maxDD==0)return 0;double net=m_grossProfit-m_grossLoss;return net/m_maxDD;}
   double Sharpe(){ // simplified: mean/std of trade profits
      return 0; // placeholder
   }
   int TotalTrades(){return m_totalTrades;}
   int Wins(){return m_wins;}
   int Losses(){return m_losses;}
   double GrossProfit(){return m_grossProfit;}
   double GrossLoss(){return m_grossLoss;}
   double NetProfit(){return m_grossProfit-m_grossLoss;}
   double MaxDD(){return m_maxDD;}
   double LastProfit(){return m_lastProfit;}
   string LastSymbol(){return m_lastSymbol;}
   int MaxConsecWin(){return m_maxConsecWin;}
   int MaxConsecLoss(){return m_maxConsecLoss;}
   // Daily snapshot
   void DailySnapshot(string file)
   {
      int h=FileOpen(file,FILE_WRITE|FILE_TXT|FILE_COMMON);if(h==INVALID_HANDLE)return;
      FileWrite(h,"Date: "+TimeToString(TimeCurrent(),TIME_DATE));
      FileWrite(h,"Balance: "+DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2));
      FileWrite(h,"Equity: "+DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2));
      FileWrite(h,"Trades: "+(string)m_totalTrades);
      FileWrite(h,"WinRate: "+DoubleToString(WinRate(),2)+"%");
      FileWrite(h,"ProfitFactor: "+DoubleToString(ProfitFactor(),2));
      FileWrite(h,"MaxDD: "+DoubleToString(m_maxDD,2)+"%");
      FileClose(h);
   }
   // Export CSV (copy) already written live
   void ExportCSV(string /*dest*/){}
};
#endif
