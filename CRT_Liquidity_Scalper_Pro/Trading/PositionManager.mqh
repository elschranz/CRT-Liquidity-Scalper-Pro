#ifndef CRT_POSITION_MANAGER_MQH
#define CRT_POSITION_MANAGER_MQH
#include <Trade/Trade.mqh>
#include "ExecutionValidator.mqh"
#include "../Management/BreakEvenManager.mqh"
#include "../Management/TrailingManager.mqh"
class CPositionManager
{
private:
   CTrade m_trade;
   CBreakEvenManager m_be;
   CTrailingManager m_trail;
   datetime m_last_trail_bar;
   bool Modify(const ulong ticket,const double new_sl,string &reason)
   {
      if(!CRTTradePositionOwned(ticket))return false;
      double old_sl=PositionGetDouble(POSITION_SL),tp=PositionGetDouble(POSITION_TP);
      bool buy=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
      MqlTick tick;if(!SymbolInfoTick(CRTSymbol(),tick))return false;
      if((buy && new_sl<=old_sl) || (!buy && old_sl>0 && new_sl>=old_sl) ||
         !CRTTradeStopValid(buy,new_sl,tp,tick)){reason="Modificacion no mejora o no valida";return false;}
      bool sent=m_trade.PositionModify(ticket,new_sl,tp);
      if(!sent || (!CRTTradeRetcodeAccepted(m_trade.ResultRetcode()) && m_trade.ResultRetcode()!=TRADE_RETCODE_NO_CHANGES))
         {reason="Modificar SL: "+m_trade.ResultRetcodeDescription();Print(reason);return false;}
      return true;
   }
   void Partial(const ulong ticket,const double initial_risk)
   {
      if(!InpPartialsEnabled || InpPartialPercent<=0 || InpPartialPercent>=100 ||
         !CRTTradePositionOwned(ticket))return;
      string id=IntegerToString(PositionGetInteger(POSITION_IDENTIFIER));
      double flag=0;if(CRTTradeGet("P."+id,flag))return;
      bool buy=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
      double entry=PositionGetDouble(POSITION_PRICE_OPEN),volume=PositionGetDouble(POSITION_VOLUME);
      MqlTick tick;if(!SymbolInfoTick(CRTSymbol(),tick))return;
      if((buy?tick.bid-entry:entry-tick.ask)<InpPartialTriggerR*initial_risk)return;
      double step=SymbolInfoDouble(CRTSymbol(),SYMBOL_VOLUME_STEP),minimum=SymbolInfoDouble(CRTSymbol(),SYMBOL_VOLUME_MIN);
      if(step<=0)return;
      double part=NormalizeDouble(MathFloor(volume*InpPartialPercent/100.0/step+1e-9)*step,8);
      if(part<minimum-1e-9 || volume-part<minimum-1e-9 || part>=volume)return;
      // Attempt is persisted before sending; uncertain responses cannot duplicate partials.
      if(!CRTTradeSet("P."+id,1))return;
      bool sent=false;
      if(AccountInfoInteger(ACCOUNT_MARGIN_MODE)==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
         sent=m_trade.PositionClosePartial(ticket,part,InpDeviationPoints);
      else
      {
         string reason;if(!TradingOwnershipSafe(reason))return;
         // Netting reduction uses an opposite market deal smaller than the verified own volume.
         if(!CRTTradePositionOwned(ticket) || PositionGetDouble(POSITION_VOLUME)<=part)return;
         if(buy)sent=m_trade.Sell(part,CRTSymbol(),0,0,0,"CRT partial");
         else sent=m_trade.Buy(part,CRTSymbol(),0,0,0,"CRT partial");
      }
      if(!sent || !CRTTradeRetcodeAccepted(m_trade.ResultRetcode()))
         Print("CRT partial: ",m_trade.ResultRetcodeDescription());
   }
public:
   CPositionManager()
   {
      m_trade.SetExpertMagicNumber(InpMagic);m_trade.SetAsyncMode(false);
      m_trade.SetDeviationInPoints(InpDeviationPoints);m_trade.SetTypeFillingBySymbol(CRTSymbol());
      m_last_trail_bar=0;
   }
   int Count()
   {
      int count=0;
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         ulong ticket=PositionGetTicket(i);
         if(ticket>0 && PositionGetString(POSITION_SYMBOL)==CRTSymbol() &&
            PositionGetInteger(POSITION_MAGIC)==(long)InpMagic)count++;
      }
      return count;
   }
   bool CloseOwn(string &reason)
   {
      bool ok=true;
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         ulong ticket=PositionGetTicket(i);if(!CRTTradePositionOwned(ticket))continue;
         bool sent=m_trade.PositionClose(ticket,InpDeviationPoints);
         if(!sent || !CRTTradeRetcodeAccepted(m_trade.ResultRetcode()))
            {ok=false;reason="Cerrar propia: "+m_trade.ResultRetcodeDescription();Print(reason);}
      }
      return ok;
   }
   bool MoveToBE(string &reason)
   {
      bool changed=false;reason="No hay BE valido";
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         ulong ticket=PositionGetTicket(i);if(!CRTTradePositionOwned(ticket))continue;
         string id=IntegerToString(PositionGetInteger(POSITION_IDENTIFIER));double risk=0,new_sl=0;
         if(!CRTTradeGet("R."+id,risk)){reason="R inicial persistido no disponible";continue;}
         if(m_be.Propose(ticket,risk,true,new_sl,reason) && Modify(ticket,new_sl,reason))changed=true;
      }
      return changed;
   }
   void Reconcile()
   {
      STradePlan saved;bool have=CRTTradeStateLoad(saved);
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         ulong ticket=PositionGetTicket(i);if(!CRTTradePositionOwned(ticket))continue;
         string id=IntegerToString(PositionGetInteger(POSITION_IDENTIFIER));double risk=0;
         if(CRTTradeGet("R."+id,risk))continue;
         if(!have || PositionGetString(POSITION_COMMENT)!=CRTTradeComment(saved.signal_id))continue;
         double original=MathAbs(PositionGetDouble(POSITION_PRICE_OPEN)-saved.sl);
         if(original<=0)continue;
         CRTTradeSet("R."+id,original);
         CRTTradeSet("V."+id,PositionGetDouble(POSITION_VOLUME));
      }
   }
   bool Recover(STradePlan &p)
   {
      if(!CRTTradeStateLoad(p))return false;
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         ulong ticket=PositionGetTicket(i);
         if(CRTTradePositionOwned(ticket) && PositionGetString(POSITION_COMMENT)==CRTTradeComment(p.signal_id))
         {p.entry=PositionGetDouble(POSITION_PRICE_OPEN);p.volume=PositionGetDouble(POSITION_VOLUME);return true;}
      }
      return false;
   }
   void Manage(const double atr_pips)
   {
      datetime bar=iTime(CRTSymbol(),PERIOD_M1,0);
      bool new_bar=(bar>0 && bar!=m_last_trail_bar);
      if(new_bar)m_last_trail_bar=bar;
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         ulong ticket=PositionGetTicket(i);if(!CRTTradePositionOwned(ticket))continue;
         string id=IntegerToString(PositionGetInteger(POSITION_IDENTIFIER));double risk=0,new_sl=0;
         if(!CRTTradeGet("R."+id,risk) || risk<=0)continue;
         string reason;
         if(InpManagementMode==DELAYED_BREAK_EVEN)
         {
            if(m_be.Propose(ticket,risk,false,new_sl,reason))Modify(ticket,new_sl,reason);
         }
         else if(InpManagementMode==STRUCTURE_TRAILING_M1 && new_bar)
         {
            if(m_trail.Propose(ticket,risk,atr_pips,new_sl,reason))Modify(ticket,new_sl,reason);
         }
         Partial(ticket,risk);
      }
   }
};
#endif
