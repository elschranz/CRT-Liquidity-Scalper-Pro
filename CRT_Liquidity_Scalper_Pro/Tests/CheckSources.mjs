// Run: node CRT_Liquidity_Scalper_Pro/Tests/CheckSources.mjs
// These checks inspect source structure and translated arithmetic, not MQL compilation.
import fs from "node:fs";
import path from "node:path";
import {fileURLToPath} from "node:url";
import {runRiskExpressionChecks} from "./RiskExpressionChecks.mjs";
import {runStrategyExpressionChecks} from "./StrategyExpressionChecks.mjs";

export function checkSources(files) {
 const findings=[], graph={}, inputs=new Map(), types=new Map();
 const normalize=p=>p.split("/").reduce((a,x)=>{if(x==="..")a.pop();else if(x && x!==".")a.push(x);return a;},[]).join("/");
 function clean(source,name) {
  let result="",state="code",quote="",stack=[];
  for(let i=0;i<source.length;i++) {
   const c=source[i],n=source[i+1];
   if(state==="line") { if(c==="\n"){state="code";result+="\n";}else result+=" ";continue; }
   if(state==="block") {if(c==="*" && n==="/"){state="code";result+="  ";i++;}else result+=c==="\n"?"\n":" ";continue;}
   if(state==="string") {if(c==="\\"){result+="  ";i++;continue;}if(c===quote)state="code";result+=c==="\n"?"\n":" ";continue;}
   if(c==="/" && n==="/"){state="line";result+="  ";i++;continue;}
   if(c==="/" && n==="*"){state="block";result+="  ";i++;continue;}
   if(c==='"' || c==="'"){state="string";quote=c;result+=" ";continue;}
   result+=c;
  }
  if(state==="string" || state==="block")findings.push(name+": unterminated "+state);
  for(const c of result) {
   if("([{".includes(c))stack.push(c);
   else if(")]}".includes(c)) {const x=stack.pop();if(x!=="([{"[")]}".indexOf(c)])findings.push(name+": mismatched delimiter");}
  }
  if(stack.length)findings.push(name+": unclosed delimiter");
  return result;
 }
 const sources=Object.entries(files).filter(([name])=>/\.mq[5h]$/.test(name));
 for(const [name,source] of sources) {
  const code=clean(source,name);
  if(name.endsWith(".mqh")) {
   const a=source.match(/#ifndef\s+(\w+)/),b=source.match(/#define\s+(\w+)/);
   if(!a || !b || a[1]!==b[1] || !/#endif\s*$/.test(source))findings.push(name+": bad include guard");
  }
  graph[name]=[];
  for(const m of source.matchAll(/#include\s+"([^"]+)"/g)) {
   const dependency=normalize(name.slice(0,name.lastIndexOf("/")+1)+m[1]);
   if(!(dependency in files))findings.push(name+": missing "+dependency);
   else graph[name].push(dependency);
  }
  for(const m of code.matchAll(/\binput\s+(?!group\b)\w+\s+(Inp\w+)/g)) {
   if(inputs.has(m[1]))findings.push("duplicate input "+m[1]);
   inputs.set(m[1],name);
  }
  for(const m of code.matchAll(/\b(?:class|struct|enum)\s+(\w+)\s*[{\n]/g)) {
   if(types.has(m[1]))findings.push("duplicate type "+m[1]);
   types.set(m[1],name);
  }
  if(/\b(?:TODO|FIXME)\b/.test(code))findings.push(name+": unfinished marker");
 }
 const visited=new Set(),visiting=new Set();
 function visit(name) {
  if(visiting.has(name)){findings.push("include cycle at "+name);return;}
  if(visited.has(name))return;
  visiting.add(name);for(const dep of graph[name]||[])visit(dep);visiting.delete(name);visited.add(name);
 }
 Object.keys(graph).forEach(visit);
 for(const [name,source] of sources)
  for(const m of clean(source,name).matchAll(/\bInp\w+\b/g))
   if(!inputs.has(m[0]))findings.push(name+": unknown input "+m[0]);
 return {sources:sources.length,inputs:inputs.size,types:types.size,findings:[...new Set(findings)],pass:findings.length===0};
}

if(process.argv[1] && path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
 const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),".."),files={};
 function walk(dir) {
  for(const entry of fs.readdirSync(dir,{withFileTypes:true})) {
   const full=path.join(dir,entry.name);
   if(entry.isDirectory())walk(full);
   else files[path.relative(root,full).split(path.sep).join("/")]=fs.readFileSync(full,"utf8");
  }
 }
 walk(root);
 const structure=checkSources(files),risk=runRiskExpressionChecks(p=>files[p]),strategy=runStrategyExpressionChecks(p=>files[p]);
 console.log(JSON.stringify({structure,risk,strategy},null,2));
 process.exitCode=structure.pass && risk.every(x=>x.pass) && strategy.every(x=>x.pass)?0:1;
}
