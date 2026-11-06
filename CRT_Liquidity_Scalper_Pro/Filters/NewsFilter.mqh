#ifndef CRT_NEWS_FILTER_MQH
#define CRT_NEWS_FILTER_MQH
input group "NEWS"
input bool InpNewsFilterEnabled=true;
input int InpNewsMinutesBefore=15;
input int InpNewsMinutesAfter=15;
input bool InpBlockWhenCalendarUnavailable=true;
input int InpCalendarRefreshSeconds=30;
class CNewsFilter
{
private:
   datetime m_checked;
   datetime m_events[];
   string m_names[];
   bool m_available;
   string m_status;
   bool Currency(const string currency,const datetime now)
   {
      MqlCalendarValue values[];
      ResetLastError();
      // Query beyond the block window so cached events gate the exact boundary on every tick.
      // Calendar API timestamps already use trade-server time including its DST.
      int count=CalendarValueHistory(values,now-InpNewsMinutesAfter*60,
                                    now+86400+InpNewsMinutesBefore*60,NULL,currency);
      if(count<0 || GetLastError()!=0) return false;
      for(int i=0;i<count;i++)
      {
         MqlCalendarEvent event;
         if(!CalendarEventById(values[i].event_id,event)) return false;
         if(event.importance!=CALENDAR_IMPORTANCE_HIGH) continue;
         int n=ArraySize(m_events);
         ArrayResize(m_events,n+1); ArrayResize(m_names,n+1);
         m_events[n]=values[i].time; m_names[n]=currency+": "+event.name;
      }
      return true;
   }
public:
   CNewsFilter() { m_checked=0; m_available=false; m_status="Calendar not checked"; }
   string Status() { return m_status; }
   void Invalidate() { m_checked=0; }
   bool Allowed(const datetime server_time,string &reason)
   {
      if(!InpNewsFilterEnabled) { m_status="News filter disabled"; return true; }
      if(InpNewsMinutesBefore<0 || InpNewsMinutesAfter<0 ||
         InpCalendarRefreshSeconds<1 || InpCalendarRefreshSeconds>3600)
      { reason="Invalid news-filter inputs"; return false; }
      if(m_checked==0 || server_time<m_checked ||
         server_time-m_checked>=InpCalendarRefreshSeconds)
      {
         m_checked=server_time;
         ArrayResize(m_events,0); ArrayResize(m_names,0);
         // Native economic calendar is unavailable inside Strategy Tester.
         if(MQLInfoInteger(MQL_TESTER)) m_available=false;
         else
         {
            const bool eur_ok=Currency("EUR",server_time);
            const bool usd_ok=Currency("USD",server_time);
            m_available=eur_ok && usd_ok;
         }
      }
      if(!m_available)
      {
         m_status=InpBlockWhenCalendarUnavailable ? "NEWS BLOCK: calendar unavailable" :
            "Calendar unavailable: explicit permissive policy";
         if(InpBlockWhenCalendarUnavailable) reason=m_status;
         return !InpBlockWhenCalendarUnavailable;
      }
      for(int i=0;i<ArraySize(m_events);i++)
         if(server_time>=m_events[i]-InpNewsMinutesBefore*60 &&
            server_time<=m_events[i]+InpNewsMinutesAfter*60)
         { m_status="NEWS BLOCK "+m_names[i]; reason=m_status; return false; }
      m_status="Calendar available / no high-impact EUR/USD news";
      return true;
   }
};
#endif
