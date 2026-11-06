#ifndef CRT_STATISTICS_MQH
#define CRT_STATISTICS_MQH
#include "../Core/Config.mqh"
#include "TradeJournal.mqh"

struct SClosedPositionMetric
  {
   ulong id;
   double net,entry_volume,exit_volume;
   datetime closed;
   bool has_entry,has_exit,mixed;
  };

class CStatistics
  {
private:
   SStatistics m_stats;
   datetime m_last;
   bool m_dirty;
   int Find(SClosedPositionMetric &positions[],const ulong id)
     {
      const int n=ArraySize(positions);
      for(int i=0;i<n;i++) if(positions[i].id==id) return i;
      ArrayResize(positions,n+1); ZeroMemory(positions[n]); positions[n].id=id;
      return n;
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
           { positions[j].has_entry=true; positions[j].entry_volume+=HistoryDealGetDouble(deal,DEAL_VOLUME); }
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
      ZeroMemory(m_stats);
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
         const double risk=CRTJournalOriginalRisk(positions[i].id);
         if(risk>0 && CRTJournalGet(positions[i].id,"mixed")==0)
           { sum_r+=pnl/risk; m_stats.r_samples++; }
        }
      m_stats.winrate=m_stats.trades>0?100.0*m_stats.wins/m_stats.trades:0;
      // A zero-loss sample has no finite PF; -1 represents N/A in the dashboard.
      m_stats.pf=m_stats.gross_loss>0?m_stats.gross_profit/m_stats.gross_loss:-1;
      m_stats.expectancy_r=m_stats.r_samples>0?sum_r/m_stats.r_samples:0;
      m_stats.realized_rr=m_stats.expectancy_r;
      m_last=now; m_dirty=false;
      return true;
     }
   SStatistics Snapshot() { return m_stats; }
  };
#endif
