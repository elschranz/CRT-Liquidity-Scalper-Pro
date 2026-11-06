#ifndef CRT_UI_DASHBOARD_MQH
#define CRT_UI_DASHBOARD_MQH
#include "../Core/Types.mqh"
#include "../Core/Config.mqh"
#include "../Core/Utilities.mqh"
#include "DashboardComponents.mqh"
#include "DashboardEvents.mqh"
#include "../Risk/PropFirmManager.mqh"


class CDashboard
  {
private:
   string m_prefix;
   int m_x,m_y,m_width,m_tab,m_chart_width,m_chart_height;
   bool m_minimized,m_auto_minimized,m_initialized,m_have_view;
   SDashboardView m_view;
   CDashboardConfirmation m_confirm;
   string N(const string suffix) { return m_prefix+suffix; }
   void SaveLayout(void)
     {
      GlobalVariableSet(CRTKey("ui.x"),m_x);
      GlobalVariableSet(CRTKey("ui.y"),m_y);
      GlobalVariableSet(CRTKey("ui.min"),m_minimized ? 1.0 : 0.0);
      GlobalVariableSet(CRTKey("ui.tab"),m_tab);
      GlobalVariablesFlush();
     }
   void HideChildren(void)
     {
      for(int i=ObjectsTotal(0,-1,-1)-1;i>=0;i--)
        {
         const string name=ObjectName(0,i,-1,-1);
         if(StringFind(name,m_prefix)==0) CRTUIHide(name);
        }
     }
   void Geometry(void)
     {
      m_chart_width=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS,0);
      m_chart_height=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0);
      m_width=MathMin(MathMax(300,InpDashboardWidth),MathMax(180,m_chart_width-16));
      m_auto_minimized=(m_chart_height<556 || m_width<300);
      const int h=(m_minimized || m_auto_minimized) ? 76 : 538;
      m_x=MathMax(4,MathMin(m_x,MathMax(4,m_chart_width-m_width-8)));
      m_y=MathMax(4,MathMin(m_y,MathMax(4,m_chart_height-h-8)));
     }
   void Pair(const string key,const string caption,const string value,const int col,
             const int row,const color fg=CRT_UI_TEXT)
     {
      const int cell=(m_width-30)/2;
      const int xx=m_x+12+col*(cell+6);
      const int yy=m_y+76+row*34;
      CRTUILabel(N(key+".label"),caption,xx,yy,CRT_UI_MUTED,8);
      CRTUILabel(N(key+".value"),value,xx,yy+13,fg,MathMax(8,InpDashboardFontSize));
     }
   void Detail(const int index,const string text,const color fg=CRT_UI_MUTED)
     {
      CRTUILabel(N("detail"+IntegerToString(index)),CRTUITrim(text,(m_width-24)/6),
                 m_x+12,m_y+281+index*17,fg,8);
     }
   void Render(void)
     {
      if(!m_initialized || !InpDashboardEnabled) return;
      const bool mini=m_minimized || m_auto_minimized;
      CRTUIRect(N("shell"),m_x,m_y,m_width,mini ? 76 : 538,CRT_UI_BG);
      CRTUILabel(N("title"),"CRT SCALPER PRO",m_x+12,m_y+10,CRT_UI_TEXT,10);
      CRTUIInt(N("title"),OBJPROP_SELECTABLE,true);
      CRTUIInt(N("title"),OBJPROP_ZORDER,103);
      ObjectSetString(0,N("title"),OBJPROP_TOOLTIP,"Arrastre el titulo para mover el panel");
      CRTUILabel(N("subtitle"),CRTSymbol()+"  M5 > M1",m_x+12,m_y+28,CRT_UI_MUTED,8);
      CRTUIButton(N("min"),mini ? "+" : "-",m_x+m_width-34,m_y+10,22,22);
      const color status_color=m_view.risk_locked ? CRT_UI_RED :
                               ((m_view.paused || StringFind(m_view.state,"NEWS")>=0) ? CRT_UI_ACCENT : CRT_UI_GREEN);
      CRTUILabel(N("status"),CRTUITrim(m_have_view ? m_view.state : "INITIALIZING",
                 (m_width-24)/7),m_x+12,m_y+50,status_color,9);
      if(mini) return;

      Pair("balance","BALANCE",DoubleToString(m_view.balance,2),0,0);
      Pair("equity","EQUITY",DoubleToString(m_view.equity,2),1,0);
      Pair("pnl","P&L DIARIO",DoubleToString(m_view.daily_pnl,2),0,1,
           m_view.daily_pnl<0 ? CRT_UI_RED : CRT_UI_GREEN);
      Pair("dd","DD DIARIO",DoubleToString(m_view.daily_dd,2)+"%",1,1,
           m_view.risk_locked ? CRT_UI_RED : CRT_UI_TEXT);
      Pair("risk","RIESGO",DoubleToString(m_view.risk_percent,2)+"%",0,2,CRT_UI_ACCENT);
      Pair("spread","SPREAD",DoubleToString(m_view.spread,2)+" pip",1,2);
      Pair("atr","ATR M5",DoubleToString(m_view.atr,2)+" pip",0,3);
      Pair("stop","SL / RR",DoubleToString(m_view.sl_pips,2)+" pip / "+
           DoubleToString(m_view.rr,1)+"R",1,3);
      Pair("session","SESION",CRTUITrim(m_view.session,22),0,4);
      Pair("trades","TRADES / PERDIDAS",IntegerToString(m_view.trades)+" / "+
           IntegerToString(m_view.losses),1,4);

      string tabs[5]={"OVERVIEW","STRATEGY","RISK","PERFORMANCE","SETTINGS"};
      const int tabw=(m_width-24)/5;
      for(int i=0;i<5;i++)
         CRTUIButton(N("tab"+IntegerToString(i)),tabs[i],m_x+12+i*tabw,m_y+249,
                     tabw-2,23,i==m_tab ? CRT_UI_ACCENT_DARK : CRT_UI_SURFACE,CRT_UI_TEXT,7);
      const string mode=m_view.entry_mode==ENTRY_AGGRESSIVE ? "AGGRESSIVE" :
                        (m_view.entry_mode==ENTRY_CONFIRMED ? "CONFIRMED" : "BOTH COMPARE");
      if(m_tab==0)
        {
         Detail(0,"Modo: "+mode+" | Entradas: "+(m_view.entries_enabled ? "ON" : "OFF"));
         Detail(1,"Ultima senal: "+m_view.signal);
         Detail(2,"Noticias: "+m_view.news);
        }
      else if(m_tab==1)
        {
         Detail(0,"CRT M5 cerrado > retest M1 | "+mode);
         Detail(1,"ATR "+DoubleToString(m_view.atr,2)+" | SL "+DoubleToString(m_view.sl_pips,2)+" pip");
         Detail(2,"Senal: "+m_view.signal);
        }
      else if(m_tab==2)
        {
         Detail(0,"DD semana "+DoubleToString(m_view.weekly_dd,2)+"% | Total "+
                   DoubleToString(m_view.total_dd,2)+"%");
         Detail(1,"Techo riesgo "+DoubleToString(InpRiskCeilingPercent,2)+"% | Bloqueo "+
                   (m_view.risk_locked ? "ACTIVO" : "NO"),m_view.risk_locked ? CRT_UI_RED : CRT_UI_MUTED);
         Detail(2,"La UI no resetea limites ni bloqueos");
        }
      else if(m_tab==3)
        {
         Detail(0,"Reales "+IntegerToString(m_view.closed_trades)+" | WR "+
                   DoubleToString(m_view.winrate,1)+"% | Neto "+DoubleToString(m_view.net,2));
         Detail(1,"PF "+DoubleToString(m_view.pf,2)+" | Esperanza "+
                   DoubleToString(m_view.expectancy_r,2)+"R");
         if(m_view.comparing)
            Detail(2,"A "+IntegerToString(m_view.virtual_a_closed)+"/"+
                      DoubleToString(m_view.virtual_a_r,2)+"R | B "+
                      IntegerToString(m_view.virtual_b_closed)+"/"+
                      DoubleToString(m_view.virtual_b_r,2)+"R (virtual)");
         else Detail(2,"Solo reales");
        }
      else
        {
         Detail(0,"Riesgo rapido (respetando techo):");
         Detail(1,"");
         Detail(2,"Drag: titulo | Layout persistente");
         const int rw=(m_width-28)/3;
         CRTUIButton(N("risk010"),"0.10%",m_x+12,m_y+297,rw-3,19);
         CRTUIButton(N("risk025"),"0.25%",m_x+12+rw,m_y+297,rw-3,19);
         CRTUIButton(N("risk050"),"0.50%",m_x+12+rw*2,m_y+297,rw-3,19);
        }
      if(m_tab!=4)
        {
         CRTUIHide(N("risk010")); CRTUIHide(N("risk025")); CRTUIHide(N("risk050"));
        }
      CRTUILabel(N("reason.label"),"ESTADO / MOTIVO",m_x+12,m_y+337,CRT_UI_MUTED,8);
      CRTUILabel(N("reason"),CRTUITrim(m_view.reason,(m_width-24)/6),m_x+12,m_y+352,
                 m_view.risk_locked ? CRT_UI_RED : CRT_UI_TEXT,8);
      ObjectSetString(0,N("reason"),OBJPROP_TOOLTIP,m_view.reason);
      const double dd_ratio=MathMax(0.0,MathMin(1.0,m_view.daily_dd/MathMax(0.001,InpDailyLossLimitPercent)));
      CRTUIRect(N("dd.track"),m_x+12,m_y+370,m_width-24,3,CRT_UI_SURFACE);
      CRTUIRect(N("dd.progress"),m_x+12,m_y+370,MathMax(1,(int)((m_width-24)*dd_ratio)),
                3,dd_ratio>=1.0 ? CRT_UI_RED : CRT_UI_ACCENT);
      const int half=(m_width-30)/2;
      CRTUIButton(N("pause"),m_view.paused ? "START" : "PAUSE",m_x+12,m_y+377,half,25,
                  m_view.paused ? CRT_UI_ACCENT_DARK : CRT_UI_RAISED);
      CRTUIButton(N("entries"),m_view.entries_enabled ? "DISABLE ENTRIES" : "ENABLE ENTRIES",
                  m_x+18+half,m_y+377,half,25,CRT_UI_RAISED,
                  m_view.risk_locked ? CRT_UI_MUTED : CRT_UI_TEXT);
      CRTUIButton(N("aggressive"),"AGGRESSIVE",m_x+12,m_y+409,half,25,
                  m_view.entry_mode==ENTRY_AGGRESSIVE ? CRT_UI_ACCENT_DARK : CRT_UI_RAISED);
      CRTUIButton(N("confirmed"),"CONFIRMED",m_x+18+half,m_y+409,half,25,
                  m_view.entry_mode==ENTRY_CONFIRMED ? CRT_UI_ACCENT_DARK : CRT_UI_RAISED);
      const int third=(m_width-36)/3;
      CRTUIButton(N("cancel"),m_confirm.Pending("CANCEL_PENDING") ? "CONFIRM CANCEL" : "CANCEL PEND.",
                  m_x+12,m_y+441,third,25,CRT_UI_RAISED,CRT_UI_ACCENT,7);
      CRTUIButton(N("close"),m_confirm.Pending("CLOSE_POSITIONS") ? "CONFIRM CLOSE" : "CLOSE OWN",
                  m_x+18+third,m_y+441,third,25,CRT_UI_RAISED,CRT_UI_RED,7);
      CRTUIButton(N("be"),"MOVE TO BE",m_x+24+third*2,m_y+441,third,25,CRT_UI_RAISED,CRT_UI_TEXT,7);
      CRTUILabel(N("confirm.hint"),
                 (m_confirm.Pending("CANCEL_PENDING") || m_confirm.Pending("CLOSE_POSITIONS")) ?
                 "Segundo clic en 5 s para confirmar" : "Acciones aplicadas solo al EA / magic",
                 m_x+12,m_y+475,CRT_UI_MUTED,8);
      CRTUIButton(N("levels"),"LEVELS ON/OFF",m_x+12,m_y+505,third,23,CRT_UI_SURFACE,CRT_UI_TEXT,7);
      CRTUIButton(N("stats"),"STATS ON/OFF",m_x+18+third,m_y+505,third,23,CRT_UI_SURFACE,CRT_UI_TEXT,7);
      CRTUIButton(N("reset"),"RESET LAYOUT",m_x+24+third*2,m_y+505,third,23,CRT_UI_SURFACE,CRT_UI_TEXT,7);
     }
public:
   CDashboard(void)
     {
      m_x=16; m_y=16; m_width=390; m_tab=0;
      m_chart_width=0; m_chart_height=0; m_minimized=false; m_auto_minimized=false;
      m_initialized=false; m_have_view=false; ZeroMemory(m_view);
     }
   bool Init(void)
     {
      if(!InpDashboardEnabled || (MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE))) return true;
      m_prefix="CRTUI."+IntegerToString((long)InpMagic)+"."+IntegerToString(ChartID())+".";
      m_minimized=InpDashboardStartMinimized;
      const int cw=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS,0);
      m_x=MathMax(4,cw-MathMax(300,InpDashboardWidth)-16);
      if(GlobalVariableCheck(CRTKey("ui.x"))) m_x=(int)GlobalVariableGet(CRTKey("ui.x"));
      if(GlobalVariableCheck(CRTKey("ui.y"))) m_y=(int)GlobalVariableGet(CRTKey("ui.y"));
      if(GlobalVariableCheck(CRTKey("ui.min"))) m_minimized=GlobalVariableGet(CRTKey("ui.min"))>0.5;
      if(GlobalVariableCheck(CRTKey("ui.tab"))) m_tab=(int)GlobalVariableGet(CRTKey("ui.tab"));
      m_tab=MathMax(0,MathMin(4,m_tab));
      Geometry(); m_initialized=true; Render(); ChartRedraw();
      return ObjectFind(0,N("shell"))>=0;
     }
   void Update(const SDashboardView &view)
     {
      m_view=view; m_have_view=true;
      if(!InpDashboardEnabled || !m_initialized) return;
      const int cw=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS,0);
      const int ch=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0);
      if(cw!=m_chart_width || ch!=m_chart_height) { HideChildren(); Geometry(); }
      Render();
     }
   string Event(const int id,const long lparam,const double dparam,const string sparam)
     {
      if(!m_initialized || !InpDashboardEnabled) return "";
      if(id==CHARTEVENT_CHART_CHANGE)
        {
         HideChildren(); Geometry(); Render(); return "";
        }
      if(id==CHARTEVENT_OBJECT_DRAG && sparam==N("title"))
        {
         m_x=(int)ObjectGetInteger(0,N("title"),OBJPROP_XDISTANCE)-12;
         m_y=(int)ObjectGetInteger(0,N("title"),OBJPROP_YDISTANCE)-10;
         ObjectSetInteger(0,N("title"),OBJPROP_SELECTED,false);
         Geometry(); SaveLayout(); Render(); ChartRedraw(); return "";
        }
      if(id!=CHARTEVENT_OBJECT_CLICK || StringFind(sparam,m_prefix)!=0) return "";
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      const string key=StringSubstr(sparam,StringLen(m_prefix));
      string action="";
      if(key=="min")
        {
         m_minimized=!m_minimized; HideChildren(); Geometry(); SaveLayout(); Render();
         return "MINIMIZE";
        }
      if(StringFind(key,"tab")==0)
        {
         m_tab=MathMax(0,MathMin(4,(int)StringToInteger(StringSubstr(key,3))));
         SaveLayout(); Render(); return "";
        }
      if(key=="reset")
        {
         m_tab=0; m_minimized=InpDashboardStartMinimized;
         m_x=MathMax(4,m_chart_width-MathMax(300,InpDashboardWidth)-16); m_y=16;
         HideChildren(); Geometry(); SaveLayout(); Render(); return "RESET";
        }
      if(key=="stats")
        {
         m_tab=(m_tab==3 ? 0 : 3); SaveLayout(); Render(); return "STATS";
        }
      if(key=="close" || key=="cancel")
        {
         action=(key=="close" ? "CLOSE_POSITIONS" : "CANCEL_PENDING");
         if(!m_confirm.Request(action)) { Render(); return ""; }
         Render(); return action;
        }
      m_confirm.Clear();
      if(key=="pause") action="START_PAUSE";
      else if(key=="entries")
        {
         if(m_view.risk_locked && !m_view.entries_enabled) return "";
         action="TOGGLE_ENTRIES";
        }
      else if(key=="aggressive") action="ENTRY_AGGRESSIVE";
      else if(key=="confirmed") action="ENTRY_CONFIRMED";
      else if(key=="be") action="BE";
      else if(key=="levels") action="LEVELS";
      else if(key=="risk010" && InpRiskCeilingPercent>=0.10) action="RISK_010";
      else if(key=="risk025" && InpRiskCeilingPercent>=0.25) action="RISK_025";
      else if(key=="risk050" && InpRiskCeilingPercent>=0.50) action="RISK_050";
      Render();
      return action;
     }
   void Destroy(void)
     {
      if(!m_initialized) return;
      SaveLayout();
      for(int i=ObjectsTotal(0,-1,-1)-1;i>=0;i--)
        {
         const string name=ObjectName(0,i,-1,-1);
         if(StringFind(name,m_prefix)==0) ObjectDelete(0,name);
        }
      m_initialized=false; ChartRedraw();
     }
  };
#endif
