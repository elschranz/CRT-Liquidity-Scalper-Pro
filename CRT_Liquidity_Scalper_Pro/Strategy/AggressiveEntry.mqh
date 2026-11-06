#ifndef CRT_AGGRESSIVE_ENTRY_MQH
#define CRT_AGGRESSIVE_ENTRY_MQH
#include "../Core/Config.mqh"
#include "../Core/Utilities.mqh"
class CAggressiveEntry
{
public:
   bool Evaluate(const SSignal &signal,const MqlTick &tick,STradePlan &plan,string &reason) const
   {
      double pip=CRTPip(CRTSymbol());
      double entry=CRTPrice(CRTSymbol(),signal.level+(int)signal.direction*InpEntryOffsetPips*pip);
      if((signal.direction==DIR_BUY && entry>=tick.ask) || (signal.direction==DIR_SELL && entry<=tick.bid))
      { reason="Limit price not on valid side of market"; return false; }
      ZeroMemory(plan); plan.signal_id=signal.id; plan.direction=signal.direction;
      plan.mode=ENTRY_AGGRESSIVE; plan.pending=true; plan.created=TimeCurrent();
      plan.expiration=(datetime)MathMin((double)signal.expires_at,(double)(signal.confirmed_at+InpPendingExpirationMinutes*60));
      if(plan.expiration<=TimeCurrent()) { reason="Pending window expired"; return false; }
      plan.entry=entry; plan.atr_pips=signal.atr_pips;
      return true;
   }
};
#endif
