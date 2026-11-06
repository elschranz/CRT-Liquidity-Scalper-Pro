#ifndef CRT_TRAILING_MANAGER_MQH
#define CRT_TRAILING_MANAGER_MQH
#include "../Trading/ExecutionValidator.mqh"
input group "STRUCTURE TRAILING M1"
input int InpTrailingPivotStrength=2;
input int InpTrailingLookbackBars=40;
input double InpTrailingStartR=3.0;
input double InpTrailingBufferPips=0.1;
input double InpTrailingATRMultiplier=0.0;
class CTrailingManager
{
public:
   bool Propose(const ulong ticket,const double initial_risk,const double atr_pips,double &new_sl,string &reason)
   {
      if(!CRTTradePositionOwned(ticket) || initial_risk<=0)return false;
      bool buy=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
      double entry=PositionGetDouble(POSITION_PRICE_OPEN),old_sl=PositionGetDouble(POSITION_SL);
      MqlTick tick;if(!SymbolInfoTick(CRTSymbol(),tick))return false;
      double move=buy?tick.bid-entry:entry-tick.ask;
      if(move<initial_risk*InpTrailingStartR)return false;
      int strength=InpTrailingPivotStrength;
      if(strength<1 || InpTrailingLookbackBars<strength*2+1)return false;
      MqlRates bars[];ArraySetAsSeries(bars,true);
      int copied=CopyRates(CRTSymbol(),PERIOD_M1,1,InpTrailingLookbackBars,bars);
      if(copied<strength*2+1)return false;
      datetime opened=(datetime)PositionGetInteger(POSITION_TIME);
      double buffer=MathMax(InpTrailingBufferPips,MathMax(0.0,atr_pips)*InpTrailingATRMultiplier)*CRTPip(CRTSymbol());
      double grid=SymbolInfoDouble(CRTSymbol(),SYMBOL_TRADE_TICK_SIZE);if(grid<=0)return false;
      for(int i=strength;i<copied-strength;i++)
      {
         if(bars[i].time<opened)continue;
         bool pivot=true;
         for(int j=1;j<=strength;j++)
         {
            if(buy && (bars[i].low>=bars[i-j].low || bars[i].low>=bars[i+j].low))pivot=false;
            if(!buy && (bars[i].high<=bars[i-j].high || bars[i].high<=bars[i+j].high))pivot=false;
         }
         if(!pivot)continue;
         double wanted=buy?bars[i].low-buffer:bars[i].high+buffer;
         // Outward rounding preserves structural buffer; old SL is never loosened.
         new_sl=NormalizeDouble((buy?MathFloor(wanted/grid):MathCeil(wanted/grid))*grid,
                               (int)SymbolInfoInteger(CRTSymbol(),SYMBOL_DIGITS));
         if((buy && old_sl>0 && new_sl<=old_sl) || (!buy && old_sl>0 && new_sl>=old_sl))continue;
         if(!CRTTradeStopValid(buy,new_sl,PositionGetDouble(POSITION_TP),tick))continue;
         return true;
      }
      reason="Sin pivote M1 cerrado/confirmado valido";return false;
   }
};
#endif
