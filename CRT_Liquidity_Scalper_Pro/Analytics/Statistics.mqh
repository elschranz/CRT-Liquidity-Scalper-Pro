#ifndef CRT_STATISTICS_MQH
#define CRT_STATISTICS_MQH
#include "TradeJournal.mqh"

struct SClosedPositionMetric
  {
   ulong id;
   double net,entry_volume,exit_volume;
   datetime opened,closed;
   bool has_entry,has_exit,mixed;
  };

struct SPerformanceGroup
  {
   string dimension,label;
   int trades,wins,r_samples;
   double net,gross_profit,gross_loss,sum_r;
  };

class CStatistics
  {
private:
   SStatistics m_stats;
   datetime m_last;
   bool m_dirty;
   SPerformanceGroup m_groups[];
   CSessionManager m_sessions;
   int Find(SClosedPositionMetric &positions[],const ulong id)
     {
      const int n=ArraySize(positions);
      for(int i=0;i<n;i++) if(positions[i].id==id) return i;
      ArrayResize(positions,n+1); ZeroMemory(positions[n]); positions[n].id=id;
      return n;
     }
   void AddGroup(const string dimension,const string label,const double net,
                 const bool known_r,const double realized_r)
     {
      int index=-1;
      for(int i=0;i<ArraySize(m_groups);i++)
         if(m_groups[i].dimension==dimension && m_groups[i].label==label) { index=i; break; }
      if(index<0)
        {
         index=ArraySize(m_groups); ArrayResize(m_groups,index+1);
         ZeroMemory(m_groups[index]); m_groups[index].dimension=dimension;
         m_groups[index].label=label;
        }
      m_groups[index].trades++; m_groups[index].net+=net;
      if(net>0) { m_groups[index].wins++; m_groups[index].gross_profit+=net; }
      else if(net<0) m_groups[index].gross_loss-=net;
      if(known_r) { m_groups[index].r_samples++; m_groups[index].sum_r+=realized_r; }
     }
   string ModeLabel(const ulong id)
     {
      if(CRTJournalGet(id,"mapped")<=0) return "UNKNOWN";
      const int mode=(int)CRTJournalGet(id,"mode");
      return mode==ENTRY_AGGRESSIVE?"AGGRESSIVE":
             (mode==ENTRY_CONFIRMED?"CONFIRMED":"UNKNOWN");
     }
   string RRLabel(const ulong id)
     {
      if(CRTJournalGet(id,"mapped")<=0) return "UNKNOWN";
      const double rr=CRTJournalGet(id,"rr");
      if(MathAbs(rr-3)<0.05) return "3";
      if(MathAbs(rr-5)<0.05) return "5";
      if(MathAbs(rr-7)<0.05) return "7";
      if(MathAbs(rr-9)<0.05) return "9";
      return "UNKNOWN";
     }
   string ATRLabel(const ulong id)
     {
      if(CRTJournalGet(id,"mapped")<=0) return "UNKNOWN";
      const double atr=CRTJournalGet(id,"atr");
      if(atr<=0) return "UNKNOWN";
      if(atr<2) return "<2";
      if(atr<5) return "2-5";
      if(atr<10) return "5-10";
      return ">=10";
     }
   void SortGroups()
     {
      const int n=ArraySize(m_groups);
      for(int i=1;i<n;i++)
        {
         SPerformanceGroup item=m_groups[i]; int j=i-1;
         const string key=item.dimension+"|"+item.label;
         while(j>=0 && StringCompare(m_groups[j].dimension+"|"+m_groups[j].label,key)>0)
           { m_groups[j+1]=m_groups[j]; j--; }
         m_groups[j+1]=item;
        }
     }
   void ExportGroups()
     {
      const int h=FileOpen(CRTKey("analytics")+"_breakdown.csv",
                          FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',');
      if(h==INVALID_HANDLE)
        {
         Print("CRT grouped statistics export failed: ",GetLastError()); return;
        }
      FileWrite(h,"asof_server_time","dataset","dimension","group","closed_positions",
                "wins","net_account_currency","winrate_percent","profit_factor",
                "mean_realized_r","r_samples");
      for(int i=0;i<ArraySize(m_groups);i++)
        {
         const double winrate=m_groups[i].trades>0?
                              100.0*m_groups[i].wins/m_groups[i].trades:0;
         FileWrite(h,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),"REAL",
                   m_groups[i].dimension,m_groups[i].label,m_groups[i].trades,
                   m_groups[i].wins,DoubleToString(m_groups[i].net,2),
                   DoubleToString(winrate,2),m_groups[i].gross_loss>0?
                   DoubleToString(m_groups[i].gross_profit/m_groups[i].gross_loss,4):"N/A",
                   m_groups[i].r_samples>0?
                   DoubleToString(m_groups[i].sum_r/m_groups[i].r_samples,4):"N/A",
                   m_groups[i].r_samples);
        }
      FileFlush(h); FileClose(h);
     }
public:
   CStatistics() { ZeroMemory(m_stats); m_last=0; m_dirty=true; }
   void Invalidate() { m_dirty=true; }
   bool Refresh()
     {
      const datetime now=TimeCurrent();
      if(!m_dirty && now-m_last<MathMax(1,InpStatisticsRefreshSeconds)) return true;
      const datetime from=InpStatisticsLookbackDays>0?
                          now-(datetime)((long)InpStatisticsLookbackDays*86400):0;
      if(!HistorySelect(from,now)) return false;
      const bool export_needed=m_dirty || m_last==0;
      SClosedPositionMetric positions[];
      const int count=HistoryDealsTotal();
      for(int i=0;i<count;i++)
        {
         const ulong deal=HistoryDealGetTicket(i);
         if(deal==0 || HistoryDealGetString(deal,DEAL_SYMBOL)!=CRTSymbol()) continue;
         const ulong id=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
         if(id==0) continue;
         const int j=Find(positions,id);
         const ENUM_DEAL_TYPE type=(ENUM_DEAL_TYPE)HistoryDealGetInteger(deal,DEAL_TYPE);
         const bool execution=type==DEAL_TYPE_BUY || type==DEAL_TYPE_SELL;
         if(execution && (ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)!=InpMagic)
            positions[j].mixed=true;
         const ENUM_DEAL_ENTRY side=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY);
         positions[j].net+=HistoryDealGetDouble(deal,DEAL_PROFIT)+
                           HistoryDealGetDouble(deal,DEAL_COMMISSION)+
                           HistoryDealGetDouble(deal,DEAL_SWAP)+
                           HistoryDealGetDouble(deal,DEAL_FEE);
         if(!execution) continue;
         if(side==DEAL_ENTRY_IN)
           {
            positions[j].has_entry=true; positions[j].entry_volume+=HistoryDealGetDouble(deal,DEAL_VOLUME);
            const datetime opened=(datetime)HistoryDealGetInteger(deal,DEAL_TIME);
            if(positions[j].opened==0 || opened<positions[j].opened) positions[j].opened=opened;
           }
         else if(side==DEAL_ENTRY_OUT || side==DEAL_ENTRY_OUT_BY)
           {
            positions[j].has_exit=true;
            positions[j].exit_volume+=HistoryDealGetDouble(deal,DEAL_VOLUME);
            positions[j].closed=(datetime)HistoryDealGetInteger(deal,DEAL_TIME);
           }
         else positions[j].mixed=true; // INOUT reversal cannot be attributed as one EA trade.
        }
      // Closure time order matters for drawdown; HistoryDealsTotal order alone is insufficient
      // when a position has multiple fills and partial exits.
      const int n=ArraySize(positions);
      for(int i=1;i<n;i++)
        {
         SClosedPositionMetric item=positions[i];
         int j=i-1;
         while(j>=0 && positions[j].closed>item.closed)
           { positions[j+1]=positions[j]; j--; }
         positions[j+1]=item;
        }
      ZeroMemory(m_stats); ArrayResize(m_groups,0);
      double cumulative=0,peak=0,sum_r=0;
      for(int i=0;i<n;i++)
        {
         if(positions[i].mixed || !positions[i].has_entry || !positions[i].has_exit ||
            CRTJournalPositionOpen(positions[i].id) ||
            MathAbs(positions[i].entry_volume-positions[i].exit_volume)>0.0000001) continue;
         const double pnl=positions[i].net;
         m_stats.trades++; m_stats.net+=pnl;
         if(pnl>0) { m_stats.wins++; m_stats.gross_profit+=pnl; }
         else if(pnl<0) { m_stats.losses++; m_stats.gross_loss-=pnl; }
         cumulative+=pnl; peak=MathMax(peak,cumulative);
         m_stats.max_dd=MathMax(m_stats.max_dd,peak-cumulative);
         const ulong id=positions[i].id;
         const double risk=CRTJournalOriginalRisk(id);
         const bool known_r=risk>0 && CRTJournalGet(id,"mixed")==0;
         const double realized_r=known_r?pnl/risk:0;
         if(known_r) { sum_r+=realized_r; m_stats.r_samples++; }
         AddGroup("SESSION",positions[i].opened>0?m_sessions.Name(positions[i].opened):"UNKNOWN",
                  pnl,known_r,realized_r);
         AddGroup("MODE",ModeLabel(id),pnl,known_r,realized_r);
         AddGroup("RR",RRLabel(id),pnl,known_r,realized_r);
         AddGroup("ATR",ATRLabel(id),pnl,known_r,realized_r);
        }
      m_stats.winrate=m_stats.trades>0?100.0*m_stats.wins/m_stats.trades:0;
      // A zero-loss sample has no finite PF; -1 represents N/A in the dashboard.
      m_stats.pf=m_stats.gross_loss>0?m_stats.gross_profit/m_stats.gross_loss:-1;
      m_stats.expectancy_r=m_stats.r_samples>0?sum_r/m_stats.r_samples:0;
      m_stats.realized_rr=m_stats.expectancy_r;
      SortGroups();
      if(export_needed) ExportGroups();
      m_last=now; m_dirty=false;
      return true;
     }
   SStatistics Snapshot() { return m_stats; }
   string Breakdown(const string dimension)
     {
      string wanted=dimension; StringToUpper(wanted);
      string text="";
      for(int i=0;i<ArraySize(m_groups);i++)
        {
         if(m_groups[i].dimension!=wanted) continue;
         if(text!="") text+="\n";
         text+=m_groups[i].label+" N="+IntegerToString(m_groups[i].trades)+
               " Net="+DoubleToString(m_groups[i].net,2)+
               " WR="+DoubleToString(100.0*m_groups[i].wins/m_groups[i].trades,1)+"% PF="+
               (m_groups[i].gross_loss>0?
                DoubleToString(m_groups[i].gross_profit/m_groups[i].gross_loss,2):"N/A")+
               " R="+(m_groups[i].r_samples>0?
                      DoubleToString(m_groups[i].sum_r/m_groups[i].r_samples,2):"N/A")+
               " (r="+IntegerToString(m_groups[i].r_samples)+")";
        }
      return text==""?"No closed real positions in "+wanted:text;
     }
  };
#endif
