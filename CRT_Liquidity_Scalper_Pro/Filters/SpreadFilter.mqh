#ifndef CRT_SPREAD_FILTER_MQH
#define CRT_SPREAD_FILTER_MQH
#include "../Core/Config.mqh"
#include "../Core/Utilities.mqh"
class CSpreadFilter
{
public:
   bool Allowed(const MqlTick &tick,string &reason)
   {
      double pip=CRTPip(CRTSymbol());
      if(pip<=0 || tick.ask<=0 || tick.bid<=0 || tick.ask<tick.bid)
      { reason="Invalid bid/ask"; return false; }
      if(InpMaximumSpreadPips<=0 || (tick.ask-tick.bid)/pip>InpMaximumSpreadPips+1e-8)
      { reason="Spread above configured maximum"; return false; }
      return true;
   }
};
#endif
