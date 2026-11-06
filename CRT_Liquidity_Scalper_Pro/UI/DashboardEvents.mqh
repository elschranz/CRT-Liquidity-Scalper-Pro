#ifndef CRT_UI_DASHBOARD_EVENTS_MQH
#define CRT_UI_DASHBOARD_EVENTS_MQH
// A UI confirmation only authorizes the requested action. Risk gates remain in the engine.
class CDashboardConfirmation
  {
private:
   string m_action;
   ulong m_deadline;
public:
   CDashboardConfirmation(void) { m_action=""; m_deadline=0; }
   bool Request(const string action)
     {
      const ulong now=GetTickCount64();
      if(m_action==action && now<=m_deadline)
        {
         m_action=""; m_deadline=0; return true;
        }
      m_action=action; m_deadline=now+5000; return false;
     }
   bool Pending(const string action)
     {
      if(GetTickCount64()>m_deadline) { m_action=""; m_deadline=0; }
      return m_action==action;
     }
   void Clear(void) { m_action=""; m_deadline=0; }
  };
#endif
