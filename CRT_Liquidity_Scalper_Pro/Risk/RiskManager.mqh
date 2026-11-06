#ifndef CRT_RISK_MANAGER_MQH
#define CRT_RISK_MANAGER_MQH
#include "../Core/Config.mqh"
#include "../Core/Types.mqh"
#include "../Core/Utilities.mqh"
#include "DailyLimits.mqh"
#include "DrawdownManager.mqh"
struct SCRTRiskLedger
{
   ulong id;
   datetime entry_time,exit_time;
   double net,in_volume,out_volume;
};
class CRiskManager
{
private:
   SRiskSnapshot m_snapshot;
   CPropFirmManager m_prop;
   CDailyLimits m_period;
   CDrawdownManager m_dd;
   SCRTRiskLedger m_ledger[];
   datetime m_day,m_week,m_history_checked,m_first_deal;
   double m_reference,m_high,m_day_reference,m_week_reference,m_cash_origin;
   double m_day_cash,m_week_cash,m_all_cash,m_day_delta,m_week_delta;
   int m_locks,m_own_positions,m_own_pending,m_seen_deals;
   bool m_dirty,m_loaded,m_ready,m_persistence_error;
   string Key(const string suffix) { return CRTKey("risk."+suffix); }
   bool Put(const string suffix,const double value)
   { return GlobalVariableSet(Key(suffix),value)!=0; }
   bool Get(const string suffix,double &value)
   {
      if(!GlobalVariableCheck(Key(suffix))) return false;
      ResetLastError();
      value=GlobalVariableGet(Key(suffix));
      return GetLastError()==0 && MathIsValidNumber(value);
   }
   bool CashFlow(const ENUM_DEAL_TYPE type)
   { return type==DEAL_TYPE_BALANCE || type==DEAL_TYPE_CREDIT ||
            type==DEAL_TYPE_BONUS || type==DEAL_TYPE_CORRECTION; }
   int Find(const ulong id)
   {
      for(int i=0;i<ArraySize(m_ledger);i++) if(m_ledger[i].id==id) return i;
      return -1;
   }
   bool PositionAlive(const ulong identifier)
   {
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         if(PositionGetTicket(i)==0) continue;
         if((ulong)PositionGetInteger(POSITION_IDENTIFIER)==identifier) return true;
      }
      return false;
   }
   bool Load()
   {
      double version=0;
      if(!Get("version",version) || version!=3) return false;
      double day=0,week=0,locks=0,seen=0,first=0;
      if(!Get("reference",m_reference) || !Get("high",m_high) ||
         !Get("dayref",m_day_reference) || !Get("weekref",m_week_reference) ||
         !Get("cashorigin",m_cash_origin) || !Get("day",day) ||
         !Get("week",week) || !Get("locks",locks) ||
         !Get("seen",seen) || !Get("first",first)) return false;
      m_day=(datetime)day; m_week=(datetime)week; m_locks=(int)locks;
      m_seen_deals=(int)seen; m_first_deal=(datetime)first;
      return m_reference>0 && m_high>=m_reference &&
             m_day_reference>0 && m_week_reference>0 &&
             m_day>0 && m_week>0 && m_day<=CRTNow() &&
             m_week<=m_day && m_locks>=0 && m_locks<=7;
   }
   bool History(const datetime now,const bool full)
   {
      const datetime start=full ? (datetime)0 : (m_day<m_week ? m_day:m_week);
      if(!HistorySelect(start,now)) return false;
      const int count=HistoryDealsTotal();
      const int previous_count=m_seen_deals;
      const datetime previous_first=m_first_deal;
      m_day_delta=0; m_week_delta=0; m_day_cash=0; m_week_cash=0;
      if(full)
      {
         ArrayResize(m_ledger,0);
         m_all_cash=0;
         datetime earliest=0;
         // Ownership comes from the entry magic; manual exits are still counted.
         for(int i=0;i<count;i++)
         {
            ulong ticket=HistoryDealGetTicket(i);
            if(ticket==0) return false;
            const datetime t=(datetime)HistoryDealGetInteger(ticket,DEAL_TIME);
            if(earliest==0 || t<earliest) earliest=t;
            const ENUM_DEAL_TYPE type=(ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket,DEAL_TYPE);
            if(type!=DEAL_TYPE_BUY && type!=DEAL_TYPE_SELL) continue;
            if((ulong)HistoryDealGetInteger(ticket,DEAL_MAGIC)!=InpMagic) continue;
            const ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket,DEAL_ENTRY);
            if(entry!=DEAL_ENTRY_IN && entry!=DEAL_ENTRY_INOUT) continue;
            const ulong id=(ulong)HistoryDealGetInteger(ticket,DEAL_POSITION_ID);
            int p=Find(id);
            if(p<0)
            {
               p=ArraySize(m_ledger); ArrayResize(m_ledger,p+1);
               ZeroMemory(m_ledger[p]); m_ledger[p].id=id; m_ledger[p].entry_time=t;
            }
         }
         if(m_loaded && (count<previous_count ||
            (previous_first>0 && (earliest==0 || earliest>previous_first)))) return false;
         m_seen_deals=count; m_first_deal=earliest;
      }
      for(int i=0;i<count;i++)
      {
         const ulong ticket=HistoryDealGetTicket(i);
         if(ticket==0) return false;
         const datetime t=(datetime)HistoryDealGetInteger(ticket,DEAL_TIME);
         const ENUM_DEAL_TYPE type=(ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket,DEAL_TYPE);
         const double net=HistoryDealGetDouble(ticket,DEAL_PROFIT)+
            HistoryDealGetDouble(ticket,DEAL_COMMISSION)+
            HistoryDealGetDouble(ticket,DEAL_SWAP)+HistoryDealGetDouble(ticket,DEAL_FEE);
         if(!MathIsValidNumber(net)) return false;
         const bool cash=CashFlow(type);
         if(t>=m_day) { m_day_delta+=net; if(cash) m_day_cash+=net; }
         if(t>=m_week) { m_week_delta+=net; if(cash) m_week_cash+=net; }
         if(!full) continue;
         if(cash) m_all_cash+=net;
         const ulong id=(ulong)HistoryDealGetInteger(ticket,DEAL_POSITION_ID);
         const int p=Find(id);
         if(p<0) continue;
         m_ledger[p].net+=net;
         if(type!=DEAL_TYPE_BUY && type!=DEAL_TYPE_SELL) continue;
         const double volume=HistoryDealGetDouble(ticket,DEAL_VOLUME);
         const ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket,DEAL_ENTRY);
         if(entry==DEAL_ENTRY_IN) m_ledger[p].in_volume+=volume;
         else if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_OUT_BY)
         { m_ledger[p].out_volume+=volume; m_ledger[p].exit_time=t; }
         else if(entry==DEAL_ENTRY_INOUT)
         {
            // EA forbids reversals/mixed netting. Unknown reversal accounting is unsafe.
            m_snapshot.reason="Netting reversal in owned position history: manual audit required";
            return false;
         }
      }
      m_snapshot.trades_today=0;
      for(int i=0;i<ArraySize(m_ledger);i++)
         if(m_ledger[i].entry_time>=m_day) m_snapshot.trades_today++;
      m_snapshot.losses=0;
      datetime before=now+1;
      ulong before_id=0;
      for(int n=0;n<ArraySize(m_ledger);n++)
      {
         int selected=-1; datetime latest=0;
         for(int i=0;i<ArraySize(m_ledger);i++)
            if((m_ledger[i].exit_time>latest ||
                (selected>=0 && m_ledger[i].exit_time==latest && m_ledger[i].id>m_ledger[selected].id)) &&
               (m_ledger[i].exit_time<before ||
                (m_ledger[i].exit_time==before && m_ledger[i].id<before_id)) &&
               m_ledger[i].out_volume+1e-8>=m_ledger[i].in_volume &&
               m_ledger[i].in_volume>0 && !PositionAlive(m_ledger[i].id))
            { latest=m_ledger[i].exit_time; selected=i; }
         if(selected<0) break;
         if(latest<m_day) break;
         before=latest; before_id=m_ledger[selected].id;
         if(m_ledger[selected].net< -0.0000001) m_snapshot.losses++;
         else break;
      }
      m_history_checked=now;
      return true;
   }
   bool Exposure()
   {
      m_snapshot.risk_reserved=0;
      m_own_positions=0; m_own_pending=0;
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         const ulong ticket=PositionGetTicket(i);
         if(ticket==0) return false;
         if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
         m_own_positions++;
         const string symbol=PositionGetString(POSITION_SYMBOL);
         const double sl=PositionGetDouble(POSITION_SL);
         const double open=PositionGetDouble(POSITION_PRICE_OPEN);
         const double volume=PositionGetDouble(POSITION_VOLUME);
         if(sl<=0 || volume<=0) { m_snapshot.reason="Owned position has no reliable stop"; return false; }
         const ENUM_ORDER_TYPE type=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY ? ORDER_TYPE_BUY:ORDER_TYPE_SELL;
         const double worst=sl+(type==ORDER_TYPE_BUY ? -1.0:1.0)*InpSlippagePips*CRTPip(symbol);
         double pnl=0;
         if(!OrderCalcProfit(type,symbol,volume,open,worst,pnl)) return false;
         m_snapshot.risk_reserved+=MathMax(0.0,-pnl)+volume*InpCommissionPerLot;
      }
      for(int i=OrdersTotal()-1;i>=0;i--)
      {
         const ulong ticket=OrderGetTicket(i);
         if(ticket==0) return false;
         if((ulong)OrderGetInteger(ORDER_MAGIC)!=InpMagic) continue;
         m_own_pending++;
         const string symbol=OrderGetString(ORDER_SYMBOL);
         const double sl=OrderGetDouble(ORDER_SL),open=OrderGetDouble(ORDER_PRICE_OPEN);
         const double volume=OrderGetDouble(ORDER_VOLUME_CURRENT);
         const ENUM_ORDER_TYPE pending=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
         const bool buy=pending==ORDER_TYPE_BUY_LIMIT || pending==ORDER_TYPE_BUY_STOP || pending==ORDER_TYPE_BUY_STOP_LIMIT;
         const bool sell=pending==ORDER_TYPE_SELL_LIMIT || pending==ORDER_TYPE_SELL_STOP || pending==ORDER_TYPE_SELL_STOP_LIMIT;
         if(sl<=0 || volume<=0 || (!buy && !sell))
         { m_snapshot.reason="Owned order has unreliable risk"; return false; }
         double pnl=0;
         const double worst=sl+(buy ? -1.0:1.0)*InpSlippagePips*CRTPip(symbol);
         if(!OrderCalcProfit(buy ? ORDER_TYPE_BUY:ORDER_TYPE_SELL,symbol,volume,open,worst,pnl)) return false;
         m_snapshot.risk_reserved+=MathMax(0.0,-pnl)+volume*InpCommissionPerLot;
      }
      // Conservative additional reserve: account-wide floating losses, including foreign trades.
      m_snapshot.risk_reserved+=MathMax(0.0,m_snapshot.balance-m_snapshot.equity);
      return MathIsValidNumber(m_snapshot.risk_reserved);
   }
public:
   CRiskManager()
   {
      ZeroMemory(m_snapshot);
      m_day=0; m_week=0; m_history_checked=0; m_first_deal=0;
      m_reference=0; m_high=0; m_day_reference=0; m_week_reference=0; m_cash_origin=0;
      m_day_cash=0; m_week_cash=0; m_all_cash=0; m_day_delta=0; m_week_delta=0;
      m_locks=0; m_own_positions=0; m_own_pending=0; m_seen_deals=0;
      m_dirty=true; m_loaded=false; m_ready=false; m_persistence_error=false;
   }
   void Invalidate() { m_dirty=true; m_history_checked=0; }
   SRiskSnapshot Snapshot() { return m_snapshot; }
   bool Save()
   {
      if(!m_ready) return false;
      bool ok=Put("version",0);
      if(!Put("reference",m_reference)) ok=false;
      if(!Put("high",m_high)) ok=false;
      if(!Put("dayref",m_day_reference)) ok=false;
      if(!Put("weekref",m_week_reference)) ok=false;
      if(!Put("cashorigin",m_cash_origin)) ok=false;
      if(!Put("day",(double)m_day)) ok=false;
      if(!Put("week",(double)m_week)) ok=false;
      if(!Put("locks",(double)m_locks)) ok=false;
      if(!Put("seen",(double)m_seen_deals)) ok=false;
      if(!Put("first",(double)m_first_deal)) ok=false;
      if(ok) ok=Put("version",3);
      GlobalVariablesFlush();
      if(!ok) m_persistence_error=true;
      return ok;
   }
   bool Init()
   {
      string reason="";
      if(!m_prop.Valid(reason)) { m_snapshot.reason=reason; return false; }
      const datetime now=CRTNow();
      if(now<=0) { m_snapshot.reason="Trade-server clock unavailable"; return false; }
      const bool marker=GlobalVariableCheck(Key("version"));
      m_loaded=Load();
      if(marker && !m_loaded)
      { m_snapshot.reason="Risk state corrupt/incomplete: fail closed"; return false; }
      const datetime old_day=m_day,old_week=m_week;
      m_day=m_period.DayStart(now); m_week=m_period.WeekStart(now);
      if(!History(now,true))
      { if(m_snapshot.reason=="") m_snapshot.reason="Account history unavailable/incomplete"; return false; }
      if(!m_loaded)
      {
         bool own_live=false;
         for(int i=PositionsTotal()-1;i>=0;i--)
            if(PositionGetTicket(i)>0 && (ulong)PositionGetInteger(POSITION_MAGIC)==InpMagic) own_live=true;
         for(int i=OrdersTotal()-1;i>=0;i--)
            if(OrderGetTicket(i)>0 && (ulong)OrderGetInteger(ORDER_MAGIC)==InpMagic) own_live=true;
         if((ArraySize(m_ledger)>0 || own_live) && InpRecoveryReferenceBalance<=0)
         { m_snapshot.reason="Missing risk reference with prior own activity: fail closed"; return false; }
         m_reference=InpRecoveryReferenceBalance>0 ? InpRecoveryReferenceBalance:m_dd.ReferenceValue();
         m_high=m_reference; m_cash_origin=m_all_cash;
         m_locks=0;
      }
      if(!m_loaded || old_day!=m_day)
      { m_day_reference=AccountInfoDouble(ACCOUNT_BALANCE)-m_day_delta; m_locks&=~1; }
      if(!m_loaded || old_week!=m_week)
      { m_week_reference=AccountInfoDouble(ACCOUNT_BALANCE)-m_week_delta; m_locks&=~2; }
      if(m_reference<=0 || m_day_reference<=0 || m_week_reference<=0)
      { m_snapshot.reason="Non-positive risk reference"; return false; }
      m_ready=true; m_dirty=false;
      if(!Save()) { m_snapshot.reason="Risk persistence unavailable"; return false; }
      m_loaded=true;
      return Refresh();
   }
   bool Refresh()
   {
      m_snapshot.valid=false; m_snapshot.locked=true;
      if(!m_ready || m_persistence_error)
      { if(m_snapshot.reason=="") m_snapshot.reason="Risk persistence not ready"; return false; }
      const datetime now=CRTNow();
      const datetime day=m_period.DayStart(now),week=m_period.WeekStart(now);
      if(day<m_day || week<m_week) { m_snapshot.reason="Server reset boundary moved backwards"; return false; }
      const bool rollover=day!=m_day || week!=m_week;
      const bool full=m_dirty || rollover;
      if(full || now<m_history_checked || now-m_history_checked>=1)
      {
         const datetime old_day=m_day,old_week=m_week;
         m_day=day; m_week=week;
         if(!History(now,full))
         { if(m_snapshot.reason=="") m_snapshot.reason="Risk history refresh failed"; return false; }
         if(old_day!=day)
         { m_day_reference=AccountInfoDouble(ACCOUNT_BALANCE)-m_day_delta; m_locks&=~1; }
         if(old_week!=week)
         { m_week_reference=AccountInfoDouble(ACCOUNT_BALANCE)-m_week_delta; m_locks&=~2; }
         m_dirty=false;
      }
      m_snapshot.balance=AccountInfoDouble(ACCOUNT_BALANCE);
      m_snapshot.equity=AccountInfoDouble(ACCOUNT_EQUITY);
      if(MathAbs(AccountInfoDouble(ACCOUNT_CREDIT))>0.000001)
      { m_snapshot.reason="Non-zero account credit requires unsupported credit accounting"; return false; }
      if(m_snapshot.balance<=0 || m_snapshot.equity<=0 ||
         !MathIsValidNumber(m_snapshot.equity))
      { m_snapshot.reason="Invalid account funds"; return false; }
      const double neutral_cash=m_all_cash-m_cash_origin;
      const double reference_now=m_dd.ReferenceValue()-neutral_cash;
      const double previous_high=m_high;
      if(m_dd.Trailing()) m_high=MathMax(m_high,reference_now);
      const double total_ref=m_dd.Trailing() ? m_high:m_reference;
      const double day_eq=m_snapshot.equity-m_day_cash;
      const double week_eq=m_snapshot.equity-m_week_cash;
      const double total_eq=m_snapshot.equity-neutral_cash;
      m_snapshot.daily_pnl=day_eq-m_day_reference;
      m_snapshot.daily_dd=m_dd.Percent(m_day_reference,day_eq);
      m_snapshot.weekly_dd=m_dd.Percent(m_week_reference,week_eq);
      m_snapshot.total_dd=m_dd.Percent(total_ref,total_eq);
      const int old_locks=m_locks;
      if(m_snapshot.daily_dd>=InpDailyLossLimitPercent) m_locks|=1;
      if(m_snapshot.weekly_dd>=InpWeeklyLossLimitPercent) m_locks|=2;
      if(m_snapshot.total_dd>=InpTotalDrawdownLimitPercent) m_locks|=4;
      if(!Exposure())
      { if(m_snapshot.reason=="") m_snapshot.reason="Cannot calculate aggregate exposure"; return false; }
      if((old_locks!=m_locks || previous_high!=m_high || full) && !Save())
      { m_snapshot.reason="Cannot persist risk lock/reference"; return false; }
      m_snapshot.valid=true;
      m_snapshot.locked=m_locks!=0 || m_snapshot.losses>=InpMaximumConsecutiveLosses ||
                        m_snapshot.trades_today>=InpMaximumTradesPerDay;
      if((m_locks&4)!=0) m_snapshot.reason="Total drawdown lock";
      else if((m_locks&2)!=0) m_snapshot.reason="Weekly loss lock";
      else if((m_locks&1)!=0) m_snapshot.reason="Daily loss lock";
      else if(m_snapshot.losses>=InpMaximumConsecutiveLosses) m_snapshot.reason="Consecutive-loss lock";
      else if(m_snapshot.trades_today>=InpMaximumTradesPerDay) m_snapshot.reason="Daily trade-count lock";
      else m_snapshot.reason="";
      return true;
   }
   double Budget(const double risk_percent)
   {
      if(!Refresh() || m_snapshot.locked || risk_percent<=0) return 0;
      return m_prop.Base()*MathMin(risk_percent,InpRiskCeilingPercent)/100.0;
   }
   bool Allow(const double requested_money,string &reason)
   {
      if(!Refresh() || !m_snapshot.valid || m_snapshot.locked)
      { reason=m_snapshot.reason; return false; }
      if(requested_money<=0 || !MathIsValidNumber(requested_money) ||
         requested_money>m_prop.Base()*InpRiskCeilingPercent/100.0+0.000001)
      { reason="Requested risk is invalid or exceeds hard ceiling"; return false; }
      if(m_own_positions>=InpMaximumOwnPositions || m_own_pending>=InpMaximumOwnPendings)
      { reason="Owned position/pending capacity reached"; return false; }
      const double total_ref=m_dd.Trailing() ? m_high:m_reference;
      const double day_available=m_dd.Remaining(m_day_reference,m_snapshot.equity-m_day_cash,InpDailyLossLimitPercent);
      const double week_available=m_dd.Remaining(m_week_reference,m_snapshot.equity-m_week_cash,InpWeeklyLossLimitPercent);
      const double total_available=m_dd.Remaining(total_ref,m_snapshot.equity-(m_all_cash-m_cash_origin),InpTotalDrawdownLimitPercent);
      const double available=MathMin(day_available,MathMin(week_available,total_available));
      if(requested_money+m_snapshot.risk_reserved>=available)
      { reason="Aggregate stops/floating reserve would exceed drawdown headroom"; return false; }
      return true;
   }
};
#endif
