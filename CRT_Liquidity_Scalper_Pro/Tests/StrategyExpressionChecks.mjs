// Translation harness for pure method bodies extracted from the delivered MQL.
// No market API, indicator handle, order API or MT5 event loop is executed here.
export function runStrategyExpressionChecks(readSource) {
 function body(source,signature) {
  const start=source.indexOf("{",source.indexOf(signature));
  let depth=1,index=start+1;
  while(depth && index<source.length){if(source[index]==="{")depth++;if(source[index]==="}")depth--;index++;}
  return source.slice(start+1,index-1);
 }
 const detector=body(readSource("Strategy/CRTDetector.mqh"),"bool Detect(")
   .replace(/\b(?:double|bool)\s+/g,"let ")
   .replace(/\(long\)/g,"")
   .replaceAll("MathIsValidNumber","Number.isFinite")
   .replaceAll("MathMin","Math.min").replaceAll("MathMax","Math.max");
 const detect=new Function("reference","manipulation","signal","InpMinSweepPips","InpMinWickPips",
 "InpRejectDoubleSidedSweep","InpMaxSignalAgeMinutes",
 "const InpCRTTimeframe=5,DIR_BUY=1,DIR_SELL=-1; let reason='';"+
 "const CRTPip=()=>.0001,CRTSymbol=()=>'EURUSD',PeriodSeconds=()=>300,IntegerToString=String;"+
 "const ZeroMemory=x=>Object.keys(x).forEach(k=>delete x[k]);"+detector);
 const ref={time:1000,open:1.1004,high:1.1010,low:1.1000,close:1.1006};
 const buy={time:1300,open:1.1003,high:1.1009,low:1.09996,close:1.1002};
 const sell={time:1300,open:1.1007,high:1.10104,low:1.1001,close:1.1008};
 const cases=[
  ["CRT buy",ref,buy,true,1],
  ["CRT sell",ref,sell,true,-1],
  ["double sweep",ref,{...buy,high:1.10104},false,0],
  ["close on boundary",ref,{...buy,close:1.1000},false,0],
  ["close outside range",ref,{...buy,high:1.1012,close:1.1011},false,0],
  ["insufficient sweep",ref,{...buy,low:1.09999},false,0],
  ["insufficient wick",ref,{...buy,open:1.09998,low:1.09997,close:1.10001},false,0],
  ["degenerate reference", {...ref,high:1.1000,open:1.1000,close:1.1000},buy,false,0],
  ["nonconsecutive bars",ref,{...buy,time:1600},false,0],
  ["nonfinite OHLC",ref,{...buy,low:NaN},false,0]
 ];
 const result=cases.map(([name,reference,manipulation,expected,direction])=>{
  const signal={},actual=detect(reference,manipulation,signal,.2,.3,true,15);
  const pass=actual===expected && (!expected || (signal.direction===direction && signal.confirmed_at===1600 && signal.expires_at===2500));
  return {name,actual,expected,direction:signal.direction||0,pass};
 });
 const rrBody=body(readSource("Strategy/DynamicTargets.mqh"),"double SelectRR(")
  .replace(/double ladder\[4\]=\{([^}]+)\};/,"const ladder=[$1];").replace("int i=0","let i=0");
 const select=new Function("available","InpMinimumRR","InpMaximumRR",rrBody);
 for(const [available,expected] of [[2.99,0],[3,3],[4.99,3],[5,5],[6.99,5],[7,7],[8.99,7],[9,9],[12,9]]) {
  const actual=select(available,3,9);
  result.push({name:"RR available "+available,actual,expected,pass:actual===expected});
 }
 return result;
}
