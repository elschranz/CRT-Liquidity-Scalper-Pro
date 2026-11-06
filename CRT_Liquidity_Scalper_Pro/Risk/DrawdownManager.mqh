#ifndef CRT_DRAWDOWN_MANAGER_MQH
#define CRT_DRAWDOWN_MANAGER_MQH
#include "PropFirmManager.mqh"
class CDrawdownManager
{
public:
   double Percent(const double reference,const double adjusted_equity)
   { return reference>0 ? MathMax(0.0,(reference-adjusted_equity)*100.0/reference) : 100.0; }
   double Remaining(const double reference,const double adjusted_equity,const double limit_percent)
   { return adjusted_equity-reference*(1.0-limit_percent/100.0); }
   bool Trailing()
   { return InpDrawdownModel==CRT_DD_TRAILING_BALANCE || InpDrawdownModel==CRT_DD_HIGH_WATER_EQUITY; }
   double ReferenceValue()
   {
      return (InpDrawdownModel==CRT_DD_FIXED_EQUITY || InpDrawdownModel==CRT_DD_HIGH_WATER_EQUITY)
         ? AccountInfoDouble(ACCOUNT_EQUITY) : AccountInfoDouble(ACCOUNT_BALANCE);
   }
};
#endif
