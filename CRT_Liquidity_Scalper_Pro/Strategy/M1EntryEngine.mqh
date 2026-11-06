#ifndef CRT_M1_ENTRY_ENGINE_MQH
#define CRT_M1_ENTRY_ENGINE_MQH
#include "../Core/Config.mqh"
#include "AggressiveEntry.mqh"
#include "ConfirmedEntry.mqh"
class CM1EntryEngine
{
private:
   CAggressiveEntry m_aggressive;
   CConfirmedEntry m_confirmed;
public:
   void Reset(SSignal &signal)
   {
      signal.retested=false; signal.confirmed=false; signal.consumed=false;
      signal.retest_time=0; signal.m1_confirmation=0; signal.m1_extreme=0;
   }
   bool Valid() const
   {
      return InpRealComparisonMode!=ENTRY_BOTH_COMPARE && InpEntryOffsetPips>=0 &&
             InpPendingExpirationMinutes>0 && InpMinRejectionWickPips>=0 &&
             InpMinM1CloseBeyondLevelPips>=0 && InpMaximumChaseDistancePips>0 &&
             InpRetestAreaPips>=0 && InpConfirmationExpirationMinutes>0;
   }
   bool Evaluate(SSignal &signal,const EEntryMode mode,const MqlTick &tick,STradePlan &plan,string &reason)
   {
      reason="";
      if((signal.direction!=DIR_BUY && signal.direction!=DIR_SELL) || tick.bid<=0 || tick.ask<tick.bid)
      { reason="Invalid signal or executable quote"; return false; }
      if(!signal.active || signal.consumed) { reason="Signal inactive or already used"; return false; }
      if(TimeCurrent()>=signal.expires_at) { signal.active=false; reason="Signal expired"; return false; }
      bool invalid=signal.direction==DIR_BUY?tick.bid<signal.extreme:tick.ask>signal.extreme;
      if(invalid) { signal.active=false; reason="Manipulation extreme broken before entry"; return false; }
      if(mode==ENTRY_AGGRESSIVE) return m_aggressive.Evaluate(signal,tick,plan,reason);
      if(mode==ENTRY_CONFIRMED) return m_confirmed.Evaluate(signal,tick,plan,reason);
      reason="BOTH_COMPARE requires one independent engine/signal per mode"; return false;
   }
};
#endif
