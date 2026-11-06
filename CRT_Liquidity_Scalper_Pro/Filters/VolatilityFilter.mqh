#ifndef CRT_VOLATILITY_FILTER_MQH
#define CRT_VOLATILITY_FILTER_MQH
input group "VOLATILITY"
input double InpMinimumATRPips=0.2;
input double InpMaximumATRPips=20.0;
class CVolatilityFilter
{
public:
   bool Allowed(const double atr_pips,string &reason)
   {
      if(!MathIsValidNumber(atr_pips) || atr_pips<=0 ||
         InpMinimumATRPips<0 || InpMaximumATRPips<InpMinimumATRPips ||
         atr_pips<InpMinimumATRPips || atr_pips>InpMaximumATRPips)
      { reason="ATR unavailable or outside configured range"; return false; }
      return true;
   }
};
#endif
