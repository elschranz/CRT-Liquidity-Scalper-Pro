#ifndef CRT_TRADE_JOURNAL_MQH
#define CRT_TRADE_JOURNAL_MQH
#include "../Core/Config.mqh"
#include "../Core/Types.mqh"
#include "../Core/Utilities.mqh"
#include "../Strategy/SessionManager.mqh"


// Core CRTKey has a bounded account/server/symbol/magic prefix. Full position IDs
// avoid hashing different trades onto the same analytics persistence key.
uint CRTJournalHash(const string text)
  {
   uint h=2166136261;
   for(int i=0;i<StringLen(text);i++) { h^=(uint)StringGetCharacter(text,i); h*=16777619; }
   return h;
  }
string CRTJournalPositionKey(const ulong id,const string suffix)
  {
   return CRTKey("J"+(string)id+"."+suffix);
  }
double CRTJournalGet(const ulong id,const string suffix)
  {
   const string key=CRTJournalPositionKey(id,suffix);
   return GlobalVariableCheck(key)?GlobalVariableGet(key):0.0;
  }
bool CRTJournalSet(const ulong id,const string suffix,const double value)
  {
   return GlobalVariableSet(CRTJournalPositionKey(id,suffix),value)>0;
  }
double CRTJournalOriginalRisk(const ulong position_id)
  {
   return CRTJournalGet(position_id,"risk");
  }
bool CRTJournalPositionOpen(const ulong id)
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      if(PositionGetTicket(i)==0) continue;
      if((ulong)PositionGetInteger(POSITION_IDENTIFIER)==id) return true;
     }
   return false;
  }

class CTradeJournal
  {
private:
   int m_file;
   SSignal m_signal;
   STradePlan m_plan;
   string m_base;
   CSessionManager m_sessions;
   string ContextPath() { return m_base+"_context.csv"; }
   string Num(const double value,const int digits=5) { return DoubleToString(value,digits); }
   string Mode(const EEntryMode mode)
     { return mode==ENTRY_AGGRESSIVE?"AGGRESSIVE":"CONFIRMED"; }
   string PositionPath(const ulong id) { return m_base+"_p_"+(string)id+".csv"; }
   void SaveContext(const string path,const SSignal &signal,const STradePlan &plan)
     {
      int h=FileOpen(path,FILE_WRITE|FILE_CSV|FILE_ANSI,',');
      if(h==INVALID_HANDLE) { Print("CRT journal: cannot persist context: ",GetLastError()); return; }
      FileWrite(h,signal.id,(int)signal.direction,(long)signal.reference_time,
                (long)signal.confirmed_at,signal.level,signal.extreme,signal.atr_pips,
                (long)signal.retest_time,plan.signal_id,(int)plan.mode,plan.entry,
                plan.sl,plan.tp,plan.rr,plan.volume,plan.risk_money,
                (long)plan.created,(long)plan.expiration,plan.pending?1:0,
                signal.range_high,signal.range_low);
      FileFlush(h); FileClose(h);
     }
   bool LoadContext(const string path,SSignal &signal,STradePlan &plan)
     {
      int h=FileOpen(path,FILE_READ|FILE_CSV|FILE_ANSI,',');
      if(h==INVALID_HANDLE) return false;
      signal.id=FileReadString(h);
      signal.direction=(EDirection)(int)FileReadNumber(h);
      signal.reference_time=(datetime)FileReadNumber(h);
      signal.confirmed_at=(datetime)FileReadNumber(h);
      signal.level=FileReadNumber(h); signal.extreme=FileReadNumber(h);
      signal.atr_pips=FileReadNumber(h); signal.retest_time=(datetime)FileReadNumber(h);
      plan.signal_id=FileReadString(h); plan.mode=(EEntryMode)(int)FileReadNumber(h);
      plan.entry=FileReadNumber(h); plan.sl=FileReadNumber(h); plan.tp=FileReadNumber(h);
      plan.rr=FileReadNumber(h); plan.volume=FileReadNumber(h);
      plan.risk_money=FileReadNumber(h); plan.created=(datetime)FileReadNumber(h);
      plan.expiration=(datetime)FileReadNumber(h); plan.pending=FileReadNumber(h)>0;
      signal.range_high=FileReadNumber(h); signal.range_low=FileReadNumber(h);
      plan.direction=signal.direction; plan.atr_pips=signal.atr_pips;
      FileClose(h);
      return signal.id!="" && plan.signal_id==signal.id;
     }
   void Write(const string event,const string reason,const ulong order=0,
              const ulong deal=0,const ulong position=0,const double real_entry=0,
              const double volume=0,const double profit=0,const double commission=0,
              const double swap=0,const double fee=0,const double slippage=0,
              const bool observed=false)
     {
      if(!InpJournalEnabled || m_file==INVALID_HANDLE) return;
      MqlTick tick; ZeroMemory(tick); SymbolInfoTick(CRTSymbol(),tick);
      const double spread=CRTPips(CRTSymbol(),tick.ask-tick.bid);
      SSignal logged_signal=m_signal; STradePlan logged_plan=m_plan;
      bool metadata=true;
      if(position>0)
        {
         ZeroMemory(logged_signal); ZeroMemory(logged_plan);
         metadata=LoadContext(PositionPath(position),logged_signal,logged_plan);
        }
      const double mfe=position>0?CRTJournalGet(position,"mfe"):0;
      const double mae=position>0?CRTJournalGet(position,"mae"):0;
      const long retest_seconds=logged_signal.retest_time>0?
                                (long)(logged_signal.retest_time-logged_signal.confirmed_at):-1;
      const bool mapped=metadata && (position==0 || CRTJournalGet(position,"mapped")>0);
      FileWrite(m_file,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),"REAL",event,
                logged_signal.id,TimeToString(logged_signal.confirmed_at,TIME_DATE|TIME_SECONDS),
                CRTSymbol(),(int)logged_signal.direction,mapped?Mode(logged_plan.mode):"N/A",
                logged_signal.confirmed_at>0?m_sessions.Name(logged_signal.confirmed_at):"N/A",
                Num(logged_signal.level),Num(logged_signal.extreme),Num(logged_signal.atr_pips,3),
                Num(logged_plan.entry),Num(real_entry),Num(logged_plan.sl),Num(logged_plan.tp),
                Num(logged_plan.rr,3),Num(volume,4),Num(spread,3),Num(commission,2),
                Num(swap,2),Num(fee,2),Num(profit,2),Num(InpSlippagePips,3),
                observed?Num(slippage,3):"N/A",Num(mfe,3),Num(mae,3),
                retest_seconds>=0?(string)retest_seconds:"N/A",
                (string)order,(string)deal,(string)position,
                position>0?Num(CRTJournalOriginalRisk(position),2):"N/A",
                mapped?"mapped":"metadata_unavailable",TimeToString(logged_signal.reference_time,TIME_DATE|TIME_SECONDS),
                Num(logged_signal.range_high),Num(logged_signal.range_low),reason);
      FileFlush(m_file);
     }
   void RegisterEntry(const ulong deal,const ulong position)
     {
      const double entry=HistoryDealGetDouble(deal,DEAL_PRICE);
      const double volume=HistoryDealGetDouble(deal,DEAL_VOLUME);
      const ulong order=(ulong)HistoryDealGetInteger(deal,DEAL_ORDER);
      const ENUM_DEAL_TYPE type=(ENUM_DEAL_TYPE)HistoryDealGetInteger(deal,DEAL_TYPE);
      const bool buy=type==DEAL_TYPE_BUY;
      double initial_sl=0,expected=0;
      string opening_comment="";
      // Historic ORDER_SL is the opening stop, never the later trailing stop.
      if(HistoryOrderSelect(order))
        {
         initial_sl=HistoryOrderGetDouble(order,ORDER_SL);
         expected=HistoryOrderGetDouble(order,ORDER_PRICE_OPEN);
         opening_comment=HistoryOrderGetString(order,ORDER_COMMENT);
        }
      else if(OrderSelect(order))
        {
         // A partially filled pending order can still be live rather than historical.
         initial_sl=OrderGetDouble(ORDER_SL);
         expected=OrderGetDouble(ORDER_PRICE_OPEN);
         opening_comment=OrderGetString(ORDER_COMMENT);
        }
      const double ticksize=SymbolInfoDouble(CRTSymbol(),SYMBOL_TRADE_TICK_SIZE);
      const string expected_comment="CRT:"+IntegerToString((long)CRTJournalHash(m_plan.signal_id));
      const bool context=m_plan.signal_id!="" && m_signal.id==m_plan.signal_id &&
                         StringFind(opening_comment,expected_comment)==0 &&
                         m_plan.sl>0 && initial_sl>0 &&
                         MathAbs(m_plan.sl-initial_sl)<=ticksize*1.1;
      if(context) { expected=m_plan.entry; SaveContext(PositionPath(position),m_signal,m_plan); }
      if(initial_sl<=0 || (buy && initial_sl>=entry) || (!buy && initial_sl<=entry))
        {
         CRTJournalSet(position,"mapped",0);
         return; // Unknown opening risk: do not manufacture R statistics.
        }
      const string seen_key=CRTKey("JD"+(string)deal);
      if(GlobalVariableCheck(seen_key)) return;
      double pnl=0;
      if(!OrderCalcProfit(buy?ORDER_TYPE_BUY:ORDER_TYPE_SELL,CRTSymbol(),
                          volume,entry,initial_sl,pnl)) return;
      const double risk=MathAbs(pnl)+InpCommissionPerLot*volume;
      CRTJournalSet(position,"risk",CRTJournalOriginalRisk(position)+risk);
      CRTJournalSet(position,"distance",MathAbs(entry-initial_sl));
      CRTJournalSet(position,"expected",expected);
      CRTJournalSet(position,"sl",initial_sl);
      CRTJournalSet(position,"mapped",context?1:0);
      CRTJournalSet(position,"mode",context?(int)m_plan.mode:-1);
      CRTJournalSet(position,"atr",context?m_plan.atr_pips:0);
      CRTJournalSet(position,"rr",context?m_plan.rr:0);
      CRTJournalSet(position,"opened",(double)HistoryDealGetInteger(deal,DEAL_TIME));
      CRTJournalSet(position,"mfe",CRTJournalGet(position,"mfe"));
      CRTJournalSet(position,"mae",CRTJournalGet(position,"mae"));
      GlobalVariableSet(seen_key,1);
      GlobalVariablesFlush();
     }
public:
   CTradeJournal() { m_file=INVALID_HANDLE; ZeroMemory(m_signal); ZeroMemory(m_plan); }
   bool Init()
     {
      m_base=CRTKey("analytics");
      LoadContext(ContextPath(),m_signal,m_plan);
      if(!InpJournalEnabled) return true;
      m_file=FileOpen(m_base+"_real.csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|
                      FILE_SHARE_READ,',');
      if(m_file==INVALID_HANDLE) { Print("CRT journal open failed: ",GetLastError()); return false; }
      if(FileSize(m_file)==0)
        {
         FileWrite(m_file,"server_time","dataset","event","signal_id","signal_confirmed",
                   "symbol","direction","mode","session","level","sweep_extreme","atr_pips",
                   "planned_entry","deal_price","sl","tp","rr","volume","spread_pips",
                   "commission","swap","fee","profit","estimated_slippage_pips",
                   "observed_slippage_pips","mfe_pips","mae_pips","retest_seconds",
                   "order","deal","position_id","initial_risk_money","mapping","reference_open","reference_high","reference_low","reason");
        }
      FileSeek(m_file,0,SEEK_END);
      Write("JOURNAL_START","Excursions are observed ticks; gaps and prior history are not reconstructed");
      return true;
     }
   void Signal(const SSignal &signal,const string event,const string reason)
     {
      // Observing another CRT while an owned order is live must not erase that order's
      // submitted context. Signal rows use a temporary snapshot only.
      const SSignal submitted_signal=m_signal;
      const STradePlan submitted_plan=m_plan;
      m_signal=signal;
      if(m_plan.signal_id!=signal.id) ZeroMemory(m_plan);
      Write(event,reason);
      m_signal=submitted_signal; m_plan=submitted_plan;
     }
   void Plan(const SSignal &signal,const STradePlan &plan,const string event,const string reason)
     {
      if(StringFind(event,"VIRTUAL")==0)
        {
         Print("CRT journal: virtual observations require the separate comparison ledger.");
         return;
        }
      const SSignal submitted_signal=m_signal;
      const STradePlan submitted_plan=m_plan;
      m_signal=signal; m_plan=plan;
      if(event=="REQUEST") SaveContext(ContextPath(),m_signal,m_plan);
      Write(event,reason,0,0,0,0,plan.volume);
      // Only a real submitted request can replace recovery metadata. Candidate rejects,
      // display updates and all other journal observations are non-mutating.
      if(event!="REQUEST") { m_signal=submitted_signal; m_plan=submitted_plan; }
     }
   void Transaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,
                    const MqlTradeResult &result)
     {
      if(trans.type!=TRADE_TRANSACTION_DEAL_ADD || trans.deal==0) return;
      if(!HistoryDealSelect(trans.deal)) return;
      if(HistoryDealGetString(trans.deal,DEAL_SYMBOL)!=CRTSymbol()) return;
      const ulong position=(ulong)HistoryDealGetInteger(trans.deal,DEAL_POSITION_ID);
      const ulong magic=(ulong)HistoryDealGetInteger(trans.deal,DEAL_MAGIC);
      if(magic!=InpMagic && CRTJournalOriginalRisk(position)<=0) return;
      const ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
      if(magic!=InpMagic)
        {
         CRTJournalSet(position,"mixed",1);
         Write("FOREIGN_DEAL_ON_TRACKED_POSITION","Excluded from R statistics",
               trans.order,trans.deal,position);
         return;
        }
      if(entry==DEAL_ENTRY_IN) RegisterEntry(trans.deal,position);
      const double price=HistoryDealGetDouble(trans.deal,DEAL_PRICE);
      const double expected=CRTJournalGet(position,"expected");
      const ENUM_DEAL_TYPE type=(ENUM_DEAL_TYPE)HistoryDealGetInteger(trans.deal,DEAL_TYPE);
      const double slip=(price-expected)*(type==DEAL_TYPE_BUY?1:-1)/CRTPip(CRTSymbol());
      const string event=entry==DEAL_ENTRY_IN?"FILL":
                         (CRTJournalPositionOpen(position)?"PARTIAL_CLOSE":"CLOSE");
      Write(event,EnumToString((ENUM_DEAL_REASON)HistoryDealGetInteger(trans.deal,DEAL_REASON)),
            (ulong)HistoryDealGetInteger(trans.deal,DEAL_ORDER),trans.deal,position,
            price,HistoryDealGetDouble(trans.deal,DEAL_VOLUME),
            HistoryDealGetDouble(trans.deal,DEAL_PROFIT),
            HistoryDealGetDouble(trans.deal,DEAL_COMMISSION),
            HistoryDealGetDouble(trans.deal,DEAL_SWAP),
            HistoryDealGetDouble(trans.deal,DEAL_FEE),slip,
            entry==DEAL_ENTRY_IN && expected>0);
     }
   void Tick(const MqlTick &tick)
     {
      if(tick.bid<=0 || tick.ask<=0) return;
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         if(PositionGetTicket(i)==0 || PositionGetString(POSITION_SYMBOL)!=CRTSymbol() ||
            (ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
         const ulong id=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
         const bool buy=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY;
         const double pips=((buy?tick.bid:tick.ask)-PositionGetDouble(POSITION_PRICE_OPEN))*
                            (buy?1:-1)/CRTPip(CRTSymbol());
         if(pips>CRTJournalGet(id,"mfe")) CRTJournalSet(id,"mfe",pips);
         if(-pips>CRTJournalGet(id,"mae")) CRTJournalSet(id,"mae",-pips);
        }
     }
   void Close()
     {
      if(m_file!=INVALID_HANDLE) { FileFlush(m_file); FileClose(m_file); m_file=INVALID_HANDLE; }
      GlobalVariablesFlush();
     }
  };
#endif
