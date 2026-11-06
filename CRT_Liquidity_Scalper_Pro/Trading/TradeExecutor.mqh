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
      if(!CRTTradePositionOwned(ticket))return false;
      string id=IntegerToString(PositionGetInteger(POSITION_IDENTIFIER));
      // Durable queue precedes any close request. It survives partial fills and restarts.
      if(!CRTTradeSet("C."+id,1))
      {m_uncertain=true;Print("CRT safety: persistencia fallida; intervencion manual requerida");return false;}
      ProcessSafety();
      return !PositionSelectByTicket(ticket);
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
   bool Uncertain()
   {
      if(m_uncertain)return true;
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         ulong ticket=PositionGetTicket(i);
         if(!CRTTradePositionOwned(ticket))continue;
         string id=IntegerToString(PositionGetInteger(POSITION_IDENTIFIER));double queued=0;
         if(CRTTradeGet("C."+id,queued) && queued>0)return true;
      }
      return false;
   }
   void ProcessSafety()
   {
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         ulong ticket=PositionGetTicket(i);
         if(!CRTTradePositionOwned(ticket))continue;
         string id=IntegerToString(PositionGetInteger(POSITION_IDENTIFIER));
         double queued=0;if(!CRTTradeGet("C."+id,queued) || queued<=0)continue;
         double attempts=0,last=0,unknown=0,order_id=0,manual=0;
         CRTTradeGet("A."+id,attempts);CRTTradeGet("D."+id,last);
         CRTTradeGet("U."+id,unknown);CRTTradeGet("O."+id,order_id);
         CRTTradeGet("B."+id,manual);
         if(unknown>0)
         {
            // A known broker order must have a terminal history state before another close.
            // A timeout without an order identity remains blocked for manual reconciliation.
            bool resolved=false;
            if(order_id>0 && !OrderSelect((ulong)order_id) && HistoryOrderSelect((ulong)order_id))
            {
               ENUM_ORDER_STATE state=(ENUM_ORDER_STATE)HistoryOrderGetInteger((ulong)order_id,ORDER_STATE);
               resolved=(state==ORDER_STATE_FILLED || state==ORDER_STATE_CANCELED ||
                         state==ORDER_STATE_REJECTED || state==ORDER_STATE_EXPIRED);
            }
            if(!resolved)manual=1;
            else if(CRTTradeSet("U."+id,0))unknown=0;
         }
         if(!InpCloseInvalidFill || attempts>=3 || manual>0 || unknown>0)
         {
            double notified=0;
            if(!CRTTradeGet("N."+id,notified))
            {
               Print("CRT SAFETY: posicion ",ticket," sigue abierta; intentos=",attempts,
                     ", respuesta incierta=",unknown,". Intervencion manual requerida.");
               CRTTradeSet("N."+id,1);
            }
            continue;
         }
         if(!TerminalInfoInteger(TERMINAL_CONNECTED) || !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) ||
            !MQLInfoInteger(MQL_TRADE_ALLOWED) || TimeCurrent()-(datetime)last<1)continue;
         // Query this exact, still-owned ticket again immediately before sending.
         if(!CRTTradePositionOwned(ticket) || PositionGetDouble(POSITION_VOLUME)<=0)continue;
         if(!m_trade.SetTypeFillingBySymbol(CRTSymbol()))continue;
         if(!CRTTradeSet("A."+id,attempts+1) || !CRTTradeSet("D."+id,(double)TimeCurrent()) ||
            !CRTTradeSet("U."+id,1) || !CRTTradeSet("O."+id,0))
         {m_uncertain=true;continue;}
         bool sent=m_trade.PositionClose(ticket,InpDeviationPoints);
         uint code=m_trade.ResultRetcode();
         bool known=(sent && (code==TRADE_RETCODE_DONE || code==TRADE_RETCODE_DONE_PARTIAL) &&
                     (m_trade.ResultDeal()>0 || m_trade.ResultOrder()>0));
         if(known)
         {
            // DONE_PARTIAL is not completion: the durable queue drives the remaining close.
            CRTTradeSet("U."+id,0);
            Print("CRT safety close ",ticket,": ",m_trade.ResultRetcodeDescription(),
                  "; reconciliar volumen restante, maximo tres intentos.");
         }
         else
         {
            bool uncertain=(code==0 || code==TRADE_RETCODE_TIMEOUT || code==TRADE_RETCODE_CONNECTION ||
                            code==TRADE_RETCODE_ERROR || CRTTradeRetcodeAccepted(code));
            if(uncertain)
            {
               if(m_trade.ResultOrder()>0)CRTTradeSet("O."+id,(double)m_trade.ResultOrder());
            }
            else
            {
               CRTTradeSet("U."+id,0);
               bool transient=(code==TRADE_RETCODE_REQUOTE || code==TRADE_RETCODE_PRICE_CHANGED ||
                               code==TRADE_RETCODE_PRICE_OFF || code==TRADE_RETCODE_TOO_MANY_REQUESTS ||
                               code==TRADE_RETCODE_LOCKED);
               if(!transient)CRTTradeSet("B."+id,1);
            }
            Print("CRT safety close ",ticket,": ",m_trade.ResultRetcodeDescription());
         }
      }
   }
   uint LastRetcode(){return m_last_retcode;}
   bool LastPlan(STradePlan &p){if(!m_have_plan)return false;p=m_plan;return true;}
   bool Submit(const STradePlan &p,string &reason)
   {
      if(m_uncertain){reason="Solicitud anterior incierta; reconciliacion necesaria";return false;}
      CExecutionValidator validator;if(!validator.Validate(p,reason))return false;
      if(p.pending)m_trade.SetTypeFilling(ORDER_FILLING_RETURN);
      else if(!m_trade.SetTypeFillingBySymbol(CRTSymbol()))
         {reason="Modo filling del broker desconocido";return false;}
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
         bool buy=(submitted.direction==DIR_BUY);
         if((buy && sl<submitted.sl-SymbolInfoDouble(CRTSymbol(),SYMBOL_TRADE_TICK_SIZE)*0.1) ||
            (!buy && sl>submitted.sl+SymbolInfoDouble(CRTSymbol(),SYMBOL_TRADE_TICK_SIZE)*0.1))
         {reason="SL real ampliado frente a plan";valid=false;SafetyClose(ticket,reason);continue;}
         double checked_entry=0,checked_volume=0;
         if(CRTTradeGet("E."+id,checked_entry) && CRTTradeGet("Q."+id,checked_volume) &&
            MathAbs(checked_entry-actual)<SymbolInfoDouble(CRTSymbol(),SYMBOL_TRADE_TICK_SIZE)*0.1 &&
            MathAbs(checked_volume-volume)<SymbolInfoDouble(CRTSymbol(),SYMBOL_VOLUME_STEP)*0.1)continue;
         // Original SL survives later BE/trailing modifications. Only new fills update R.
         double original_risk=MathAbs(actual-submitted.sl);
         if(original_risk<=0 || !CRTTradeSet("R."+id,original_risk) || !CRTTradeSet("V."+id,volume))
         {reason="No se pudo guardar riesgo original";valid=false;SafetyClose(ticket,reason);continue;}
         STradePlan actual_plan=submitted;actual_plan.volume=volume;actual_plan.sl=submitted.sl;
         CDynamicTargets targets;
         if(!targets.Reprice(actual_plan,actual,reason))
         {valid=false;SafetyClose(ticket,reason);continue;}
         double profit=0,slippage=0;ENUM_ORDER_TYPE type=(actual_plan.direction==DIR_BUY?ORDER_TYPE_BUY:ORDER_TYPE_SELL);
         double worse=submitted.sl-(double)actual_plan.direction*2.0*InpSlippagePips*CRTPip(CRTSymbol());
         if(!OrderCalcProfit(type,CRTSymbol(),volume,actual,submitted.sl,profit) ||
            !OrderCalcProfit(type,CRTSymbol(),volume,submitted.sl,worse,slippage) ||
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
         if(!CRTTradeSet("E."+id,actual) || !CRTTradeSet("Q."+id,volume))
         {reason="No se pudo persistir validacion de fill";valid=false;SafetyClose(ticket,reason);}
      }
      return valid;
   }
};
#endif
