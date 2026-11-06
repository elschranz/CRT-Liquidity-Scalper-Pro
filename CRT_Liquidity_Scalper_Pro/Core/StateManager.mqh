#ifndef CRT_CORE_STATE_MANAGER_MQH
#define CRT_CORE_STATE_MANAGER_MQH
#include "Utilities.mqh"
class CStateManager {
 private:
 EEngineState m_state;
 string m_reason;
 bool m_paused,m_entries;
 double m_risk;
 bool TransitionAllowed(EEngineState next) {
  if(next==m_state || next==RISK_LOCKED || next==PAUSED || next==POSITION_OPEN || next==ORDER_PENDING) return true;
  switch(m_state) {
   case IDLE: return next==CRT_DETECTED || next==SIGNAL_EXPIRED;
   case CRT_DETECTED: return next==WAITING_RETEST || next==WAITING_M1_CONFIRMATION || next==SIGNAL_EXPIRED || next==IDLE;
   case WAITING_RETEST: return next==WAITING_M1_CONFIRMATION || next==SIGNAL_EXPIRED || next==IDLE || next==CRT_DETECTED;
   case WAITING_M1_CONFIRMATION: return next==WAITING_RETEST || next==SIGNAL_EXPIRED || next==IDLE || next==CRT_DETECTED;
   case ORDER_PENDING: case POSITION_OPEN: return next==IDLE || next==SIGNAL_EXPIRED || next==CRT_DETECTED;
   case SIGNAL_EXPIRED: return next==IDLE || next==CRT_DETECTED;
   case PAUSED: case RISK_LOCKED: return true;
  }
  return false;
 }
 public:
 CStateManager():m_state(IDLE),m_reason(""),m_paused(false),m_entries(true),m_risk(.25) {}
 bool Init() {
  m_paused=(bool)CRTGlobal("ui.paused",InpStartPaused ? 1.0:0.0);
  m_entries=(bool)CRTGlobal("ui.entries",1);
  m_risk=MathMin(CRTGlobal("ui.risk",InpRiskPerTradePercent),InpRiskCeilingPercent);
  if(m_risk<=0) m_risk=InpRiskPerTradePercent;
  return Save();
 }
 bool Save() {
  bool ok=CRTSetGlobal("ui.paused",m_paused?1:0);
  ok=CRTSetGlobal("ui.entries",m_entries?1:0) && ok;
  ok=CRTSetGlobal("ui.risk",m_risk) && ok;
  GlobalVariablesFlush();
  return ok;
 }
 bool SaveSignal(const SSignal &s) {
  int h=FileOpen(CRTKey("signal.csv"),FILE_WRITE|FILE_CSV|FILE_ANSI,',');
  if(h==INVALID_HANDLE) return false;
  uint written=FileWrite(h,1,s.id,(int)s.direction,(long)s.reference_time,(long)s.confirmed_at,
   (long)s.expires_at,(long)s.retest_time,(long)s.m1_confirmation,s.level,s.extreme,
   s.range_high,s.range_low,s.atr_pips,s.m1_extreme,(int)s.active,(int)s.retested,(int)s.confirmed,(int)s.consumed);
  FileFlush(h); FileClose(h);
  return written>0;
 }
 bool LoadSignal(SSignal &s) {
  ZeroMemory(s);
  int h=FileOpen(CRTKey("signal.csv"),FILE_READ|FILE_CSV|FILE_ANSI,',');
  if(h==INVALID_HANDLE) return false;
  int version=(int)FileReadNumber(h);
  s.id=FileReadString(h); s.direction=(EDirection)(int)FileReadNumber(h);
  s.reference_time=(datetime)(long)FileReadNumber(h); s.confirmed_at=(datetime)(long)FileReadNumber(h);
  s.expires_at=(datetime)(long)FileReadNumber(h); s.retest_time=(datetime)(long)FileReadNumber(h);
  s.m1_confirmation=(datetime)(long)FileReadNumber(h); s.level=FileReadNumber(h);
  s.extreme=FileReadNumber(h); s.range_high=FileReadNumber(h); s.range_low=FileReadNumber(h);
  s.atr_pips=FileReadNumber(h); s.m1_extreme=FileReadNumber(h);
  s.active=(bool)FileReadNumber(h); s.retested=(bool)FileReadNumber(h);
  s.confirmed=(bool)FileReadNumber(h); s.consumed=(bool)FileReadNumber(h);
  FileClose(h);
  bool ok=version==1 && s.id!="" && (s.direction==DIR_BUY || s.direction==DIR_SELL)
   && s.level>0 && s.extreme>0 && s.range_high>s.range_low && s.expires_at>s.confirmed_at;
  if(!ok) ZeroMemory(s);
  return ok;
 }
 bool Set(EEngineState state,const string reason) {
  if(!TransitionAllowed(state)) return false;
  m_state=state; m_reason=reason; return true;
 }
 EEngineState State() { return m_state; }
 string Reason() { return m_reason; }
 bool Paused() { return m_paused; }
 bool Entries() { return m_entries; }
 double Risk() { return m_risk; }
 void TogglePause() { m_paused=!m_paused; Save(); }
 void ToggleEntries() { m_entries=!m_entries; Save(); }
 void SetRisk(double value) { if(value>0 && value<=InpRiskCeilingPercent) { m_risk=value; Save(); } }
 string Name() {
  switch(m_state) {
   case IDLE: return "WAITING CRT";
   case CRT_DETECTED: return "CRT DETECTED";
   case WAITING_RETEST: return "WAITING RETEST";
   case WAITING_M1_CONFIRMATION: return "WAITING M1 CONFIRMATION";
   case ORDER_PENDING: return "ORDER PENDING";
   case POSITION_OPEN: return "POSITION OPEN";
   case SIGNAL_EXPIRED: return "SIGNAL EXPIRED";
   case PAUSED: return "PAUSED";
   case RISK_LOCKED: return "RISK LOCKED";
  }
  return "WAITING";
 }
};
#endif
