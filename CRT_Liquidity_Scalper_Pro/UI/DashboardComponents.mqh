#ifndef CRT_UI_DASHBOARD_COMPONENTS_MQH
#define CRT_UI_DASHBOARD_COMPONENTS_MQH
#include "DashboardTheme.mqh"

void CRTUIInt(const string name,const ENUM_OBJECT_PROPERTY_INTEGER prop,const long value)
  {
   if(ObjectGetInteger(0,name,prop)!=value) ObjectSetInteger(0,name,prop,value);
  }
void CRTUIText(const string name,const string value)
  {
   if(ObjectGetString(0,name,OBJPROP_TEXT)!=value) ObjectSetString(0,name,OBJPROP_TEXT,value);
  }
bool CRTUIBase(const string name,const ENUM_OBJECT type,const int x,const int y,const int w,const int h)
  {
   if(ObjectFind(0,name)<0)
     {
      if(!ObjectCreate(0,name,type,0,0,0)) return false;
      ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_BACK,false);
      ObjectSetInteger(0,name,OBJPROP_ZORDER,100);
      if(type==OBJ_LABEL || type==OBJ_BUTTON) ObjectSetString(0,name,OBJPROP_FONT,CRT_UI_FONT);
     }
   CRTUIInt(name,OBJPROP_XDISTANCE,x);
   CRTUIInt(name,OBJPROP_YDISTANCE,y);
   if(type!=OBJ_LABEL)
     {
      CRTUIInt(name,OBJPROP_XSIZE,w);
      CRTUIInt(name,OBJPROP_YSIZE,h);
     }
   CRTUIInt(name,OBJPROP_TIMEFRAMES,OBJ_ALL_PERIODS);
   return true;
  }
bool CRTUIRect(const string name,const int x,const int y,const int w,const int h,const color bg)
  {
   if(!CRTUIBase(name,OBJ_RECTANGLE_LABEL,x,y,w,h)) return false;
   CRTUIInt(name,OBJPROP_BGCOLOR,bg);
   CRTUIInt(name,OBJPROP_COLOR,CRT_UI_BORDER);
   CRTUIInt(name,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   return true;
  }
bool CRTUILabel(const string name,const string value,const int x,const int y,
                const color fg=CRT_UI_TEXT,const int size=9)
  {
   if(!CRTUIBase(name,OBJ_LABEL,x,y,0,0)) return false;
   CRTUIInt(name,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
   CRTUIInt(name,OBJPROP_COLOR,fg);
   CRTUIInt(name,OBJPROP_FONTSIZE,size);
   CRTUIText(name,value);
   return true;
  }
bool CRTUIButton(const string name,const string value,const int x,const int y,
                 const int w,const int h,const color bg=CRT_UI_RAISED,
                 const color fg=CRT_UI_TEXT,const int size=8)
  {
   if(!CRTUIBase(name,OBJ_BUTTON,x,y,w,h)) return false;
   CRTUIInt(name,OBJPROP_BGCOLOR,bg);
   CRTUIInt(name,OBJPROP_BORDER_COLOR,CRT_UI_BORDER);
   CRTUIInt(name,OBJPROP_COLOR,fg);
   CRTUIInt(name,OBJPROP_FONTSIZE,size);
   CRTUIInt(name,OBJPROP_ZORDER,102);
   CRTUIText(name,value);
   return true;
  }
void CRTUIHide(const string name)
  {
   if(ObjectFind(0,name)>=0) CRTUIInt(name,OBJPROP_TIMEFRAMES,OBJ_NO_PERIODS);
  }
string CRTUITrim(const string value,const int length)
  {
   if(StringLen(value)<=length) return value;
   return StringSubstr(value,0,MathMax(0,length-3))+"...";
  }
#endif
