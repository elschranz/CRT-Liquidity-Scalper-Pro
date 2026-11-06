#ifndef CRT_PROP_FIRM_MANAGER_MQH
#define CRT_PROP_FIRM_MANAGER_MQH
#include "../Core/Config.mqh"
enum ECRTDrawdownModel { CRT_DD_FIXED_BALANCE=0, CRT_DD_TRAILING_BALANCE=1, CRT_DD_FIXED_EQUITY=2, CRT_DD_HIGH_WATER_EQUITY=3 };
input group "RISK"
input bool InpRiskOnEquity=true;
input double InpDailyLossLimitPercent=0.75;
input double InpWeeklyLossLimitPercent=2.0;
input int InpMaximumConsecutiveLosses=3;
input int InpMaximumTradesPerDay=3;
input int InpMaximumOwnPositions=1;
input int InpMaximumOwnPendings=1;
input group "PROP FIRM"
input ECRTDrawdownModel InpDrawdownModel=CRT_DD_FIXED_BALANCE;
input double InpTotalDrawdownLimitPercent=4.0;
input int InpRiskResetHourServer=0;
input double InpRecoveryReferenceBalance=0.0;
input bool InpCloseOwnPositionsOnRiskLock=false;
input bool InpAllowGlobalProtection=false;
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
         InpMaximumOwnPositions<1 || InpMaximumOwnPendings<1 ||
         InpRecoveryReferenceBalance<0 || InpCommissionPerLot<0 || InpSlippagePips<0)
      { reason="Invalid risk/prop-firm inputs"; return false; }
      return true;
   }
   double Base()
   { return InpRiskOnEquity ? AccountInfoDouble(ACCOUNT_EQUITY) : AccountInfoDouble(ACCOUNT_BALANCE); }
};
#endif
