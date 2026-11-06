#property copyright "CRT Liquidity Scalper Pro"
#property version "1.00"
#property strict
#property description "Closed-bar CRT M5, M1 entries, persistent risk controls. Validate on demo before live use."
#include "Core/Config.mqh"
#include "Core/StateManager.mqh"
#include "Core/Logger.mqh"
#include "Strategy/ATRManager.mqh"
#include "Strategy/CRTDetector.mqh"
#include "Strategy/LiquidityDetector.mqh"
#include "Strategy/M1EntryEngine.mqh"
#include "Strategy/DynamicTargets.mqh"
#include "Strategy/SessionManager.mqh"
#include "Risk/RiskManager.mqh"
#include "Filters/SpreadFilter.mqh"
#include "Filters/VolatilityFilter.mqh"
#include "Filters/NewsFilter.mqh"
#include "Filters/TradingHoursFilter.mqh"
#include "Trading/LotCalculator.mqh"
#include "Trading/ExecutionValidator.mqh"
#include "Trading/TradeExecutor.mqh"
#include "Trading/OrderManager.mqh"
#include "Trading/PositionManager.mqh"
#include "Analytics/TradeJournal.mqh"
#include "Analytics/Statistics.mqh"
#include "Analytics/BacktestMetrics.mqh"
#include "UI/Dashboard.mqh"
#include "UI/DashboardEvents.mqh"
#include "UI/ChartVisualizer.mqh"
#include "UI/Notifications.mqh"

CStateManager g_state;
CLogger g_log;
CATRManager g_atr;
CCRTDetector g_crt;
CLiquidityDetector g_liquidity;
CM1EntryEngine g_entry,g_virtual_a,g_virtual_b;
CDynamicTargets g_targets;
CSessionManager g_sessions;
CRiskManager g_risk;
CSpreadFilter g_spread;
CVolatilityFilter g_volatility;
CNewsFilter g_news;
CTradingHoursFilter g_hours;
CLotCalculator g_lots;
CExecutionValidator g_validator;
CTradeExecutor g_executor;
COrderManager g_orders;
CPositionManager g_positions;
CTradeJournal g_journal;
CStatistics g_statistics;
CBacktestMetrics g_comparison;
CDashboard g_dashboard;
CChartVisualizer g_visuals;
CNotifications g_notifications;
SSignal g_signal,g_compare_a,g_compare_b;
STradePlan g_plan;
EEntryMode g_mode=ENTRY_AGGRESSIVE,g_real_mode=ENTRY_AGGRESSIVE;
bool g_ready=false,g_reconciling=false,g_storage_ok=true;
string g_last_reason="",g_gate_reason="";
datetime g_last_ui=0;

EEntryMode RealMode() { return g_mode==ENTRY_BOTH_COMPARE ? g_real_mode:g_mode; }

void Reject(const string reason,const bool expire=true) {
 g_last_reason=reason;
 g_log.Write("SIGNAL",reason);
 if(g_signal.id!="") g_journal.Signal(g_signal,"REJECT",reason);
 if(expire) {
  g_signal.active=false; g_signal.consumed=true; g_signal.reason=reason;
  g_storage_ok=g_state.SaveSignal(g_signal) && g_storage_ok;
  g_state.Set(SIGNAL_EXPIRED,reason);
 }
}
void CancelPending(const string reason) {
 if(g_orders.Count()==0) return;
 string result="";
 bool ok=g_orders.CancelOwn(result);
 g_log.Write(ok ? "CANCEL":"CANCEL ERROR",reason+" "+result);
 g_notifications.Send("cancel."+g_signal.id,reason+" "+result);
}
bool BaseGates(const MqlTick &tick,string &reason) {
 if(!g_storage_ok) { reason="Persistence unavailable; entries blocked"; return false; }
 SRiskSnapshot risk=g_risk.Snapshot();
 if(!risk.valid || risk.locked) { reason=risk.reason; return false; }
 if(g_state.Paused()) { reason="Paused by user"; return false; }
 if(!g_state.Entries()) { reason="Entries disabled"; return false; }
 if(!TerminalInfoInteger(TERMINAL_CONNECTED)) { reason="Disconnected"; return false; }
 if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED) ||
    !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) || !AccountInfoInteger(ACCOUNT_TRADE_EXPERT)) {
  reason="Trading permission disabled"; return false;
 }
 if(tick.time<=0 || TimeCurrent()-tick.time>10) { reason="Stale execution tick"; return false; }
 if(!g_spread.Allowed(tick,reason) || !g_volatility.Allowed(g_atr.Pips(),reason) ||
    !g_hours.Allowed(TimeCurrent(),reason) || !g_news.Allowed(TimeCurrent(),reason)) return false;
 return true;
}
void Protect(const MqlTick &tick) {
 g_risk.Refresh();
 g_orders.Maintain(g_signal);
 g_positions.Manage(g_atr.Pips());
 SRiskSnapshot r=g_risk.Snapshot();
 string reason="";
 bool allowed=BaseGates(tick,reason);
 g_gate_reason=allowed ? "":reason;
 if(!allowed) {
  CancelPending(reason);
  if(!r.valid || r.locked) {
   g_state.Set(RISK_LOCKED,reason);
   g_notifications.Send("risk."+reason,reason);
   bool hard_dd=r.daily_dd>=InpDailyLossLimitPercent || r.weekly_dd>=InpWeeklyLossLimitPercent ||
                r.total_dd>=InpTotalDrawdownLimitPercent;
   if(InpCloseOwnPositionsOnRiskLock && (hard_dd || !r.valid) && g_positions.Count()>0) {
    string result=""; g_positions.CloseOwn(result); g_log.Write("RISK CLOSE",result);
   }
  } else if(g_state.Paused() || !g_state.Entries()) g_state.Set(PAUSED,reason);
 }
 if(g_positions.Count()>0) g_state.Set(POSITION_OPEN,"Managing owned position");
 else if(g_orders.Count()>0) g_state.Set(ORDER_PENDING,"Broker pending order");
 else if(allowed && !g_signal.active) g_state.Set(IDLE,g_last_reason);
}
void PollCRT(const MqlTick &tick) {
 SSignal next; ZeroMemory(next); string reason="";
 if(!g_crt.Poll(next,reason)) return;
 // Durable consumed-bar watermark is written before accepting any signal.
 datetime watermark=(datetime)(long)CRTGlobal("processedCRT",0);
 if(next.confirmed_at<=watermark) return;
 if(!CRTSetGlobal("processedCRT",(double)next.confirmed_at)) { g_storage_ok=false; return; }
 GlobalVariablesFlush();
 g_journal.Signal(next,"CRT",reason);
 g_notifications.Send("crt."+next.id,CRTDirection(next.direction)+" CRT "+next.id);
 if(g_positions.Count()>0 || g_orders.Count()>0 || (g_mode==ENTRY_BOTH_COMPARE && g_comparison.Busy()) || (g_signal.active && !g_signal.consumed)) {
  g_journal.Signal(next,"REJECT","One active setup/exposure at a time"); return;
 }
 if(!BaseGates(tick,reason)) { g_journal.Signal(next,"REJECT",reason); g_last_reason=reason; return; }
 g_liquidity.Refresh(next.reference_time);
 if(!g_liquidity.Qualifies(next,reason)) { g_journal.Signal(next,"REJECT",reason); g_last_reason=reason; return; }
 next.atr_pips=g_atr.Pips();
 g_signal=next; g_compare_a=next; g_compare_b=next;
 g_entry.Reset(g_signal); g_virtual_a.Reset(g_compare_a); g_virtual_b.Reset(g_compare_b);
 g_comparison.Reset(next);
 g_liquidity.Consume(next);
 ZeroMemory(g_plan);
 g_storage_ok=g_state.SaveSignal(g_signal) && g_storage_ok;
 if(!g_storage_ok) { Reject("Cannot persist signal"); return; }
 g_state.Set(CRT_DETECTED,"Closed M5 CRT confirmed");
 g_state.Set(WAITING_RETEST,"Waiting for eligible M1/tick retest");
 g_visuals.Show(g_signal,g_plan);
}
bool SignalValid(SSignal &signal,const MqlTick &tick,string &reason) {
 if(!signal.active || signal.consumed) return false;
 if(TimeCurrent()>=signal.expires_at) { reason="Signal expired"; return false; }
 if((signal.direction==DIR_BUY && tick.bid<signal.extreme) ||
    (signal.direction==DIR_SELL && tick.ask>signal.extreme)) {
  reason="Manipulation extreme broken before entry"; return false;
 }
 return true;
}
void CompareMode(SSignal &signal,CM1EntryEngine &engine,EEntryMode mode,const MqlTick &tick) {
 if(!signal.active || signal.consumed) return;
 string reason="";
 if(g_state.Paused() || !g_state.Entries() || !g_spread.Allowed(tick,reason) ||
    !g_volatility.Allowed(g_atr.Pips(),reason) || !g_hours.Allowed(TimeCurrent(),reason) ||
    !g_news.Allowed(TimeCurrent(),reason)) return;
 if(!SignalValid(signal,tick,reason)) { signal.active=false; return; }
 STradePlan candidate; ZeroMemory(candidate);
 if(!engine.Evaluate(signal,mode,tick,candidate,reason)) return;
 signal.consumed=true;
 if(!g_targets.Build(signal,candidate,g_liquidity,reason)) {
  g_journal.Plan(signal,candidate,"VIRTUAL_REJECT",reason); return;
 }
 // Virtual trades have their own price/R ledger; never call Submit or reserve real money.
 g_comparison.OnPlan(signal,candidate);
}
void EvaluateEntry(const MqlTick &tick) {
 string reason="";
 if(g_mode==ENTRY_BOTH_COMPARE) {
  CompareMode(g_compare_a,g_virtual_a,ENTRY_AGGRESSIVE,tick);
  CompareMode(g_compare_b,g_virtual_b,ENTRY_CONFIRMED,tick);
  g_comparison.Tick(tick);
 }
 if(!g_signal.active || g_signal.consumed || g_positions.Count()>0 || g_orders.Count()>0 || g_executor.Uncertain()) return;
 if(!SignalValid(g_signal,tick,reason)) { Reject(reason); return; }
 if(!BaseGates(tick,reason)) { g_last_reason=reason; return; }
 STradePlan candidate; ZeroMemory(candidate);
 bool had_retest=g_signal.retested,had_confirmation=g_signal.confirmed;
 if(!g_entry.Evaluate(g_signal,RealMode(),tick,candidate,reason)) {
  if(g_signal.retested) g_state.Set(WAITING_M1_CONFIRMATION,reason);
  if(!had_retest && g_signal.retested) {
   g_journal.Signal(g_signal,"RETEST",reason);
   g_notifications.Send("retest."+g_signal.id,"Retest "+g_signal.id);
   g_storage_ok=g_state.SaveSignal(g_signal) && g_storage_ok;
  }
  g_last_reason=reason;
  return;
 }
 if(!had_confirmation && g_signal.confirmed) {
  g_journal.Signal(g_signal,"CONFIRMATION","Closed M1 rejection");
  g_notifications.Send("confirmed."+g_signal.id,"M1 confirmed "+g_signal.id);
 }
 if(!g_targets.Build(g_signal,candidate,g_liquidity,reason)) { Reject(reason); return; }
 if(!g_lots.Size(candidate,g_risk.Budget(g_state.Risk()),reason)) { Reject(reason); return; }
 if(!g_risk.Allow(candidate.risk_money,reason) || !g_validator.Validate(candidate,reason)) {
  g_journal.Plan(g_signal,candidate,"REJECT",reason); Reject(reason); return;
 }
 // Consume before sending. An uncertain response never causes a retry.
 g_signal.consumed=true;
 g_storage_ok=g_state.SaveSignal(g_signal) && g_storage_ok;
 if(!g_storage_ok) { Reject("Cannot persist execution intent"); return; }
 g_plan=candidate;
 g_journal.Plan(g_signal,g_plan,"REQUEST","");
 bool accepted=g_executor.Submit(g_plan,reason);
 g_log.Write("EXECUTION",reason);
 g_notifications.Send("order."+g_signal.id,reason);
 if(!accepted) { Reject(reason); return; }
 g_executor.Reconcile();
 if(g_positions.Count()>0) {
  g_reconciling=true;
  string validation=""; g_executor.RevalidateFill(g_plan,validation);
  g_reconciling=false;
  if(validation!="") g_log.Write("FILL",validation);
  g_state.Set(POSITION_OPEN,"Filled; actual execution revalidated");
 } else g_state.Set(ORDER_PENDING,"Accepted; awaiting broker reconciliation");
 g_visuals.Show(g_signal,g_plan);
}
void Render() {
 SDashboardView v; ZeroMemory(v);
 SRiskSnapshot r=g_risk.Snapshot();
 SStatistics stats=g_statistics.Snapshot();
 MqlTick tick; ZeroMemory(tick); CRTTick(CRTSymbol(),tick);
 v.state=g_state.Name();
 if(g_gate_reason!="" && StringFind(g_gate_reason,"news")>=0) v.state="NEWS BLOCK";
 v.reason=g_gate_reason!="" ? g_gate_reason:g_last_reason;
 v.session=g_sessions.Name(TimeCurrent()); v.signal=g_signal.id; v.news=g_news.Status();
 v.balance=AccountInfoDouble(ACCOUNT_BALANCE); v.equity=AccountInfoDouble(ACCOUNT_EQUITY);
 v.daily_pnl=r.daily_pnl; v.daily_dd=r.daily_dd; v.weekly_dd=r.weekly_dd; v.total_dd=r.total_dd;
 v.risk_percent=g_state.Risk(); v.spread=CRTPips(CRTSymbol(),tick.ask-tick.bid); v.atr=g_atr.Pips();
 v.sl_pips=g_plan.entry>0 ? CRTPips(CRTSymbol(),MathAbs(g_plan.entry-g_plan.sl)):0; v.rr=g_plan.rr;
 v.trades=r.trades_today; v.losses=r.losses; v.entry_mode=g_mode==ENTRY_BOTH_COMPARE ? g_real_mode:g_mode;
 v.paused=g_state.Paused(); v.entries_enabled=g_state.Entries(); v.risk_locked=r.locked || !r.valid || !g_storage_ok;
 v.winrate=stats.winrate; v.net=stats.net; v.pf=stats.pf; v.expectancy_r=stats.expectancy_r; v.closed_trades=stats.trades;
 g_dashboard.Update(v);
}
int OnInit() {
 string reason="";
 if(!CRTCoreConfigValid(reason)) { Print(reason); return INIT_PARAMETERS_INCORRECT; }
 ZeroMemory(g_signal); ZeroMemory(g_plan); ZeroMemory(g_compare_a); ZeroMemory(g_compare_b);
 g_mode=InpEntryMode; g_real_mode=InpRealComparisonMode;
 if(g_real_mode==ENTRY_BOTH_COMPARE) { Print("Comparison real mode must be aggressive or confirmed"); return INIT_PARAMETERS_INCORRECT; }
 g_storage_ok=g_state.Init();
 if(!g_atr.Init()) { Print("ATR handle unavailable"); return INIT_FAILED; }
 g_atr.Refresh();
 if(!g_executor.Init()) { Print("Trade executor initialization failed"); return INIT_FAILED; }
 if(!g_journal.Init()) { Print("Journal unavailable; refusing entries"); return INIT_FAILED; }
 bool recovered=g_state.LoadSignal(g_signal);
 if(recovered) {
  // Recover exposure management, never resume an unsubmitted setup after a restart.
  g_signal.consumed=true;
  g_signal.active=TimeCurrent()<g_signal.expires_at;
  g_state.SaveSignal(g_signal);
 }
 g_executor.Reconcile(); g_positions.Reconcile(); g_positions.Recover(g_plan);
 g_orders.Maintain(g_signal);
 if(!g_risk.Init()) g_last_reason="Risk reference unavailable; locked until reliable recovery";
 g_risk.Refresh(); g_statistics.Refresh();
 if(!g_dashboard.Init()) { Print("Dashboard initialization failed"); return INIT_FAILED; }
 g_visuals.Init();
 if(g_signal.active) g_visuals.Show(g_signal,g_plan);
 if(!EventSetTimer(1)) { Print("Timer unavailable"); return INIT_FAILED; }
 g_ready=true; Render();
 return INIT_SUCCEEDED;
}
void OnTick() {
 if(!g_ready) return;
 MqlTick tick; ZeroMemory(tick);
 if(!CRTTick(CRTSymbol(),tick)) return;
 g_atr.Refresh();
 g_liquidity.Invalidate(tick);
 Protect(tick);
 g_journal.Tick(tick);
 PollCRT(tick);
 EvaluateEntry(tick);
 if(g_signal.active && TimeCurrent()>=g_signal.expires_at && g_orders.Count()==0) {
  g_signal.active=false; g_state.SaveSignal(g_signal);
 }
}
void OnTimer() {
 if(!g_ready) return;
 MqlTick tick; ZeroMemory(tick); CRTTick(CRTSymbol(),tick);
 Protect(tick);
 g_statistics.Refresh();
 g_visuals.ClearExpired(TimeCurrent());
 Render();
}
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam) {
 if(!g_ready) return;
 string action=g_dashboard.Event(id,lparam,dparam,sparam),result="";
 if(action=="START_PAUSE") {
  g_state.TogglePause();
  if(g_state.Paused()) { CancelPending("User pause"); Reject("User pause"); g_comparison.Cancel("Paused"); }
 } else if(action=="TOGGLE_ENTRIES") {
  g_state.ToggleEntries();
  if(!g_state.Entries()) { CancelPending("Entries disabled"); Reject("Entries disabled"); g_comparison.Cancel("Disabled"); }
 } else if(action=="ENTRY_AGGRESSIVE" || action=="ENTRY_CONFIRMED") {
  EEntryMode next=action=="ENTRY_AGGRESSIVE" ? ENTRY_AGGRESSIVE:ENTRY_CONFIRMED;
  if(g_mode==ENTRY_BOTH_COMPARE) g_real_mode=next; else g_mode=next;
  CancelPending("Entry mode changed"); Reject("Entry mode changed"); g_comparison.Cancel("Mode changed");
 } else if(action=="CANCEL_PENDING") {
  CancelPending("User cancel"); Reject("User cancel");
 } else if(action=="CLOSE_POSITIONS") {
  CancelPending("User close"); g_positions.CloseOwn(result);
  Reject("User close "+result); g_log.Write("CLOSE",result);
 } else if(action=="BE") {
  g_positions.MoveToBE(result); g_log.Write("BE",result);
 } else if(action=="LEVELS") g_visuals.Toggle();
 else if(StringFind(action,"RISK_")==0 && !g_risk.Snapshot().locked) {
  if(action=="RISK_010") g_state.SetRisk(.10);
  if(action=="RISK_025") g_state.SetRisk(.25);
  if(action=="RISK_050") g_state.SetRisk(.50);
 }
 Render();
}
void OnTradeTransaction(const MqlTradeTransaction &transaction,const MqlTradeRequest &request,const MqlTradeResult &result) {
 if(!g_ready) return;
 g_executor.Reconcile(); g_positions.Reconcile(); g_risk.Invalidate();
 g_journal.Transaction(transaction,request,result);
 if(g_reconciling || transaction.type!=TRADE_TRANSACTION_DEAL_ADD || transaction.deal==0) return;
 if(!HistoryDealSelect(transaction.deal)) return;
 if((ulong)HistoryDealGetInteger(transaction.deal,DEAL_MAGIC)!=InpMagic ||
    HistoryDealGetString(transaction.deal,DEAL_SYMBOL)!=CRTSymbol()) return;
 ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(transaction.deal,DEAL_ENTRY);
 if(entry==DEAL_ENTRY_IN || entry==DEAL_ENTRY_INOUT) {
  g_reconciling=true;
  CancelPending("Cancel residual after fill");
  STradePlan actual;
  if(g_executor.LastPlan(actual)) {
   string validation=""; g_executor.RevalidateFill(actual,validation);
   g_log.Write("FILL",validation);
  }
  g_reconciling=false;
  g_notifications.Send("fill."+IntegerToString((long)transaction.deal),"Owned fill reconciled");
 } else {
  g_notifications.Send("close."+IntegerToString((long)transaction.deal),"Owned exit reconciled");
 }
 g_risk.Refresh(); g_statistics.Refresh();
}
double OnTester() { return g_comparison.Fitness(); }
void OnDeinit(const int reason) {
 EventKillTimer();
 // Broker-enforced pending expiration remains authoritative if terminal is offline.
 if(g_ready) { CancelPending("EA deinitialization"); g_state.SaveSignal(g_signal); g_risk.Save(); g_state.Save(); }
 g_journal.Close(); g_dashboard.Destroy(); g_visuals.Destroy(); g_atr.Release();
 g_ready=false;
}
