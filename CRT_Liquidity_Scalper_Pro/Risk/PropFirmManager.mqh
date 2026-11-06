#ifndef CRT_PROP_FIRM_MANAGER_MQH
#define CRT_PROP_FIRM_MANAGER_MQH
#include "../Core/Config.mqh"

class CPropFirmManager
{
public:
   bool Valid(string &reason)
   {
      if(InpRiskCeilingPercent<=0 || InpRiskCeilingPercent>0.50 ||
         InpRiskPerTradePercent<=0 || InpRiskPerTradePercent>InpRiskCeilingPercent ||
         InpDailyLossLimitPercent<=0 || InpWeeklyLossLimitPercent<=0 ||
         InpTotalDrawdownLimitPercent<=0 || InpTotalDrawdownLimitPercent>=100 ||
         InpRiskResetHourServer<0 || InpRiskResetHourServer>23 ||
         InpMaximumConsecutiveLosses<1 || InpMaximumTradesPerDay<1 ||
         InpMaximumOwnPositions!=1 || InpMaximumOwnPendings!=1 ||
         InpRecoveryReferenceBalance<0 || InpCommissionPerLot<0 || InpSlippagePips<0)
      { reason="Invalid risk/prop-firm inputs"; return false; }
      return true;
   }
   double Base()
   { return InpRiskOnEquity ? AccountInfoDouble(ACCOUNT_EQUITY) : AccountInfoDouble(ACCOUNT_BALANCE); }
};
#endif
