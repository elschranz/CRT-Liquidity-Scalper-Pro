#ifndef CRT_CONFIRMED_ENTRY_MQH
#define CRT_CONFIRMED_ENTRY_MQH
#include "../Core/Config.mqh"
#include "../Core/Utilities.mqh"
class CConfirmedEntry
{
public:
   bool Evaluate(SSignal &signal,const MqlTick &tick,STradePlan &plan,string &reason) const
   {
      double pip=CRTPip(CRTSymbol()),area=InpRetestAreaPips*pip;
      datetime now=TimeCurrent();
      if(now>=signal.confirmed_at+InpConfirmationExpirationMinutes*60)
      { reason="M1 confirmation window expired"; return false; }
      // Bid is the chart/close side for BUY rejection. Ask is the SELL liquidation side.
      // The retest is witnessed live after M5 confirmation, never inferred on attach.
      double touch=(signal.direction==DIR_BUY?tick.bid:tick.ask);
      bool touched=signal.direction==DIR_BUY?touch<=signal.level+area:touch>=signal.level-area;
      if(!signal.retested && touched)
      { signal.retested=true; signal.retest_time=now; signal.reason="Retest witnessed"; }
      if(!signal.retested) { reason="Waiting actual bid/ask retest"; return false; }
      MqlRates bars[]; ArraySetAsSeries(bars,true);
      if(CopyRates(CRTSymbol(),PERIOD_M1,0,2,bars)!=2) { reason="M1 history unavailable"; return false; }
      MqlRates c=bars[1];
      // A candle may start before the tick touch, but may not close before it.
      if(c.time<signal.confirmed_at || c.time+60<=signal.retest_time || bars[0].time<c.time+60)
      { reason="Waiting fully closed M1 after retest"; return false; }
      if(!signal.confirmed)
      {
         double bodylow=MathMin(c.open,c.close),bodyhigh=MathMax(c.open,c.close);
         bool buy=c.low<=signal.level+area && c.close>=signal.level+InpMinM1CloseBeyondLevelPips*pip &&
                  c.close>c.open && bodylow-c.low>=InpMinRejectionWickPips*pip;
         bool sell=c.high>=signal.level-area && c.close<=signal.level-InpMinM1CloseBeyondLevelPips*pip &&
                   c.close<c.open && c.high-bodyhigh>=InpMinRejectionWickPips*pip;
         if(!(signal.direction==DIR_BUY?buy:sell)) { reason="M1 touched but rejection not confirmed"; return false; }
         signal.confirmed=true; signal.m1_confirmation=c.time+60;
         signal.m1_extreme=(signal.direction==DIR_BUY?c.low:c.high);
         signal.reason="Closed M1 rejection confirmed";
      }
      double entry=(signal.direction==DIR_BUY?tick.ask:tick.bid);
      if(MathAbs(entry-signal.level)>InpMaximumChaseDistancePips*pip)
      { reason="Maximum chase distance exceeded"; return false; }
      ZeroMemory(plan); plan.signal_id=signal.id; plan.direction=signal.direction;
      plan.mode=ENTRY_CONFIRMED; plan.pending=false; plan.created=now;
      plan.expiration=(datetime)MathMin((double)signal.expires_at,(double)(signal.confirmed_at+InpConfirmationExpirationMinutes*60));
      plan.entry=entry; plan.atr_pips=signal.atr_pips; return true;
   }
};
#endif
