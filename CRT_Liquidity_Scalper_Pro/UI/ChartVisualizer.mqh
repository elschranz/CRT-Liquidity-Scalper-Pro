#ifndef CRT_UI_CHART_VISUALIZER_MQH
#define CRT_UI_CHART_VISUALIZER_MQH
#include "../Core/Types.mqh"
#include "../Core/Config.mqh"
#include "../Core/Utilities.mqh"
#include "DashboardTheme.mqh"


class CChartVisualizer
  {
private:
   string m_prefix,m_current_id,m_namespace;
   string m_spaces[];
   datetime m_expiries[];
   bool m_visible,m_initialized;
   uint Hash(const string value)
     {
      uint h=2166136261;
      for(int i=0;i<StringLen(value);i++) h=(h^(uint)StringGetCharacter(value,i))*16777619;
      return h;
     }
   void Remove(const string prefix)
     {
      if(prefix=="") return;
      for(int i=ObjectsTotal(0,-1,-1)-1;i>=0;i--)
        {
         const string name=ObjectName(0,i,-1,-1);
         if(StringFind(name,prefix)==0) ObjectDelete(0,name);
        }
     }
   void Style(const string name,const color value,const bool fill=false)
     {
      ObjectSetInteger(0,name,OBJPROP_COLOR,value);
      ObjectSetInteger(0,name,OBJPROP_BACK,true);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
      ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_DOT);
      if((ENUM_OBJECT)ObjectGetInteger(0,name,OBJPROP_TYPE)==OBJ_RECTANGLE)
         ObjectSetInteger(0,name,OBJPROP_FILL,fill);
      ObjectSetInteger(0,name,OBJPROP_TIMEFRAMES,m_visible ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
     }
   void Point(const string name,const int anchor,const datetime time,const double price)
     {
      if((datetime)ObjectGetInteger(0,name,OBJPROP_TIME,anchor)!=time ||
         MathAbs(ObjectGetDouble(0,name,OBJPROP_PRICE,anchor)-price)>SymbolInfoDouble(CRTSymbol(),SYMBOL_POINT)*0.05)
         ObjectMove(0,name,anchor,time,price);
     }
   void Box(const string name,const datetime first,const double top,const datetime last,
            const double bottom,const color value,const bool fill)
     {
      if(ObjectFind(0,name)<0)
        {
         if(!ObjectCreate(0,name,OBJ_RECTANGLE,0,first,top,last,bottom)) return;
         Style(name,value,fill);
        }
      Point(name,0,first,top); Point(name,1,last,bottom);
     }
   void Line(const string suffix,const datetime first,const datetime last,
             const double price,const color value,const string caption)
     {
      if(price<=0)
        {
         ObjectDelete(0,m_namespace+suffix); ObjectDelete(0,m_namespace+suffix+".text"); return;
        }
      const string name=m_namespace+suffix;
      if(ObjectFind(0,name)<0)
        {
         if(!ObjectCreate(0,name,OBJ_TREND,0,first,price,last,price)) return;
         Style(name,value);
         ObjectSetInteger(0,name,OBJPROP_RAY_LEFT,false);
         ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
        }
      Point(name,0,first,price); Point(name,1,last,price);
      const string label=name+".text";
      if(ObjectFind(0,label)<0)
        {
         if(!ObjectCreate(0,label,OBJ_TEXT,0,last,price)) return;
         Style(label,value);
         ObjectSetInteger(0,label,OBJPROP_ANCHOR,ANCHOR_LEFT_LOWER);
         ObjectSetInteger(0,label,OBJPROP_FONTSIZE,8);
         ObjectSetString(0,label,OBJPROP_FONT,CRT_UI_FONT);
        }
      Point(label,0,last,price);
      if(ObjectGetString(0,label,OBJPROP_TEXT)!=caption)
         ObjectSetString(0,label,OBJPROP_TEXT,caption);
     }
   void Register(const string space,const datetime expiry)
     {
      int n=ArraySize(m_spaces);
      const int limit=MathMax(1,MathMin(64,InpChartMaximumSignals));
      if(n>=limit)
        {
         Remove(m_spaces[0]);
         for(int i=1;i<n;i++) { m_spaces[i-1]=m_spaces[i]; m_expiries[i-1]=m_expiries[i]; }
         n--;
         ArrayResize(m_spaces,n); ArrayResize(m_expiries,n);
        }
      ArrayResize(m_spaces,n+1); ArrayResize(m_expiries,n+1);
      m_spaces[n]=space; m_expiries[n]=expiry;
     }
public:
   CChartVisualizer(void) { m_visible=true; m_initialized=false; m_current_id=""; m_namespace=""; }
   void Init(void)
     {
      if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE)) return;
      m_prefix="CRTV."+IntegerToString((long)InpMagic)+"."+IntegerToString(ChartID())+".";
      m_visible=InpChartLevelsEnabled;
      if(GlobalVariableCheck(CRTKey("ui.levels"))) m_visible=GlobalVariableGet(CRTKey("ui.levels"))>0.5;
      m_initialized=true;
      Remove(m_prefix);
      ArrayResize(m_spaces,0); ArrayResize(m_expiries,0);
     }
   void Show(const SSignal &signal,const STradePlan &plan)
     {
      if(!m_initialized || signal.id=="" || signal.level<=0 || signal.reference_time<=0) return;
      if(signal.id!=m_current_id)
        {
         if(!InpChartKeepSignalHistory)
           {
            Remove(m_prefix); ArrayResize(m_spaces,0); ArrayResize(m_expiries,0);
           }
         m_current_id=signal.id;
         m_namespace=m_prefix+IntegerToString((long)Hash(signal.id))+".";
         Register(m_namespace,signal.expires_at);
        }
      if(signal.expires_at>0 && TimeCurrent()>=signal.expires_at) return;
      const datetime first=signal.reference_time;
      const datetime last=(signal.expires_at>signal.confirmed_at ? signal.expires_at :
                           signal.confirmed_at+15*60);
      Box(m_namespace+"range",first,signal.range_high,signal.confirmed_at,
          signal.range_low,CRT_UI_BORDER,false);
      const double area=MathMax(0.0,InpChartRetestAreaPips)*CRTPip(CRTSymbol());
      Box(m_namespace+"retest",signal.confirmed_at,signal.level+area,last,
          signal.level-area,CRT_UI_SURFACE,true);
      Line("level",first,last,signal.level,CRT_UI_ACCENT,
           (signal.direction==DIR_BUY ? "BUY" : "SELL")+" CRT");
      Line("entry",signal.confirmed_at,last,plan.entry,CRT_UI_TEXT,"ENTRY");
      Line("sl",signal.confirmed_at,last,plan.sl,CRT_UI_RED,"SL");
      Line("tp",signal.confirmed_at,last,plan.tp,CRT_UI_GREEN,
           "TP "+DoubleToString(plan.rr,1)+"R");
     }
   void Toggle(void)
     {
      if(!m_initialized) return;
      m_visible=!m_visible;
      GlobalVariableSet(CRTKey("ui.levels"),m_visible ? 1.0 : 0.0);
      GlobalVariablesFlush();
      for(int i=ObjectsTotal(0,-1,-1)-1;i>=0;i--)
        {
         const string name=ObjectName(0,i,-1,-1);
         if(StringFind(name,m_prefix)==0)
            ObjectSetInteger(0,name,OBJPROP_TIMEFRAMES,m_visible ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
        }
      ChartRedraw();
     }
   void ClearExpired(const datetime now)
     {
      for(int i=ArraySize(m_spaces)-1;i>=0;i--)
        {
         if(m_expiries[i]<=0 || now<m_expiries[i]) continue;
         Remove(m_spaces[i]);
         if(m_spaces[i]==m_namespace) { m_current_id=""; m_namespace=""; }
         const int n=ArraySize(m_spaces);
         for(int j=i+1;j<n;j++) { m_spaces[j-1]=m_spaces[j]; m_expiries[j-1]=m_expiries[j]; }
         ArrayResize(m_spaces,n-1); ArrayResize(m_expiries,n-1);
        }
     }
   void Destroy(void)
     {
      if(m_initialized) Remove(m_prefix);
      m_initialized=false; m_current_id=""; m_namespace="";
      ArrayResize(m_spaces,0); ArrayResize(m_expiries,0);
     }
  };
#endif
