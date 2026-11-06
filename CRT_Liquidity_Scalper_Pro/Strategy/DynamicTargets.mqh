#ifndef CRT_DYNAMIC_TARGETS_MQH
#define CRT_DYNAMIC_TARGETS_MQH
#include "LiquidityDetector.mqh"
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
class CDynamicTargets
{
private:
   double TickPrice(const double price,const bool up) const
   {
      double step=SymbolInfoDouble(CRTSymbol(),SYMBOL_TRADE_TICK_SIZE);
      if(step<=0) return 0;
      int digits=(int)SymbolInfoInteger(CRTSymbol(),SYMBOL_DIGITS);
      return NormalizeDouble((up?MathCeil(price/step-1e-8):MathFloor(price/step+1e-8))*step,digits);
   }
   bool CostCheck(const STradePlan &plan,string &reason) const
   {
      ENUM_ORDER_TYPE side=plan.direction==DIR_BUY?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
      double loss=0,profit=0,slip=0;
      double adverse=plan.entry-(int)plan.direction*2*InpSlippagePips*CRTPip(CRTSymbol());
      if(!OrderCalcProfit(side,CRTSymbol(),1,plan.entry,plan.sl,loss) ||
         !OrderCalcProfit(side,CRTSymbol(),1,plan.entry,plan.tp,profit) ||
         !OrderCalcProfit(side,CRTSymbol(),1,plan.entry,adverse,slip))
      { reason="OrderCalcProfit unavailable for cost validation"; return false; }
      double cost=MathMax(0,InpCommissionPerLot)+MathAbs(slip);
      double risk=MathAbs(loss)+cost,reward=profit-cost;
      if(risk<=0 || reward<=0 || reward/risk+1e-8<InpMinimumRR)
      { reason="Net RR after estimated commission/slippage below minimum"; return false; }
      return true;
   }
   bool Target(STradePlan &plan,string &reason) const
   {
      double risk=(int)plan.direction*(plan.entry-plan.sl),pip=CRTPip(CRTSymbol());
      if(risk<=0 || risk/pip>InpMaximumSLPips+1e-7 || risk/pip<InpMinimumSLPips-1e-7)
      { reason="Actual stop distance outside configured range"; return false; }
      double rr=0,available=0;
      if(InpDynamicTPEnabled && plan.target_level>0)
      {
         double distance=(int)plan.direction*(plan.target_level-plan.entry);
         available=distance*(1-InpLiquidityTargetMarginPercent/100.0)/risk;
         rr=SelectRR(available);
      }
      else
      {
         rr=InpDynamicTPEnabled?InpFallbackFixedRR:InpFixedRR;
         if(rr<InpMinimumRR || rr>InpMaximumRR) rr=0;
      }
      if(rr<=0) { reason="Nearest preexisting target offers insufficient RR"; return false; }
      plan.rr=rr;
      // Round TP towards entry: no accidental crossing of reserved target margin.
      plan.tp=TickPrice(plan.entry+(int)plan.direction*risk*rr,plan.direction==DIR_SELL);
      double actualRR=(int)plan.direction*(plan.tp-plan.entry)/risk;
      if(actualRR+1e-7<InpMinimumRR || (available>0 && actualRR>available+1e-7))
      { reason="Tick size invalidates target RR"; return false; }
      plan.rr=actualRR;
      return CostCheck(plan,reason);
   }
public:
   bool Valid() const
   {
      return InpATRMultiplier>=0 && InpMinimumSLPips>0 && InpMaximumSLPips>=InpMinimumSLPips &&
             InpStructuralBufferPips>=0 && InpFixedSLPips>0 && InpMinimumRR>=3 &&
             InpMaximumRR>=InpMinimumRR && InpMaximumRR<=9 &&
             InpLiquidityTargetMarginPercent>=0 && InpLiquidityTargetMarginPercent<100 &&
             InpFallbackFixedRR>=InpMinimumRR && InpFallbackFixedRR<=InpMaximumRR &&
             InpFixedRR>=InpMinimumRR && InpFixedRR<=InpMaximumRR;
   }
   double SelectRR(const double available) const
   {
      double ladder[4]={9,7,5,3};
      for(int i=0;i<4;i++)
         if(ladder[i]>=InpMinimumRR && ladder[i]<=InpMaximumRR && ladder[i]<=available+1e-9) return ladder[i];
      return 0;
   }
   bool Build(const SSignal &signal,STradePlan &plan,CLiquidityDetector &liquidity,string &reason)
   {
      reason="";
      double pip=CRTPip(CRTSymbol()),extreme=signal.extreme;
      if(pip<=0 || plan.entry<=0 || signal.atr_pips<=0) { reason="Stop input data unavailable"; return false; }
      if(InpSLMode==SL_M1_ATR)
      {
         if(!signal.confirmed || signal.m1_extreme<=0)
         { reason="Experimental M1 stop requires closed M1 confirmation"; return false; }
         extreme=signal.m1_extreme;
      }
      double structural=extreme-(int)plan.direction*InpStructuralBufferPips*pip;
      double structuralDistance=(int)plan.direction*(plan.entry-structural);
      if(structuralDistance<=0) { reason="Entry already beyond invalidation level"; return false; }
      double distance=MathMax(structuralDistance,MathMax(signal.atr_pips*InpATRMultiplier*pip,InpMinimumSLPips*pip));
      if(InpSLMode==SL_FIXED)
      {
         distance=InpFixedSLPips*pip;
         // Comparison stop may never cut inside the M5 structural invalidation.
         if(distance+1e-9<structuralDistance) { reason="Fixed stop would cut M5 structure"; return false; }
      }
      if(distance/pip>InpMaximumSLPips+1e-7) { reason="Required structural/ATR stop exceeds maximum"; return false; }
      plan.sl=TickPrice(plan.entry-(int)plan.direction*distance,plan.direction==DIR_SELL);
      if((plan.direction==DIR_BUY && plan.sl>structural) || (plan.direction==DIR_SELL && plan.sl<structural))
      { reason="Rounded stop violates structure"; return false; }
      plan.target_level=0;
      if(InpDynamicTPEnabled && !liquidity.NextTarget(signal,plan.entry,plan.target_level) && !InpAllowFallbackTarget)
      { reason="No valid preexisting target; fallback disabled"; return false; }
      return Target(plan,reason);
   }
   bool Reprice(STradePlan &plan,const double actualEntry,string &reason) const
   {
      if(actualEntry<=0) { reason="Actual fill unavailable"; return false; }
      // An already-open SL is immutable here: only TP/RR are recalculated.
      plan.entry=actualEntry;
      if(InpDynamicTPEnabled && plan.target_level<=0 && !InpAllowFallbackTarget)
      { reason="Reprice has no permitted target"; return false; }
      return Target(plan,reason);
   }
};
#endif
