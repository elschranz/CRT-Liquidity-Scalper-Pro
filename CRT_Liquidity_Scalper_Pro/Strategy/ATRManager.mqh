#ifndef CRT_ATR_MANAGER_MQH
#define CRT_ATR_MANAGER_MQH
#include "../Core/Config.mqh"
#include "../Core/Utilities.mqh"
class CATRManager
{
private:
   int m_handle;
   datetime m_bar;
   double m_pips;
public:
   CATRManager():m_handle(INVALID_HANDLE),m_bar(0),m_pips(0) {}
   bool Init()
   {
      if(InpATRPeriod<1) return false;
      m_handle=iATR(CRTSymbol(),PERIOD_M5,InpATRPeriod);
      return m_handle!=INVALID_HANDLE;
   }
   void Release() { if(m_handle!=INVALID_HANDLE) IndicatorRelease(m_handle); m_handle=INVALID_HANDLE; }
   bool Refresh()
   {
      datetime bar=iTime(CRTSymbol(),PERIOD_M5,1);
      if(bar==0 || m_handle==INVALID_HANDLE) return false;
      if(bar==m_bar && m_pips>0) return true;
      double values[1];
      if(BarsCalculated(m_handle)<InpATRPeriod+2 || CopyBuffer(m_handle,0,1,1,values)!=1 ||
         !MathIsValidNumber(values[0]) || values[0]<=0) return false;
      m_pips=CRTPips(CRTSymbol(),values[0]); m_bar=bar;
      return m_pips>0;
   }
   double Pips() const { return m_pips; }
};
#endif
