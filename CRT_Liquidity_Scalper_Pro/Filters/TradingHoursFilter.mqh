#ifndef CRT_TRADING_HOURS_FILTER_MQH
#define CRT_TRADING_HOURS_FILTER_MQH
#include "../Strategy/SessionManager.mqh"
class CTradingHoursFilter
{
private:
   CSessionManager m_sessions;
public:
   bool Allowed(const datetime server_time,string &reason)
   {
      if(!m_sessions.Allowed(server_time))
      { reason="Outside London/New York trading session"; return false; }
      return true;
   }
};
#endif
