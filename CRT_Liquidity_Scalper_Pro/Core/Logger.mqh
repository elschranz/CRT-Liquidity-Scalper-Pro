#ifndef CRT_CORE_LOGGER_MQH
#define CRT_CORE_LOGGER_MQH
#include "Utilities.mqh"
class CLogger {
 private:
 string m_last;
 datetime m_time;
 public:
 CLogger():m_last(""),m_time(0) {}
 void Write(const string event,const string message) {
  string text=event+": "+message;
  if(text==m_last && TimeCurrent()-m_time<60) return;
  m_last=text; m_time=TimeCurrent();
  Print("[CRT ",InpMagic,"] ",text);
 }
};
#endif
