#ifndef CRT_LIQUIDITY_DETECTOR_MQH
#define CRT_LIQUIDITY_DETECTOR_MQH
#include "../Core/Utilities.mqh"
#include "SessionManager.mqh"
enum ELiquidityMode { CRT_PURE=0, CRT_STRUCTURAL=1, CRT_SESSION=2, CRT_EQUAL_LEVELS=3, CRT_ANY_LIQUIDITY=4 };
input group "LIQUIDITY"
input ELiquidityMode InpLiquidityMode=CRT_PURE;
input int InpLiquidityLookbackBars=576;
input int InpPivotStrength=2;
input double InpEqualLevelTolerancePips=0.2;
input int InpEqualLevelMinimumTouches=2;
struct SLiquidityLevel
{
   double price;
   bool high;
   int kind;
   datetime formed,known;
   bool consumed;
   string key;
};
class CLiquidityDetector
{
private:
   SLiquidityLevel m_levels[];
   MqlRates m_bars[];
   datetime m_cutoff;
   bool m_ready;
   CSessionManager m_session;
   string LevelKey(const double price,const datetime formed,const int kind,const bool high) const
   {
      double tick=SymbolInfoDouble(CRTSymbol(),SYMBOL_TRADE_TICK_SIZE);
      return CRTKey("L"+IntegerToString((long)formed)+"."+IntegerToString(kind)+(high?"H":"L")+"."+IntegerToString((long)MathRound(price/tick)));
   }
   bool Intact(const double price,const bool high,const datetime known) const
   {
      double tolerance=InpEqualLevelTolerancePips*CRTPip(CRTSymbol());
      for(int i=0;i<ArraySize(m_bars);i++)
      {
         if(m_bars[i].time<known) continue;
         if(high?m_bars[i].high>price+tolerance:m_bars[i].low<price-tolerance) return false;
      }
      return true;
   }
   void Add(const double price,const bool high,const int kind,const datetime formed,const datetime known)
   {
      if(price<=0 || known>m_cutoff || !Intact(price,high,known)) return;
      string key=LevelKey(price,formed,kind,high);
      if(GlobalVariableCheck(key)) return;
      for(int i=0;i<ArraySize(m_levels);i++) if(m_levels[i].key==key) return;
      int n=ArraySize(m_levels); ArrayResize(m_levels,n+1);
      m_levels[n].price=price; m_levels[n].high=high; m_levels[n].kind=kind;
      m_levels[n].formed=formed; m_levels[n].known=known; m_levels[n].consumed=false; m_levels[n].key=key;
   }
   void AddSession(const datetime startUTC,const datetime endUTC)
   {
      if(endUTC>m_session.ToUTC(m_cutoff) || startUTC>=endUTC) return;
      double high=-DBL_MAX,low=DBL_MAX; int count=0; datetime first=0,last=0;
      for(int i=0;i<ArraySize(m_bars);i++)
      {
         datetime utc=m_session.ToUTC(m_bars[i].time);
         if(utc<startUTC || utc+300>endUTC) continue;
         high=MathMax(high,m_bars[i].high); low=MathMin(low,m_bars[i].low);
         if(first==0 || utc<first) first=utc;
         if(utc>last) last=utc; count++;
      }
      // No session level from a partial historical window.
      if(count<2 || first>startUTC || last+300<endUTC) return;
      datetime known=m_session.ToServer(endUTC);
      Add(high,true,2,m_session.ToServer(startUTC),known);
      Add(low,false,2,m_session.ToServer(startUTC),known);
   }
public:
   CLiquidityDetector():m_cutoff(0),m_ready(false) {}
   bool Valid() const
   {
      return InpLiquidityLookbackBars>=50 && InpLiquidityLookbackBars<=5000 &&
             InpPivotStrength>=1 && InpPivotStrength<=10 && InpEqualLevelTolerancePips>=0 &&
             InpEqualLevelMinimumTouches>=2 && InpEqualLevelMinimumTouches<=10 && m_session.Valid();
   }
   bool Ready() const { return m_ready; }
   void Refresh(const datetime cutoff)
   {
      if(cutoff==m_cutoff && m_ready) return;
      m_cutoff=cutoff; m_ready=false; ArrayResize(m_levels,0);
      ArraySetAsSeries(m_bars,false);
      int n=CopyRates(CRTSymbol(),PERIOD_M5,cutoff-InpLiquidityLookbackBars*300,cutoff-1,m_bars);
      if(n<50) return;
      int used=n;
      while(used>0 && m_bars[used-1].time+300>cutoff) used--;
      ArrayResize(m_bars,used); n=used;
      if(n<50) return;
      int strength=InpPivotStrength;
      for(int i=strength;i<n-strength;i++)
      {
         bool high=true,low=true;
         for(int j=1;j<=strength;j++)
         {
            if(m_bars[i].high<=m_bars[i-j].high || m_bars[i].high<=m_bars[i+j].high) high=false;
            if(m_bars[i].low>=m_bars[i-j].low || m_bars[i].low>=m_bars[i+j].low) low=false;
         }
         datetime known=m_bars[i+strength].time+300;
         if(high) Add(m_bars[i].high,true,1,m_bars[i].time,known);
         if(low) Add(m_bars[i].low,false,1,m_bars[i].time,known);
      }
      // Equal levels require separated, independently confirmed pivot contacts.
      int structural=ArraySize(m_levels); double tol=InpEqualLevelTolerancePips*CRTPip(CRTSymbol());
      for(int i=0;i<structural;i++)
      {
         int contacts=1; datetime known=m_levels[i].known;
         double price=m_levels[i].price;
         for(int j=i+1;j<structural;j++)
         {
            if(m_levels[i].high!=m_levels[j].high || MathAbs(m_levels[j].price-price)>tol) continue;
            if(MathAbs((double)(m_levels[i].formed-m_levels[j].formed))<(2*strength+1)*300) continue;
            contacts++; known=(datetime)MathMax((double)known,(double)m_levels[j].known);
            price=m_levels[i].high?MathMax(price,m_levels[j].price):MathMin(price,m_levels[j].price);
         }
         if(contacts>=InpEqualLevelMinimumTouches) Add(price,m_levels[i].high,3,m_levels[i].formed,known);
      }
      // Previous completed broker day, never a forming D1 candle.
      MqlRates daily[]; ArraySetAsSeries(daily,true);
      if(CopyRates(CRTSymbol(),PERIOD_D1,cutoff-8*86400,cutoff,daily)>1)
      {
         for(int i=1;i<ArraySize(daily);i++)
         {
            datetime known=daily[i-1].time;
            if(known>cutoff) continue;
            Add(daily[i].high,true,2,daily[i].time,known);
            Add(daily[i].low,false,2,daily[i].time,known); break;
         }
      }
      datetime utc=m_session.ToUTC(cutoff); MqlDateTime date={}; TimeToStruct(utc,date);
      date.hour=0; date.min=0; date.sec=0; datetime midnight=StructToTime(date);
      for(int d=0;d<3;d++)
      {
         datetime day=midnight-d*86400;
         AddSession(day+InpAsiaUTCOpenHour*3600,day+InpAsiaUTCCloseHour*3600);
         int londonOffset=m_session.EUDST(day+12*3600)?1:0;
         AddSession(day+(InpLondonOpenHour-londonOffset)*3600,day+(InpLondonCloseHour-londonOffset)*3600);
      }
      m_ready=true;
   }
   bool Qualifies(const SSignal &signal,string &reason) const
   {
      if(InpLiquidityMode==CRT_PURE) return true;
      if(!m_ready) { reason="Confirmed liquidity history unavailable"; return false; }
      double tol=InpEqualLevelTolerancePips*CRTPip(CRTSymbol());
      for(int i=0;i<ArraySize(m_levels);i++)
      {
         if(m_levels[i].consumed || m_levels[i].known>signal.reference_time) continue;
         bool kind=InpLiquidityMode==CRT_ANY_LIQUIDITY || (InpLiquidityMode==CRT_STRUCTURAL && m_levels[i].kind==1) ||
                   (InpLiquidityMode==CRT_SESSION && m_levels[i].kind==2) || (InpLiquidityMode==CRT_EQUAL_LEVELS && m_levels[i].kind==3);
         if(!kind) continue;
         double level=m_levels[i].price;
         bool swept=signal.direction==DIR_BUY?
            (!m_levels[i].high && signal.extreme<level && signal.level>=level-tol):
            (m_levels[i].high && signal.extreme>level && signal.level<=level+tol);
         if(swept) return true;
      }
      reason="CRT did not sweep selected preexisting liquidity"; return false;
   }
   bool NextTarget(const SSignal &signal,const double entry,double &target)
   {
      target=0; if(!m_ready) return false;
      MqlTick tick; if(!SymbolInfoTick(CRTSymbol(),tick)) return false;
      Invalidate(tick);
      for(int i=0;i<ArraySize(m_levels);i++)
      {
         if(m_levels[i].consumed || m_levels[i].known>signal.reference_time || GlobalVariableCheck(m_levels[i].key)) continue;
         double level=m_levels[i].price;
         if(signal.direction==DIR_BUY)
         {
            if(!m_levels[i].high || level<=entry || tick.bid>=level) continue;
            if(target==0 || level<target) target=level;
         }
         else
         {
            if(m_levels[i].high || level>=entry || tick.ask<=level) continue;
            if(target==0 || level>target) target=level;
         }
      }
      return target>0;
   }
   void Invalidate(const MqlTick &tick)
   {
      bool changed=false;
      for(int i=0;i<ArraySize(m_levels);i++)
      {
         if(m_levels[i].consumed) continue;
         bool reached=m_levels[i].high?tick.bid>=m_levels[i].price:tick.ask<=m_levels[i].price;
         if(!reached) continue;
         m_levels[i].consumed=true; changed=true;
         GlobalVariableSet(m_levels[i].key,(double)TimeCurrent());
      }
      if(changed) GlobalVariablesFlush();
   }
   void Consume(const SSignal &signal)
   {
      double tol=InpEqualLevelTolerancePips*CRTPip(CRTSymbol());
      for(int i=0;i<ArraySize(m_levels);i++)
      {
         double level=m_levels[i].price;
         bool swept=signal.direction==DIR_BUY?
            (!m_levels[i].high && signal.extreme<level && signal.level>=level-tol):
            (m_levels[i].high && signal.extreme>level && signal.level<=level+tol);
         if(swept)
         {
            m_levels[i].consumed=true;
            GlobalVariableSet(m_levels[i].key,(double)signal.confirmed_at);
         }
      }
      GlobalVariablesFlush();
   }
};
#endif
