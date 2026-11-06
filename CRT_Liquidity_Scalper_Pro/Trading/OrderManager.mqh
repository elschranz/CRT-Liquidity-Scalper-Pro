#ifndef CRT_ORDER_MANAGER_MQH
#define CRT_ORDER_MANAGER_MQH
#include "../Core/Config.mqh"
#include <Trade/Trade.mqh>
#include "ExecutionValidator.mqh"
class COrderManager
{
private:
   CTrade m_trade;
public:
   COrderManager(){m_trade.SetExpertMagicNumber(InpMagic);m_trade.SetAsyncMode(false);}
   int Count()
   {
      int count=0;
      for(int i=OrdersTotal()-1;i>=0;i--)
      {
         ulong ticket=OrderGetTicket(i);
         if(ticket>0 && OrderGetString(ORDER_SYMBOL)==CRTSymbol() &&
            OrderGetInteger(ORDER_MAGIC)==(long)InpMagic)count++;
      }
      return count;
   }
   bool HasSignal(const string id)
   {
      if(GlobalVariableCheck(CRTTradeKey("S"+IntegerToString((long)CRTTradeHash(id)))))return true;
      string comment=CRTTradeComment(id);
      for(int i=OrdersTotal()-1;i>=0;i--)
      {
         ulong ticket=OrderGetTicket(i);
         if(ticket>0 && OrderGetString(ORDER_SYMBOL)==CRTSymbol() &&
            OrderGetInteger(ORDER_MAGIC)==(long)InpMagic && OrderGetString(ORDER_COMMENT)==comment)return true;
      }
      return false;
   }
   bool CancelOwn(string &reason)
   {
      bool ok=true;
      for(int i=OrdersTotal()-1;i>=0;i--)
      {
         ulong ticket=OrderGetTicket(i);
         if(ticket==0 || OrderGetString(ORDER_SYMBOL)!=CRTSymbol() ||
            OrderGetInteger(ORDER_MAGIC)!=(long)InpMagic)continue;
         bool requested=m_trade.OrderDelete(ticket);
         uint code=m_trade.ResultRetcode();
         if(!requested || !CRTTradeRetcodeAccepted(code))
         {ok=false;reason="Cancelar pendiente: "+m_trade.ResultRetcodeDescription();Print(reason);}
      }
      return ok;
   }
   void Maintain(const SSignal &signal)
   {
      MqlTick tick;if(!SymbolInfoTick(CRTSymbol(),tick))return;
      for(int i=OrdersTotal()-1;i>=0;i--)
      {
         ulong ticket=OrderGetTicket(i);
         if(ticket==0 || OrderGetString(ORDER_SYMBOL)!=CRTSymbol() ||
            OrderGetInteger(ORDER_MAGIC)!=(long)InpMagic)continue;
         bool buy=(OrderGetInteger(ORDER_TYPE)==ORDER_TYPE_BUY_LIMIT);
         datetime expiration=(datetime)OrderGetInteger(ORDER_TIME_EXPIRATION);
         bool matching=(signal.active && OrderGetString(ORDER_COMMENT)==CRTTradeComment(signal.id));
         // Missing structural state after restart is not guessed: cancel the pending order.
         bool cancel=!matching || (expiration>0 && TimeCurrent()>=expiration);
         double target=OrderGetDouble(ORDER_TP);
         if(matching)
         {
            if(TimeCurrent()>=signal.expires_at)cancel=true;
            if(buy && (tick.bid<signal.extreme || (target>0 && tick.bid>=target)))cancel=true;
            if(!buy && (tick.ask>signal.extreme || (target>0 && tick.ask<=target)))cancel=true;
         }
         if(cancel)
         {
            bool requested=m_trade.OrderDelete(ticket);
            if(!requested || !CRTTradeRetcodeAccepted(m_trade.ResultRetcode()))
               Print("CRT cancel ",ticket,": ",m_trade.ResultRetcodeDescription());
         }
      }
   }
};
#endif
