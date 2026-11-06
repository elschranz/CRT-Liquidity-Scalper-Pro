#ifndef CRT_DAILY_LIMITS_MQH
#define CRT_DAILY_LIMITS_MQH
#include "../Core/Config.mqh"
#include "PropFirmManager.mqh"
class CDailyLimits
{
public:
   datetime DayStart(const datetime now)
   {
      MqlDateTime t; TimeToStruct(now-InpRiskResetHourServer*3600,t);
      t.hour=0; t.min=0; t.sec=0;
      return StructToTime(t)+InpRiskResetHourServer*3600;
   }
   datetime WeekStart(const datetime now)
   {
      const datetime day=DayStart(now);
      MqlDateTime t; TimeToStruct(day-InpRiskResetHourServer*3600,t);
      const int monday_offset=(t.day_of_week+6)%7;
      return day-monday_offset*86400;
   }
};
#endif
