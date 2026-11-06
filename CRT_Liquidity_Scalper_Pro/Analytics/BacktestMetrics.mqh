#ifndef CRT_BACKTEST_METRICS_MQH
#define CRT_BACKTEST_METRICS_MQH
#include "../Core/Config.mqh"
#include "TradeJournal.mqh"


struct SVirtualLeg
  {
   bool offered,pending,open,done;
   SSignal signal;
   STradePlan plan;
   long created_msc;
   double fill,initial_distance,mfe,mae,cost_r;
  };

// This is a forward tick shadow ledger, not a second execution account.
// It never submits orders and never contributes to real-account statistics.
class CBacktestMetrics
  {
private:
   SVirtualLeg m_legs[2];
   int m_file;
   double m_sum_r[2];
   int m_closed[2],m_wins[2];
   string Mode(const int i) { return i==0?"AGGRESSIVE":"CONFIRMED"; }
   void Write(const int i,const string event,const string reason,const double result_r=0)
     {
      if(m_file==INVALID_HANDLE) return;
      FileWrite(m_file,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),"VIRTUAL",Mode(i),
                m_legs[i].signal.id,event,m_legs[i].plan.entry,m_legs[i].fill,
                m_legs[i].plan.sl,m_legs[i].plan.tp,m_legs[i].plan.rr,
                m_legs[i].signal.atr_pips,m_legs[i].mfe,m_legs[i].mae,
                result_r,m_closed[i],m_wins[i],m_sum_r[i],
                InpVirtualSlippagePips,reason);
      FileFlush(m_file);
     }
   double CostsInR(const int i)
     {
      const double volume=SymbolInfoDouble(CRTSymbol(),SYMBOL_VOLUME_MIN);
      double loss=0;
      if(volume<=0 || !OrderCalcProfit(m_legs[i].plan.direction==DIR_BUY?
                                     ORDER_TYPE_BUY:ORDER_TYPE_SELL,CRTSymbol(),volume,
                                     m_legs[i].fill,m_legs[i].plan.sl,loss) ||
         MathAbs(loss)<=0) return -1;
      return InpCommissionPerLot*volume/MathAbs(loss);
     }
   void Finish(const int i,const double exit_price,const string reason)
     {
      const int direction=(int)m_legs[i].plan.direction;
      const double risk=m_legs[i].initial_distance;
      const double result_r=risk>0?direction*(exit_price-m_legs[i].fill)/risk-m_legs[i].cost_r:0;
      m_closed[i]++; if(result_r>0) m_wins[i]++;
      m_sum_r[i]+=result_r;
      m_legs[i].open=false; m_legs[i].pending=false; m_legs[i].done=true;
      Write(i,"CLOSED",reason,result_r);
     }
   void Fill(const int i,const double price)
     {
      m_legs[i].fill=price;
      m_legs[i].initial_distance=MathAbs(price-m_legs[i].plan.sl);
      const bool buy=m_legs[i].plan.direction==DIR_BUY;
      if(m_legs[i].initial_distance<=0 ||
         (buy && (m_legs[i].plan.sl>=price || m_legs[i].plan.tp<=price)) ||
         (!buy && (m_legs[i].plan.sl<=price || m_legs[i].plan.tp>=price)))
        {
         m_legs[i].pending=false; m_legs[i].done=true;
         Write(i,"REJECTED","Simulated fill invalidates SL/TP"); return;
        }
      m_legs[i].cost_r=CostsInR(i);
      if(m_legs[i].cost_r<0)
        {
         m_legs[i].pending=false; m_legs[i].done=true;
         Write(i,"REJECTED","COST_DATA_UNAVAILABLE: commission conversion failed"); return;
        }
      m_legs[i].open=true; m_legs[i].pending=false;
      Write(i,"OPEN","Forward simulated fill; no order sent");
     }
public:
   CBacktestMetrics()
     {
      m_file=INVALID_HANDLE;
      for(int i=0;i<2;i++) { ZeroMemory(m_legs[i]); m_sum_r[i]=0; m_closed[i]=0; m_wins[i]=0; }
     }
   void Reset(const SSignal &signal)
     {
      // An already-open comparison trade must be observed to its exit. Do not erase it.
      for(int i=0;i<2;i++)
        {
         if(m_legs[i].open) continue;
         if(m_legs[i].pending) Write(i,"CANCELLED","Superseded by next signal");
         ZeroMemory(m_legs[i]); m_legs[i].signal=signal;
        }
      if(!InpVirtualComparisonEnabled || m_file!=INVALID_HANDLE) return;
      m_file=FileOpen(CRTKey("analytics")+"_virtual.csv",
                     FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',');
      if(m_file==INVALID_HANDLE) { Print("CRT virtual CSV unavailable: ",GetLastError()); return; }
      if(FileSize(m_file)==0)
         FileWrite(m_file,"server_time","dataset","mode","signal_id","event","planned_entry",
                   "simulated_fill","sl","tp","planned_rr","atr_pips","mfe_pips","mae_pips",
                   "result_r","closed_session","wins_session","sum_r_session",
                   "assumed_market_slippage_pips","reason");
      FileSeek(m_file,0,SEEK_END);
      Print("CRT comparison: session counters reset on EA restart; previous CSV rows retained.");
     }
   void OnPlan(const SSignal &signal,const STradePlan &plan)
     {
      if(!InpVirtualComparisonEnabled) return;
      const int i=plan.mode==ENTRY_AGGRESSIVE?0:1;
      if(m_legs[i].offered || m_legs[i].open) return;
      m_legs[i].offered=true; m_legs[i].signal=signal; m_legs[i].plan=plan;
      MqlTick tick; ZeroMemory(tick); SymbolInfoTick(CRTSymbol(),tick);
      m_legs[i].created_msc=tick.time_msc;
      if(plan.pending)
        {
         m_legs[i].pending=true;
         Write(i,"PENDING","Subsequent ticks only; fill queue and depth are not simulated");
        }
      else
        {
         const double assumed_slip=InpVirtualSlippagePips*CRTPip(CRTSymbol());
         Fill(i,plan.entry+(int)plan.direction*assumed_slip);
        }
     }
   void Tick(const MqlTick &tick)
     {
      if(!InpVirtualComparisonEnabled || tick.bid<=0 || tick.ask<=0) return;
      for(int i=0;i<2;i++)
        {
         if(m_legs[i].done || !m_legs[i].offered) continue;
         const bool buy=m_legs[i].plan.direction==DIR_BUY;
         if(m_legs[i].pending)
           {
            if(tick.time>=m_legs[i].plan.expiration || tick.time>=m_legs[i].signal.expires_at)
              {
               m_legs[i].pending=false; m_legs[i].done=true;
               Write(i,"EXPIRED","Pending lifetime"); continue;
              }
            if((buy && tick.bid>=m_legs[i].plan.tp) ||
               (!buy && tick.ask<=m_legs[i].plan.tp))
              {
               m_legs[i].pending=false; m_legs[i].done=true;
               Write(i,"CANCELLED","Target reached before entry"); continue;
              }
            if(tick.time_msc<=m_legs[i].created_msc) continue;
            const bool triggered=(buy && tick.ask<=m_legs[i].plan.entry) ||
                                 (!buy && tick.bid>=m_legs[i].plan.entry);
            const bool broken=(buy && tick.bid<m_legs[i].signal.extreme) ||
                              (!buy && tick.ask>m_legs[i].signal.extreme);
            // A gap can cross limit and stop together. Model the possible fill and loss,
            // never delete the losing trade by assuming cancellation won that race.
            if(triggered) Fill(i,m_legs[i].plan.entry);
            else if(broken)
              {
               m_legs[i].pending=false; m_legs[i].done=true;
               Write(i,"CANCELLED","Manipulation extreme broken before executable touch"); continue;
              }
           }
         if(!m_legs[i].open) continue;
         const double exit_price=buy?tick.bid:tick.ask;
         const double excursion=(int)m_legs[i].plan.direction*(exit_price-m_legs[i].fill)/
                                 CRTPip(CRTSymbol());
         m_legs[i].mfe=MathMax(m_legs[i].mfe,excursion);
         m_legs[i].mae=MathMax(m_legs[i].mae,-excursion);
         const bool stop=buy?exit_price<=m_legs[i].plan.sl:exit_price>=m_legs[i].plan.sl;
         const bool target=buy?exit_price>=m_legs[i].plan.tp:exit_price<=m_legs[i].plan.tp;
         // Stops use observed worse gap price; target fills receive no positive gap bonus.
         if(stop) Finish(i,exit_price,"STOP observed tick (gaps can exceed 1R)");
         else if(target) Finish(i,m_legs[i].plan.tp,"TARGET");
        }
     }
   void Reject(const SSignal &signal,const EEntryMode mode,const string reason)
     {
      if(!InpVirtualComparisonEnabled) return;
      const int i=mode==ENTRY_AGGRESSIVE?0:1;
      if(m_legs[i].offered || m_legs[i].open || m_legs[i].pending) return;
      m_legs[i].signal=signal; m_legs[i].plan.signal_id=signal.id;
      m_legs[i].plan.direction=signal.direction; m_legs[i].plan.mode=mode;
      m_legs[i].offered=true; m_legs[i].done=true;
      Write(i,"REJECTED",reason);
     }
   bool Busy()
     {
      for(int i=0;i<2;i++) if(m_legs[i].pending || m_legs[i].open) return true;
      return false;
     }
   int Closed(const EEntryMode mode) { return m_closed[mode==ENTRY_AGGRESSIVE?0:1]; }
   double NetR(const EEntryMode mode) { return m_sum_r[mode==ENTRY_AGGRESSIVE?0:1]; }
   double Winrate(const EEntryMode mode)
     {
      const int i=mode==ENTRY_AGGRESSIVE?0:1;
      return m_closed[i]>0?100.0*m_wins[i]/m_closed[i]:0;
     }
   void Cancel(const string reason)
     {
      for(int i=0;i<2;i++)
         if(m_legs[i].pending)
           {
            m_legs[i].pending=false; m_legs[i].done=true;
            Write(i,"CANCELLED",reason);
           }
     }
   double Fitness()
     {
      if(!MQLInfoInteger(MQL_TESTER)) return 0;
      const double profit=TesterStatistics(STAT_PROFIT);
      const double drawdown=TesterStatistics(STAT_EQUITY_DD);
      return profit/(1.0+MathMax(0.0,drawdown));
     }
   void Close()
     {
      Cancel("EA stopped before pending fill");
      for(int i=0;i<2;i++)
         if(m_legs[i].open) Write(i,"CENSORED","EA stopped before virtual exit; excluded from closed results");
      if(m_file!=INVALID_HANDLE) { FileFlush(m_file); FileClose(m_file); m_file=INVALID_HANDLE; }
     }
  };
#endif
