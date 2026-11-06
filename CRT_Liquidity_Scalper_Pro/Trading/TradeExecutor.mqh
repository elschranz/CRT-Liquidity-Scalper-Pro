#ifndef CRT_TRADE_EXECUTOR_MQH
#define CRT_TRADE_EXECUTOR_MQH
#include <Trade/Trade.mqh>
#include "ExecutionValidator.mqh"
#include "../Strategy/DynamicTargets.mqh"
class CTradeExecutor
{
private:
   CTrade m_trade;
   STradePlan m_plan;
   bool m_have_plan,m_uncertain;
   uint m_last_retcode;
   bool Mark(const int state)
   {
      return CRTTradeSet("intent.state",(double)state);
   }
   bool SafetyClose(const ulong ticket,const string reason)
   {
      Print("CRT fill safety: ",reason,". Un cierre puede perder dinero y no evita gaps.");
      if(!InpCloseInvalidFill)return false;
      if(!CRTTradePositionOwned(ticket))return false;
      bool requested=m_trade.PositionClose(ticket,InpDeviationPoints);
      if(!requested || !CRTTradeRetcodeAccepted(m_trade.ResultRetcode()))
      {Print("CRT safety close failed: ",m_trade.ResultRetcodeDescription());return false;}
      return true;
   }
public:
   CTradeExecutor(){m_have_plan=false;m_uncertain=false;m_last_retcode=0;}
   bool Init()
   {
      m_trade.SetExpertMagicNumber(InpMagic);m_trade.SetAsyncMode(false);
      m_trade.SetDeviationInPoints(InpDeviationPoints);m_trade.SetMarginMode();
      if(!m_trade.SetTypeFillingBySymbol(CRTSymbol()))return false;
      double state=0;bool present=CRTTradeGet("intent.state",state);
      m_have_plan=CRTTradeStateLoad(m_plan);
      if(present && state==1)m_uncertain=true;
      if(present && !m_have_plan)m_uncertain=true;
      Reconcile();return true;
   }
   bool Uncertain(){return m_uncertain;}
   uint LastRetcode(){return m_last_retcode;}
   bool LastPlan(STradePlan &p){if(!m_have_plan)return false;p=m_plan;return true;}
   bool Submit(const STradePlan &p,string &reason)
   {
      if(m_uncertain){reason="Solicitud anterior incierta; reconciliacion necesaria";return false;}
      CExecutionValidator validator;if(!validator.Validate(p,reason))return false;
      string attempted="S"+IntegerToString((long)CRTTradeHash(p.signal_id));
      if(GlobalVariableCheck(CRTTradeKey(attempted))){reason="Senal ya solicitada; no se reintenta";return false;}
      // Durable intent precedes the network request. Any crash in this interval fails closed.
      if(!Mark(1)){reason="No se pudo persistir intencion";m_uncertain=true;return false;}
      if(!CRTTradeStateSave(p) || !CRTTradeSet(attempted,1))
      {reason="No se pudo persistir plan/idempotencia";m_uncertain=true;return false;}
      m_plan=p;m_have_plan=true;m_uncertain=true;
      string comment=CRTTradeComment(p.signal_id);bool sent=false;
      if(p.pending)
      {
         if(p.direction==DIR_BUY)sent=m_trade.BuyLimit(p.volume,p.entry,CRTSymbol(),p.sl,p.tp,
                                                     ORDER_TIME_SPECIFIED,p.expiration,comment);
         else sent=m_trade.SellLimit(p.volume,p.entry,CRTSymbol(),p.sl,p.tp,
                                     ORDER_TIME_SPECIFIED,p.expiration,comment);
      }
      else
      {
         if(p.direction==DIR_BUY)sent=m_trade.Buy(p.volume,CRTSymbol(),0,p.sl,p.tp,comment);
         else sent=m_trade.Sell(p.volume,CRTSymbol(),0,p.sl,p.tp,comment);
      }
      m_last_retcode=m_trade.ResultRetcode();
      bool evidence=(m_trade.ResultOrder()>0 || m_trade.ResultDeal()>0);
      if(sent && CRTTradeRetcodeAccepted(m_last_retcode) && evidence)
      {
         if(!Mark(2)){reason="Aceptada, pero fallo persistencia: bloquear nuevas entradas";return false;}
         m_uncertain=false;reason=m_trade.ResultRetcodeDescription();return true;
      }
      reason="Solicitud: "+m_trade.ResultRetcodeDescription();
      bool unknown=(m_last_retcode==0 || m_last_retcode==TRADE_RETCODE_TIMEOUT ||
                    m_last_retcode==TRADE_RETCODE_CONNECTION || m_last_retcode==TRADE_RETCODE_ERROR ||
                    CRTTradeRetcodeAccepted(m_last_retcode));
      if(!unknown && Mark(3))m_uncertain=false;
      // No automatic resend, even on a definitive rejection; one attempt per signal.
      return false;
   }
   void Reconcile()
   {
      if(!m_have_plan)return;
      string comment=CRTTradeComment(m_plan.signal_id);bool evidence=false;
      for(int i=OrdersTotal()-1;i>=0;i--)
      {
         ulong order=OrderGetTicket(i);
         if(order>0 && OrderGetString(ORDER_SYMBOL)==CRTSymbol() &&
            OrderGetInteger(ORDER_MAGIC)==(long)InpMagic && OrderGetString(ORDER_COMMENT)==comment)evidence=true;
      }
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         ulong ticket=PositionGetTicket(i);
         if(CRTTradePositionOwned(ticket) && PositionGetString(POSITION_COMMENT)==comment)evidence=true;
      }
      if(!evidence && HistorySelect(m_plan.created-60,TimeCurrent()+1))
      {
         int n=HistoryDealsTotal();
         for(int i=0;i<n;i++)
         {
            ulong deal=HistoryDealGetTicket(i);
            if(HistoryDealGetString(deal,DEAL_SYMBOL)==CRTSymbol() &&
               HistoryDealGetInteger(deal,DEAL_MAGIC)==(long)InpMagic &&
               HistoryDealGetString(deal,DEAL_COMMENT)==comment){evidence=true;break;}
         }
         int orders=HistoryOrdersTotal();
         for(int i=0;i<orders && !evidence;i++)
         {
            ulong order=HistoryOrderGetTicket(i);
            if(HistoryOrderGetString(order,ORDER_SYMBOL)==CRTSymbol() &&
               HistoryOrderGetInteger(order,ORDER_MAGIC)==(long)InpMagic &&
               HistoryOrderGetString(order,ORDER_COMMENT)==comment)evidence=true;
         }
      }
      if(evidence && Mark(2))m_uncertain=false;
   }
   bool RevalidateFill(const STradePlan &submitted,string &reason)
   {
      bool valid=true;
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         ulong ticket=PositionGetTicket(i);
         if(!CRTTradePositionOwned(ticket))continue;
         string comment=PositionGetString(POSITION_COMMENT);
         if(comment!=CRTTradeComment(submitted.signal_id))continue;
         double actual=PositionGetDouble(POSITION_PRICE_OPEN),sl=PositionGetDouble(POSITION_SL);
         double volume=PositionGetDouble(POSITION_VOLUME),tp=PositionGetDouble(POSITION_TP);
         long identifier=PositionGetInteger(POSITION_IDENTIFIER);
         string id=IntegerToString(identifier);
         if(sl<=0){reason="Fill sin SL";valid=false;SafetyClose(ticket,reason);continue;}
         // Persist immutable initial risk for management; never derive R from a trailed SL.
         double original_risk=0;
         if(!CRTTradeGet("R."+id,original_risk))
         {
            if(!CRTTradeSet("R."+id,MathAbs(actual-sl)) || !CRTTradeSet("V."+id,volume))
            {reason="No se pudo guardar riesgo original";valid=false;SafetyClose(ticket,reason);continue;}
         }
         STradePlan actual_plan=submitted;actual_plan.volume=volume;actual_plan.sl=sl;
         CDynamicTargets targets;
         if(!targets.Reprice(actual_plan,actual,reason))
         {valid=false;SafetyClose(ticket,reason);continue;}
         double profit=0,slippage=0;ENUM_ORDER_TYPE type=(actual_plan.direction==DIR_BUY?ORDER_TYPE_BUY:ORDER_TYPE_SELL);
         double worse=sl-(double)actual_plan.direction*2.0*InpSlippagePips*CRTPip(CRTSymbol());
         if(!OrderCalcProfit(type,CRTSymbol(),volume,actual,sl,profit) ||
            !OrderCalcProfit(type,CRTSymbol(),volume,sl,worse,slippage) ||
            -profit+MathAbs(slippage)+volume*InpCommissionPerLot>submitted.risk_money+0.01)
         {reason="Fill excede presupuesto monetario";valid=false;SafetyClose(ticket,reason);continue;}
         MqlTick tick;SymbolInfoTick(CRTSymbol(),tick);
         if(!CRTTradeStopValid(actual_plan.direction==DIR_BUY,sl,actual_plan.tp,tick))
         {reason="TP recalculado no cabe en stops/freeze";valid=false;SafetyClose(ticket,reason);continue;}
         if(MathAbs(tp-actual_plan.tp)>SymbolInfoDouble(CRTSymbol(),SYMBOL_TRADE_TICK_SIZE)*0.5)
         {
            bool modified=m_trade.PositionModify(ticket,sl,actual_plan.tp);
            if(!modified || !CRTTradeRetcodeAccepted(m_trade.ResultRetcode()))
            {reason="No se pudo ajustar TP tras fill";valid=false;SafetyClose(ticket,reason);continue;}
         }
      }
      return valid;
   }
};
#endif
