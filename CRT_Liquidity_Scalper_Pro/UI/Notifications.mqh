#ifndef CRT_UI_NOTIFICATIONS_MQH
#define CRT_UI_NOTIFICATIONS_MQH
input group "NOTIFICATIONS"
input bool InpNotifyTerminal=true;
input bool InpNotifyPush=false;
input bool InpNotifySound=false;
input string InpNotificationSound="alert.wav";
input int InpNotificationDedupeSeconds=60;

// Bounded in-memory cache avoids repeated tick/timer notifications without unbounded growth.
// Root supplies event keys containing signal/deal identifiers for execution events.
class CNotifications
  {
private:
   string m_keys[128];
   datetime m_times[128];
   int m_cursor;
public:
   CNotifications(void)
     {
      m_cursor=0;
      for(int i=0;i<128;i++) { m_keys[i]=""; m_times[i]=0; }
     }
   void Send(const string key,const string message)
     {
      const datetime now=TimeCurrent();
      for(int i=0;i<128;i++)
         if(m_keys[i]==key && now-m_times[i]<MathMax(1,InpNotificationDedupeSeconds)) return;
      m_keys[m_cursor]=key; m_times[m_cursor]=now; m_cursor=(m_cursor+1)%128;
      const string text="CRT SCALPER PRO | "+message;
      if(InpNotifyTerminal) Print(text);
      if(MQLInfoInteger(MQL_TESTER)) return;
      if(InpNotifyPush && !SendNotification(text))
         Print("CRT notification push failed: ",GetLastError());
      if(InpNotifySound && !PlaySound(InpNotificationSound))
         Print("CRT notification sound unavailable: ",InpNotificationSound);
     }
  };
#endif
