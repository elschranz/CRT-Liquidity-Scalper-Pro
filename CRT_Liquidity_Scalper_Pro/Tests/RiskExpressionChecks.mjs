// Executes expressions extracted from the MQL sources under JavaScript.
// This is arithmetic/boundary verification; it is NOT MetaEditor compilation or MT5 execution.
export function runRiskExpressionChecks(readSource) {
 const dd=readSource("Risk/DrawdownManager.mqh");
 const news=readSource("Filters/NewsFilter.mqh");
 const percentExpression=dd.match(/double Percent[\s\S]*?return ([^;]+);/)[1].replaceAll("MathMax","Math.max");
 const remainingExpression=dd.match(/double Remaining[\s\S]*?return ([^;]+);/)[1];
 const percent=new Function("reference","adjusted_equity","return "+percentExpression);
 const remaining=new Function("reference","adjusted_equity","limit_percent","return "+remainingExpression);
 const result=[
  ["no drawdown",percent(10000,10000),0],
  ["daily .75% boundary",percent(10000,9925),.75],
  ["gain clamps DD",percent(10000,10100),0],
  ["missing reference fail closed",percent(0,1000),100],
  ["daily headroom at start",remaining(10000,10000,.75),75],
  ["daily headroom exhausted",remaining(10000,9925,.75),0],
  ["deposit neutral DD",percent(10000,11000-1000),0],
  ["withdrawal neutral DD",percent(10000,9000-(-1000)),0],
  ["total trailing headroom",remaining(11000,10900,4),340]
 ].map(([name,actual,expected])=>({name,actual,expected,pass:Math.abs(actual-expected)<1e-8}));
 const condition=news.match(/if\((server_time>=m_events\[i\][\s\S]*?)\)\n         \{/)[1];
 const gate=new Function("server_time","m_events","InpNewsMinutesBefore","InpNewsMinutesAfter","i","return "+condition);
 for(const [name,time,expected] of [
  ["news before boundary",999.999,false],
  ["news starts inclusive",1000,true],
  ["news release",1900,true],
  ["news ends inclusive",2800,true],
  ["news outside end",2801,false]
 ]) {
  const actual=gate(time,[1900],15,15,0);
  result.push({name,actual,expected,pass:actual===expected});
 }
 return result;
}
