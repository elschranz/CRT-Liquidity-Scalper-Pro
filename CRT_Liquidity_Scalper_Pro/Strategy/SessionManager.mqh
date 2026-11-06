#ifndef CRT_SESSION_MANAGER_MQH
#define CRT_SESSION_MANAGER_MQH
#include "../Core/Config.mqh"

class CSessionManager
{
private:
   datetime DateHour(const int year,const int month,const int day,const int hour) const
   {
      MqlDateTime x={}; x.year=year; x.mon=month; x.day=day; x.hour=hour;
      return StructToTime(x);
   }
   int Sunday(const int year,const int month,const int ordinal) const
   {
      MqlDateTime x={}; TimeToStruct(DateHour(year,month,1,0),x);
      return 1+(7-x.day_of_week)%7+7*(ordinal-1);
   }
   int LastSunday(const int year,const int month) const
   {
      const int next=(month==12?1:month+1);
      datetime t=DateHour(year+(month==12?1:0),next,1,0)-86400;
      MqlDateTime x={}; TimeToStruct(t,x);
      return x.day-x.day_of_week;
   }
public:
   bool EUDST(const datetime utc) const
   {
      MqlDateTime x={}; TimeToStruct(utc,x);
      return utc>=DateHour(x.year,3,LastSunday(x.year,3),1) &&
             utc<DateHour(x.year,10,LastSunday(x.year,10),1);
   }
   bool USDST(const datetime utc) const
   {
      MqlDateTime x={}; TimeToStruct(utc,x);
      return utc>=DateHour(x.year,3,Sunday(x.year,3,2),7) &&
             utc<DateHour(x.year,11,Sunday(x.year,11,1),6);
   }
   int BrokerOffset(const datetime utc) const
   {
      bool summer=(InpBrokerDSTRule==BROKER_DST_EU?EUDST(utc):
                   (InpBrokerDSTRule==BROKER_DST_US?USDST(utc):false));
      return (summer?InpBrokerUTCSummerHours:InpBrokerUTCWinterHours)*3600;
   }
   datetime ToUTC(const datetime server) const
   {
      datetime utc=server-InpBrokerUTCWinterHours*3600;
      for(int i=0;i<3;i++) utc=server-BrokerOffset(utc);
      return utc;
   }
   datetime ToServer(const datetime utc) const { return utc+BrokerOffset(utc); }
   bool InHours(const datetime local,const int open,const int close) const
   {
      MqlDateTime x={}; TimeToStruct(local,x);
      if(x.day_of_week==0 || x.day_of_week==6) return false;
      if(open==close) return true;
      return (open<close?x.hour>=open && x.hour<close:x.hour>=open || x.hour<close);
   }
   bool London(const datetime server) const
   {
      datetime utc=ToUTC(server);
      return InHours(utc+(EUDST(utc)?3600:0),InpLondonOpenHour,InpLondonCloseHour);
   }
   bool NewYork(const datetime server) const
   {
      datetime utc=ToUTC(server);
      return InHours(utc+(USDST(utc)?-4:-5)*3600,InpNewYorkOpenHour,InpNewYorkCloseHour);
   }
   bool Allowed(const datetime server) const
   {
      bool london=InpLondonEnabled && London(server),ny=InpNewYorkEnabled && NewYork(server);
      return InpOverlapOnly?(london && ny):(london || ny);
   }
   string Name(const datetime server) const
   {
      if(London(server) && NewYork(server)) return "LONDON + NY";
      if(London(server)) return "LONDON";
      if(NewYork(server)) return "NEW YORK";
      return "OFF SESSION";
   }
   bool Valid() const
   {
      return MathAbs(InpBrokerUTCWinterHours)<=14 && MathAbs(InpBrokerUTCSummerHours)<=14 &&
             InpLondonOpenHour>=0 && InpLondonOpenHour<24 && InpLondonCloseHour>=0 && InpLondonCloseHour<24 &&
             InpNewYorkOpenHour>=0 && InpNewYorkOpenHour<24 && InpNewYorkCloseHour>=0 && InpNewYorkCloseHour<24 &&
             InpAsiaUTCOpenHour>=0 && InpAsiaUTCOpenHour<24 && InpAsiaUTCCloseHour>InpAsiaUTCOpenHour && InpAsiaUTCCloseHour<=24;
   }
};
#endif
