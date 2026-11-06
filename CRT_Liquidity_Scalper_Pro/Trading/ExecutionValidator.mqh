#ifndef CRT_EXECUTION_VALIDATOR_MQH
#define CRT_EXECUTION_VALIDATOR_MQH
#include "../Core/Config.mqh"
#include "../Core/Types.mqh"
#include "../Core/Utilities.mqh"


// Hash is used only for identifiers, never as evidence that a fill occurred.
uint CRTTradeHash(const string value)
{
   uint h=2166136261;
   for(int i=0;i<StringLen(value);i++){ h^=(uint)StringGetCharacter(value,i); h*=16777619; }
   return h;
}
string CRTTradeKey(const string suffix)
{
   return CRTKey("T."+suffix);
}
string CRTTradeComment(const string id){return "CRT:"+IntegerToString((long)CRTTradeHash(id));}
bool CRTTradeSet(const string key,const double value)
{
   ResetLastError();
   datetime result=GlobalVariableSet(CRTTradeKey(key),value);
   GlobalVariablesFlush();
   return result!=0;
}
bool CRTTradeGet(const string key,double &value){return GlobalVariableGet(CRTTradeKey(key),value);}
bool CRTTradeStateSave(const STradePlan &p)
{
   string filename=CRTTradeKey("intent")+".csv";
   int f=FileOpen(filename,FILE_WRITE|FILE_CSV|FILE_COMMON,';');
   if(f==INVALID_HANDLE)return false;
   uint written=FileWrite(f,1,p.signal_id,(int)p.direction,(int)p.mode,(long)p.created,(long)p.expiration,
                         p.entry,p.sl,p.tp,p.rr,p.volume,p.risk_money,p.atr_pips,p.target_level,(int)p.pending);
   FileFlush(f); FileClose(f);
   return written>0;
}
bool CRTTradeStateLoad(STradePlan &p)
{
   int f=FileOpen(CRTTradeKey("intent")+".csv",FILE_READ|FILE_CSV|FILE_COMMON,';');
   if(f==INVALID_HANDLE)return false;
   int version=(int)FileReadNumber(f);
   p.signal_id=FileReadString(f); p.direction=(EDirection)(int)FileReadNumber(f); p.mode=(EEntryMode)(int)FileReadNumber(f);
   p.created=(datetime)(long)FileReadNumber(f);p.expiration=(datetime)(long)FileReadNumber(f);
   p.entry=FileReadNumber(f);p.sl=FileReadNumber(f);p.tp=FileReadNumber(f);p.rr=FileReadNumber(f);
   p.volume=FileReadNumber(f);p.risk_money=FileReadNumber(f);p.atr_pips=FileReadNumber(f);p.target_level=FileReadNumber(f);
   p.pending=(bool)(int)FileReadNumber(f); FileClose(f);
   return version==1 && p.signal_id!="" && p.entry>0 && p.sl>0 && p.tp>0 && p.volume>0 &&
          (p.direction==DIR_BUY || p.direction==DIR_SELL) && MathIsValidNumber(p.risk_money);
}
bool CRTTradePositionOwned(const ulong ticket)
{
   if(!PositionSelectByTicket(ticket) || PositionGetString(POSITION_SYMBOL)!=CRTSymbol() ||
      PositionGetInteger(POSITION_MAGIC)!=(long)InpMagic)return false;
   long identifier=PositionGetInteger(POSITION_IDENTIFIER);
   if(!HistorySelectByPosition(identifier))return false;
   int n=HistoryDealsTotal();bool own_entry=false;
   if(n<1)return false;
   for(int i=0;i<n;i++)
   {
      ulong deal=HistoryDealGetTicket(i);
      ENUM_DEAL_TYPE type=(ENUM_DEAL_TYPE)HistoryDealGetInteger(deal,DEAL_TYPE);
      if((type==DEAL_TYPE_BUY || type==DEAL_TYPE_SELL) &&
         HistoryDealGetInteger(deal,DEAL_MAGIC)!=(long)InpMagic)return false;
      ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY);
      if((type==DEAL_TYPE_BUY || type==DEAL_TYPE_SELL) &&
         (entry==DEAL_ENTRY_IN || entry==DEAL_ENTRY_INOUT))own_entry=true;
   }
   return own_entry && PositionSelectByTicket(ticket);
}
bool TradingOwnershipSafe(string &reason)
{
   bool hedging=(AccountInfoInteger(ACCOUNT_MARGIN_MODE)==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
   if(hedging)return true;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || PositionGetString(POSITION_SYMBOL)!=CRTSymbol())continue;
      if(!CRTTradePositionOwned(ticket)){reason="Netting: posicion o historial de otro propietario";return false;}
   }
   // Foreign pending orders on a netting symbol can merge into the same position later.
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i);
      if(ticket>0 && OrderGetString(ORDER_SYMBOL)==CRTSymbol() &&
         OrderGetInteger(ORDER_MAGIC)!=(long)InpMagic){reason="Netting: pendiente ajena en simbolo";return false;}
   }
   return true;
}
bool CRTTradeRetcodeAccepted(const uint code)
{
   return code==TRADE_RETCODE_DONE || code==TRADE_RETCODE_PLACED || code==TRADE_RETCODE_DONE_PARTIAL;
}
bool CRTTradePriceOnGrid(const string symbol,const double value)
{
   double tick=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tick<=0 || value<=0 || !MathIsValidNumber(value))return false;
   return MathAbs(value/tick-MathRound(value/tick))<=0.00001;
}
bool CRTTradeStopValid(const bool buy,const double sl,const double tp,const MqlTick &tick)
{
   string symbol=CRTSymbol();
   double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
   double minimum=(double)MathMax(SymbolInfoInteger(symbol,SYMBOL_TRADE_STOPS_LEVEL),
                                 SymbolInfoInteger(symbol,SYMBOL_TRADE_FREEZE_LEVEL))*point;
   double price=buy?tick.bid:tick.ask;
   if(!CRTTradePriceOnGrid(symbol,sl) || !CRTTradePriceOnGrid(symbol,tp))return false;
   return buy?(sl<price && tp>price && price-sl>=minimum && tp-price>=minimum):
              (sl>price && tp<price && sl-price>=minimum && price-tp>=minimum);
}
class CExecutionValidator
{
public:
   bool Validate(const STradePlan &p,string &reason)
   {
      string symbol=CRTSymbol();
      if(!TerminalInfoInteger(TERMINAL_CONNECTED) || !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) ||
         !MQLInfoInteger(MQL_TRADE_ALLOWED) || !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) ||
         !AccountInfoInteger(ACCOUNT_TRADE_EXPERT)){reason="Trading desconectado o no permitido";return false;}
      if(!TradingOwnershipSafe(reason))return false;
      // Final independent admission guard: no stacking while another own exposure exists.
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         ulong own=PositionGetTicket(i);
         if(own>0 && PositionGetString(POSITION_SYMBOL)==symbol &&
            PositionGetInteger(POSITION_MAGIC)==(long)InpMagic)
            {reason="Ya existe una posicion propia";return false;}
      }
      for(int i=OrdersTotal()-1;i>=0;i--)
      {
         ulong own=OrderGetTicket(i);
         if(own>0 && OrderGetString(ORDER_SYMBOL)==symbol &&
            OrderGetInteger(ORDER_MAGIC)==(long)InpMagic)
            {reason="Ya existe una pendiente propia";return false;}
      }
      long mode=SymbolInfoInteger(symbol,SYMBOL_TRADE_MODE);
      if(mode==SYMBOL_TRADE_MODE_DISABLED || mode==SYMBOL_TRADE_MODE_CLOSEONLY ||
         (p.direction==DIR_BUY && mode==SYMBOL_TRADE_MODE_SHORTONLY) ||
         (p.direction==DIR_SELL && mode==SYMBOL_TRADE_MODE_LONGONLY)){reason="Modo trading del simbolo";return false;}
      MqlTick tick;
      if(!SymbolInfoTick(symbol,tick) || tick.ask<=tick.bid || tick.bid<=0 ||
         (TimeCurrent()-tick.time)>InpMaximumQuoteAgeSeconds){reason="Cotizacion incompleta o antigua";return false;}
      bool session=false;MqlDateTime d;TimeToStruct(TimeCurrent(),d);
      int seconds=d.hour*3600+d.min*60+d.sec;
      for(uint i=0;i<32;i++)
      {
         datetime from,to;
         if(!SymbolInfoSessionTrade(symbol,(ENUM_DAY_OF_WEEK)d.day_of_week,i,from,to))break;
         int a=(int)((long)from%86400),b=(int)((long)to%86400);
         if(a==b || (a<b && seconds>=a && seconds<b) || (a>b && (seconds>=a || seconds<b))){session=true;break;}
      }
      if(!session){reason="Fuera de sesion del broker o sesion desconocida";return false;}
      bool buy=(p.direction==DIR_BUY);
      if((!buy && p.direction!=DIR_SELL) || p.entry<=0 || p.sl<=0 || p.tp<=0 ||
         !CRTTradePriceOnGrid(symbol,p.entry) || !CRTTradePriceOnGrid(symbol,p.sl) ||
         !CRTTradePriceOnGrid(symbol,p.tp)){reason="Precios o direccion invalidos";return false;}
      double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
      double min_distance=(double)MathMax(SymbolInfoInteger(symbol,SYMBOL_TRADE_STOPS_LEVEL),
                                         SymbolInfoInteger(symbol,SYMBOL_TRADE_FREEZE_LEVEL))*point;
      if((buy && (p.sl>=p.entry || p.tp<=p.entry)) || (!buy && (p.sl<=p.entry || p.tp>=p.entry)) ||
         MathAbs(p.entry-p.sl)<min_distance || MathAbs(p.tp-p.entry)<min_distance)
         {reason="SL/TP fuera de stops/freeze level";return false;}
      if(p.pending)
      {
         double gap=buy?tick.ask-p.entry:p.entry-tick.bid;
         if(gap<=0 || gap<min_distance){reason="Limit invalida; nunca se convierte a mercado";return false;}
         if(p.expiration<=TimeCurrent()){reason="Pendiente expirada";return false;}
         long expiration=SymbolInfoInteger(symbol,SYMBOL_EXPIRATION_MODE);
         if((expiration&SYMBOL_EXPIRATION_SPECIFIED)==0){reason="Broker sin expiracion especificada";return false;}
      }
      else if(!CRTTradeStopValid(buy,p.sl,p.tp,tick)){reason="SL/TP invalidos frente a Bid/Ask";return false;}
      double step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP),vmin=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
      double vmax=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
      if(step<=0 || p.volume<vmin-1e-9 || p.volume>vmax+1e-9 ||
         MathAbs(p.volume/step-MathRound(p.volume/step))>0.00001)
         {reason="Volumen fuera de min/max/step";return false;}
      double margin=0;
      ENUM_ORDER_TYPE type=buy?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
      if(!OrderCalcMargin(type,symbol,p.volume,p.entry,margin) || margin<=0 ||
         margin>AccountInfoDouble(ACCOUNT_MARGIN_FREE)){reason="Margen insuficiente o desconocido";return false;}
      return true;
   }
};
#endif
