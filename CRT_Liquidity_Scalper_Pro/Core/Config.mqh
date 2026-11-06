#ifndef CRT_CORE_CONFIG_MQH
#define CRT_CORE_CONFIG_MQH
#include "Types.mqh"
input group "GENERAL"
input string InpSymbol="";
input ulong InpMagic=26011061;
input bool InpStartPaused=false;
input group "RISK - POSITION SIZE AND ESTIMATED COSTS"
input double InpRiskPerTradePercent=0.25;
input double InpRiskCeilingPercent=0.50;
input double InpCommissionPerLot=7.0;
input double InpSlippagePips=0.1;
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
