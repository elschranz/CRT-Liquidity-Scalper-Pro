#ifndef CRT_BREAK_EVEN_MANAGER_MQH
#define CRT_BREAK_EVEN_MANAGER_MQH
#include "../Trading/ExecutionValidator.mqh"
input group "POSITION MANAGEMENT"
input EManagementMode InpManagementMode=FIXED_ADAPTIVE_TP;
input double InpBreakEvenTriggerR=3.0;
input double InpBreakEvenBufferPips=0.1;
input bool InpPartialsEnabled=false;
input double InpPartialTriggerR=3.0;
input double InpPartialPercent=50.0;
class CBreakEvenManager
{
public:
   bool Propose(const ulong ticket,const double initial_risk,const bool manual,double &new_sl,string &reason)
   {
      if(!CRTTradePositionOwned(ticket) || initial_risk<=0){reason="R inicial no disponible";return false;}
      bool buy=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
      double entry=PositionGetDouble(POSITION_PRICE_OPEN),old_sl=PositionGetDouble(POSITION_SL);
      MqlTick tick;if(!SymbolInfoTick(CRTSymbol(),tick))return false;
      double mark=buy?tick.bid:tick.ask;
      double favorable=buy?mark-entry:entry-mark;
      if(!manual && favorable<InpBreakEvenTriggerR*initial_risk)return false;
      double probe=SymbolInfoDouble(CRTSymbol(),SYMBOL_VOLUME_MIN),onepip=0;
      double pip=CRTPip(CRTSymbol());
      ENUM_ORDER_TYPE type=buy?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
      if(probe<=0 || !OrderCalcProfit(type,CRTSymbol(),probe,entry,entry+(buy?pip:-pip),onepip) || onepip<=0)
         {reason="No se pueden calcular costes de BE";return false;}
      double cost_pips=(MathMax(0.0,InpCommissionPerLot)*probe/onepip)+2.0*MathMax(0.0,InpSlippagePips);
      double wanted=entry+(buy?1.0:-1.0)*(cost_pips+MathMax(0.0,InpBreakEvenBufferPips))*pip;
      double grid=SymbolInfoDouble(CRTSymbol(),SYMBOL_TRADE_TICK_SIZE);
      if(grid<=0)return false;
      // Round toward profit to retain the cost buffer.
      new_sl=NormalizeDouble((buy?MathCeil(wanted/grid):MathFloor(wanted/grid))*grid,
                            (int)SymbolInfoInteger(CRTSymbol(),SYMBOL_DIGITS));
      if((buy && old_sl>0 && new_sl<=old_sl) || (!buy && old_sl>0 && new_sl>=old_sl))
         {reason="BE no mejora SL";return false;}
      if(!CRTTradeStopValid(buy,new_sl,PositionGetDouble(POSITION_TP),tick))
         {reason="BE aun no valido por Bid/Ask/stops/freeze";return false;}
      return true;
   }
};
#endif
