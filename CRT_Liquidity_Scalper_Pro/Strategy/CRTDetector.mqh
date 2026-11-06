#ifndef CRT_DETECTOR_MQH
#define CRT_DETECTOR_MQH
#include "../Core/Utilities.mqh"
input group "CRT DETECTION"
input ENUM_TIMEFRAMES InpCRTTimeframe=PERIOD_M5;
input double InpMinSweepPips=0.2;
input double InpMinWickPips=0.3;
input bool InpRejectDoubleSidedSweep=true;
input int InpMaxSignalAgeMinutes=15;
class CCRTDetector
{
private:
   datetime m_last;
public:
   CCRTDetector():m_last(0) {}
   bool Valid() const
   {
      return InpCRTTimeframe==PERIOD_M5 && InpMinSweepPips>=0 && InpMinWickPips>=0 && InpMaxSignalAgeMinutes>0;
   }
   bool Detect(const MqlRates &reference,const MqlRates &manipulation,SSignal &signal,string &reason) const
   {
      reason="";
      if(reference.high<=reference.low || manipulation.high<=manipulation.low ||
         reference.open<reference.low || reference.open>reference.high || reference.close<reference.low || reference.close>reference.high ||
         manipulation.open<manipulation.low || manipulation.open>manipulation.high || manipulation.close<manipulation.low || manipulation.close>manipulation.high)
      { reason="Degenerate M5 data"; return false; }
      double pip=CRTPip(CRTSymbol()),sweep=InpMinSweepPips*pip,wick=InpMinWickPips*pip;
      bool below=manipulation.low<reference.low,above=manipulation.high>reference.high;
      if(InpRejectDoubleSidedSweep && below && above) { reason="Double-sided sweep"; return false; }
      bool inside=manipulation.close>reference.low && manipulation.close<reference.high;
      bool buy=inside && manipulation.low<reference.low-sweep && !above &&
               MathMin(manipulation.open,manipulation.close)-manipulation.low>=wick;
      bool sell=inside && manipulation.high>reference.high+sweep && !below &&
                manipulation.high-MathMax(manipulation.open,manipulation.close)>=wick;
      if(!buy && !sell) return false;
      ZeroMemory(signal);
      signal.direction=(buy?DIR_BUY:DIR_SELL);
      signal.reference_time=manipulation.time;
      signal.confirmed_at=manipulation.time+PeriodSeconds(InpCRTTimeframe);
      signal.expires_at=signal.confirmed_at+InpMaxSignalAgeMinutes*60;
      signal.id=IntegerToString((long)signal.confirmed_at)+(buy?"B":"S");
      signal.level=buy?reference.low:reference.high;
      signal.extreme=buy?manipulation.low:manipulation.high;
      signal.range_high=reference.high; signal.range_low=reference.low;
      signal.active=true; signal.reason="Closed M5 CRT";
      return true;
   }
   bool Poll(SSignal &signal,string &reason)
   {
      reason="";
      MqlRates r[]; ArraySetAsSeries(r,true);
      if(CopyRates(CRTSymbol(),InpCRTTimeframe,0,3,r)!=3) { reason="M5 history unavailable"; return false; }
      if(r[1].time<=0 || r[1].time==m_last) return false;
      // A terminal restart must never replay a previously processed signal.
      string key=CRTKey("lastCRT");
      if(GlobalVariableCheck(key) && (datetime)GlobalVariableGet(key)>=r[1].time) { m_last=r[1].time; return false; }
      m_last=r[1].time; GlobalVariableSet(key,(double)m_last); GlobalVariablesFlush();
      if(r[0].time<r[1].time+PeriodSeconds(InpCRTTimeframe)) { reason="Incomplete M5 close"; return false; }
      if(!Detect(r[2],r[1],signal,reason)) return false;
      if(TimeCurrent()>=signal.expires_at) { signal.active=false; reason="CRT already expired"; return false; }
      return true;
   }
};
#endif
