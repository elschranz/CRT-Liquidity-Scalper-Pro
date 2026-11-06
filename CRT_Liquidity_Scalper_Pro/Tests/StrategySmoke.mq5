#property strict
#property script_show_inputs
#property description "Native CRT detector smoke tests. Run manually on a demo EURUSD chart."
#include "../Strategy/CRTDetector.mqh"
#include "../Strategy/DynamicTargets.mqh"

int passed=0,failed=0;
void Check(const bool condition,const string name)
  {
   if(condition) { passed++; Print("PASS: ",name); }
   else { failed++; Print("FAIL: ",name); }
  }
void OnStart()
  {
   const double pip=CRTPip(CRTSymbol());
   if(pip<=0) { Print("FAIL: symbol pip unavailable"); return; }
   CCRTDetector detector;
   MqlRates reference,bar; SSignal signal; string reason;
   ZeroMemory(reference); ZeroMemory(bar); ZeroMemory(signal);
   reference.time=D'2025.01.06 10:00';
   reference.low=1.10000; reference.high=reference.low+10*pip;
   reference.open=reference.low+4*pip; reference.close=reference.low+6*pip;
   bar.time=reference.time+300;
   bar.low=reference.low-2*pip; bar.high=reference.high-pip;
   bar.open=reference.low+pip; bar.close=reference.low+2*pip;
   bool detected=detector.Detect(reference,bar,signal,reason);
   Check(detected && signal.direction==DIR_BUY,"closed CRT BUY fixture");
   if(detected)
     {
      Check(MathAbs(signal.level-reference.low)<pip/100,"BUY swept reference low");
      Check(MathAbs(signal.extreme-bar.low)<pip/100,"BUY keeps manipulation low");
     }
   bar.low=reference.low+pip; bar.high=reference.high+2*pip;
   bar.open=reference.high-pip; bar.close=reference.high-2*pip;
   detected=detector.Detect(reference,bar,signal,reason);
   Check(detected && signal.direction==DIR_SELL,"closed CRT SELL fixture");
   if(detected)
      Check(MathAbs(signal.extreme-bar.high)<pip/100,"SELL keeps manipulation high");
   bar.low=reference.low-2*pip; bar.high=reference.high+2*pip;
   bar.open=reference.low+4*pip; bar.close=reference.low+5*pip;
   Check(!detector.Detect(reference,bar,signal,reason),"reject double-sided sweep");
   bar.high=reference.high-pip; bar.close=reference.high+pip;
   Check(!detector.Detect(reference,bar,signal,reason),"reject close outside reference range");
   bar.low=reference.low+pip; bar.high=reference.high-pip;
   bar.open=reference.low+3*pip; bar.close=reference.low+4*pip;
   Check(!detector.Detect(reference,bar,signal,reason),"reject no sweep");
   reference.high=reference.low;
   Check(!detector.Detect(reference,bar,signal,reason),"reject degenerate reference");
   CDynamicTargets targets;
   Check(targets.SelectRR(2.99)==0,"RR rejects under 3R");
   Check(targets.SelectRR(3.01)==3,"RR selects 3R");
   Check(targets.SelectRR(5.01)==5,"RR selects 5R");
   Check(targets.SelectRR(7.01)==7,"RR selects 7R");
   Check(targets.SelectRR(9.01)==9,"RR selects 9R");
   PrintFormat("CRT native smoke: %d passed; %d failed. Not an execution or profitability test.",
               passed,failed);
  }
