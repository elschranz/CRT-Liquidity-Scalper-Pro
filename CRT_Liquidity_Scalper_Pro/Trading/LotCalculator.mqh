#ifndef CRT_LOT_CALCULATOR_MQH
#define CRT_LOT_CALCULATOR_MQH
#include "../Core/Config.mqh"
#include "ExecutionValidator.mqh"
class CLotCalculator
{
public:
   bool Size(STradePlan &p,const double budget,string &reason)
   {
      string symbol=CRTSymbol();
      double step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP),minimum=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
      double maximum=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX),profit=0,slippage=0;
      if(budget<=0 || !MathIsValidNumber(budget) || step<=0 || minimum<=0 || maximum<minimum)
         {reason="Presupuesto/propiedades de volumen invalidos";return false;}
      ENUM_ORDER_TYPE type=(p.direction==DIR_BUY?ORDER_TYPE_BUY:ORDER_TYPE_SELL);
      // Use a broker-valid probe volume; results are in account currency.
      double probe=minimum;
      double pip=CRTPip(symbol),worse=p.sl-(double)p.direction*2.0*InpSlippagePips*pip;
      if(!OrderCalcProfit(type,symbol,probe,p.entry,p.sl,profit) || profit>=0 ||
         !OrderCalcProfit(type,symbol,probe,p.sl,worse,slippage))
         {reason="OrderCalcProfit no disponible";return false;}
      double loss_per_lot=(-profit+MathAbs(slippage))/probe+MathMax(0.0,InpCommissionPerLot);
      if(loss_per_lot<=0 || !MathIsValidNumber(loss_per_lot)){reason="Perdida monetaria desconocida";return false;}
      double volume=MathFloor(MathMin(maximum,budget/loss_per_lot)/step+1e-9)*step;
      // Never round upward to broker minimum.
      if(volume<minimum-1e-9){reason="Lote minimo excede riesgo permitido";return false;}
      double margin=0;
      if(!OrderCalcMargin(type,symbol,volume,p.entry,margin) || margin<=0 ||
         margin>AccountInfoDouble(ACCOUNT_MARGIN_FREE)){reason="Margen insuficiente";return false;}
      p.volume=NormalizeDouble(volume,8);p.risk_money=p.volume*loss_per_lot;
      if(p.risk_money>budget+0.000001){reason="Redondeo excede presupuesto";return false;}
      return true;
   }
};
#endif
