#ifndef CRT_CORE_CONFIG_MQH
#define CRT_CORE_CONFIG_MQH
#include "Types.mqh"

input group "GENERAL"
input string InpSymbol="";
input ulong InpMagic=26011061;
input bool InpStartPaused=false;

input group "EXECUTION"
input int InpMaximumQuoteAgeSeconds=10;
input int InpDeviationPoints=10;
input bool InpCloseInvalidFill=true;

input group "CRT DETECTION"
input ENUM_TIMEFRAMES InpCRTTimeframe=PERIOD_M5;
input double InpMinSweepPips=0.2;
input double InpMinWickPips=0.3;
input bool InpRejectDoubleSidedSweep=true;
input int InpMaxSignalAgeMinutes=15;

input group "LIQUIDITY"
input ELiquidityMode InpLiquidityMode=CRT_PURE;
input int InpLiquidityLookbackBars=576;
input int InpPivotStrength=2;
input double InpEqualLevelTolerancePips=0.2;
input int InpEqualLevelMinimumTouches=2;

input group "ENTRY M1 - MODE"
input EEntryMode InpEntryMode=ENTRY_AGGRESSIVE;
input EEntryMode InpRealComparisonMode=ENTRY_AGGRESSIVE;

input group "ENTRY M1 - AGGRESSIVE"
input double InpEntryOffsetPips=0.1;
input int InpPendingExpirationMinutes=15;

input group "ENTRY M1 - CONFIRMED"
input double InpMinRejectionWickPips=0.2;
input double InpMinM1CloseBeyondLevelPips=0.1;
input double InpMaximumChaseDistancePips=1.0;
input double InpRetestAreaPips=0.1;
input int InpConfirmationExpirationMinutes=15;

input group "ATR"
input int InpATRPeriod=14;

input group "ATR & STOP"
input ESLMode InpSLMode=SL_M5_ATR;
input double InpATRMultiplier=0.45;
input double InpMinimumSLPips=0.7;
input double InpMaximumSLPips=3.0;
input double InpStructuralBufferPips=0.2;
input double InpFixedSLPips=1.5;

input group "DYNAMIC TP/RR"
input bool InpDynamicTPEnabled=true;
input double InpMinimumRR=3;
input double InpMaximumRR=9;
input double InpLiquidityTargetMarginPercent=10;
input bool InpAllowFallbackTarget=false;
input double InpFallbackFixedRR=3;
input double InpFixedRR=3;

input group "RISK - POSITION SIZE AND ESTIMATED COSTS"
input double InpRiskPerTradePercent=0.25;
input double InpRiskCeilingPercent=0.50;
input double InpCommissionPerLot=7.0;
input double InpSlippagePips=0.1;

input group "RISK"
input bool InpRiskOnEquity=true;
input double InpDailyLossLimitPercent=0.75;
input double InpWeeklyLossLimitPercent=2.0;
input int InpMaximumConsecutiveLosses=3;
input int InpMaximumTradesPerDay=3;
input int InpMaximumOwnPositions=1;
input int InpMaximumOwnPendings=1;

input group "SPREAD"
input double InpMaximumSpreadPips=0.3;

input group "VOLATILITY"
input double InpMinimumATRPips=0.2;
input double InpMaximumATRPips=20.0;

input group "PROP FIRM"
input ECRTDrawdownModel InpDrawdownModel=CRT_DD_FIXED_BALANCE;
input double InpTotalDrawdownLimitPercent=4.0;
input int InpRiskResetHourServer=0;
input double InpRecoveryReferenceBalance=0.0;
input bool InpCloseOwnPositionsOnRiskLock=false;

input group "HOURS"
input int InpBrokerUTCWinterHours=2;
input int InpBrokerUTCSummerHours=3;
input EBrokerDSTRule InpBrokerDSTRule=BROKER_DST_EU;
input bool InpLondonEnabled=true;
input bool InpNewYorkEnabled=true;
input bool InpOverlapOnly=false;
input int InpLondonOpenHour=8;
input int InpLondonCloseHour=17;
input int InpNewYorkOpenHour=8;
input int InpNewYorkCloseHour=17;
input int InpAsiaUTCOpenHour=0;
input int InpAsiaUTCCloseHour=8;

input group "NEWS"
input bool InpNewsFilterEnabled=true;
input int InpNewsMinutesBefore=15;
input int InpNewsMinutesAfter=15;
input bool InpBlockWhenCalendarUnavailable=true;
input int InpCalendarRefreshSeconds=30;

input group "POSITION MANAGEMENT"
input EManagementMode InpManagementMode=FIXED_ADAPTIVE_TP;
input double InpBreakEvenTriggerR=3.0;
input double InpBreakEvenBufferPips=0.1;
input bool InpPartialsEnabled=false;
input double InpPartialTriggerR=3.0;
input double InpPartialPercent=50.0;

input group "STRUCTURE TRAILING M1"
input int InpTrailingPivotStrength=2;
input int InpTrailingLookbackBars=40;
input double InpTrailingStartR=3.0;
input double InpTrailingBufferPips=0.1;
input double InpTrailingATRMultiplier=0.0;

input group "DASHBOARD"
input bool InpDashboardEnabled=true;
input int InpDashboardWidth=390;
input int InpDashboardFontSize=9;
input bool InpDashboardStartMinimized=false;

input group "CHART LEVELS"
input bool InpChartLevelsEnabled=true;
input bool InpChartKeepSignalHistory=false;
input int InpChartMaximumSignals=12;
input double InpChartRetestAreaPips=0.10;

input group "NOTIFICATIONS"
input bool InpNotifyTerminal=true;
input bool InpNotifyPush=false;
input bool InpNotifySound=false;
input string InpNotificationSound="alert.wav";
input int InpNotificationDedupeSeconds=60;

input group "BACKTEST / ANALYTICS"
input bool InpJournalEnabled=true;
input int InpStatisticsRefreshSeconds=5;
input int InpStatisticsLookbackDays=3650;
input bool InpVirtualComparisonEnabled=true;
input double InpVirtualSlippagePips=0.1;

string CRTSymbol() { return InpSymbol=="" ? _Symbol : InpSymbol; }
bool CRTCoreConfigValid(string &reason) {
 if(InpMagic==0) { reason="Magic must be nonzero"; return false; }
 if(InpRiskPerTradePercent<=0 || InpRiskCeilingPercent<=0 || InpRiskCeilingPercent>0.50 ||
    InpRiskPerTradePercent>InpRiskCeilingPercent || InpCommissionPerLot<0 || InpSlippagePips<0) {
    reason="Invalid risk ceiling or estimated costs"; return false;
 }
 if(!SymbolSelect(CRTSymbol(),true)) { reason="Symbol unavailable"; return false; }
 if(CRTSymbol()!=_Symbol) { reason="Attach EA to its execution symbol chart"; return false; }
 return true;
}
#endif
