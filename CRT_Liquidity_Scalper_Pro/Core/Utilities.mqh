#ifndef CRT_CORE_UTILITIES_MQH
#define CRT_CORE_UTILITIES_MQH
#include "Config.mqh"
datetime CRTNow() {
 datetime current=TimeCurrent();
 if(MQLInfoInteger(MQL_TESTER)) return current;
 datetime server=TimeTradeServer();
 return server>0 ? server:current;
}
double CRTPip(const string symbol) {
 const int digits=(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
 const double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
 return point*((digits==3 || digits==5) ? 10.0 : 1.0);
}
double CRTPips(const string symbol,const double distance) {
 const double pip=CRTPip(symbol);
 return pip>0 ? distance/pip : 0;
}
double CRTPrice(const string symbol,const double price) {
 const double tick=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
 if(tick<=0) return 0;
 return NormalizeDouble(MathRound(price/tick)*tick,(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS));
}
bool CRTTick(const string symbol,MqlTick &tick) {
 return SymbolInfoTick(symbol,tick) && tick.bid>0 && tick.ask>=tick.bid && tick.time>0;
}
bool CRTOwnPosition(const string symbol,const ulong magic) {
 return PositionGetString(POSITION_SYMBOL)==symbol && (ulong)PositionGetInteger(POSITION_MAGIC)==magic;
}
uint CRTHash(const string value) {
 uint hash=2166136261;
 for(int i=0;i<StringLen(value);i++) { hash^=(uint)StringGetCharacter(value,i); hash*=16777619; }
 return hash;
}
string CRTKey(const string suffix) {
 static uint tester_nonce=0;
 if(MQLInfoInteger(MQL_TESTER) && tester_nonce==0) tester_nonce=(uint)(GetTickCount()^(uint)GetMicrosecondCount()^(uint)ChartID())+1;
 string context=IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+"|"+AccountInfoString(ACCOUNT_SERVER)+"|"+CRTSymbol()+"|"+IntegerToString((long)InpMagic);
 if(MQLInfoInteger(MQL_TESTER)) context+="|run="+IntegerToString((long)tester_nonce);
 string key="CRT"+IntegerToString((long)CRTHash(context))+"_"+IntegerToString((long)CRTHash(context+"|guard"))+"_";
 if(MQLInfoInteger(MQL_TESTER)) key+="T_";
 if(StringLen(key+suffix)>63) return key+"H"+IntegerToString((long)CRTHash(suffix));
 return key+suffix;
}
bool CRTSetGlobal(const string suffix,const double value) {
 return GlobalVariableSet(CRTKey(suffix),value)!=0;
}
double CRTGlobal(const string suffix,const double fallback=0) {
 const string key=CRTKey(suffix);
 if(!GlobalVariableCheck(key)) return fallback;
 return GlobalVariableGet(key);
}
string CRTDirection(const EDirection direction) { return direction==DIR_BUY ? "BUY" : "SELL"; }
string CRTMode(const EEntryMode mode) {
 if(mode==ENTRY_AGGRESSIVE) return "AGGRESSIVE";
 if(mode==ENTRY_CONFIRMED) return "CONFIRMED";
 return "BOTH_COMPARE";
}
#endif
