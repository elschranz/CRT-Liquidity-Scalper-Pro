#ifndef CRT_CORE_TYPES_MQH
#define CRT_CORE_TYPES_MQH
enum EDirection { DIR_SELL=-1, DIR_NONE=0, DIR_BUY=1 };
enum EEntryMode { ENTRY_AGGRESSIVE, ENTRY_CONFIRMED, ENTRY_BOTH_COMPARE };
enum ESLMode { SL_M5_ATR, SL_M1_ATR, SL_FIXED };
enum EManagementMode { FIXED_ADAPTIVE_TP, DELAYED_BREAK_EVEN, STRUCTURE_TRAILING_M1 };
enum EEngineState { IDLE,CRT_DETECTED,WAITING_RETEST,WAITING_M1_CONFIRMATION,ORDER_PENDING,POSITION_OPEN,SIGNAL_EXPIRED,PAUSED,RISK_LOCKED };
struct SSignal {
 string id,reason;
 EDirection direction;
 datetime reference_time,confirmed_at,expires_at,retest_time,m1_confirmation;
 double level,extreme,range_high,range_low,atr_pips,m1_extreme;
 bool active,retested,confirmed,consumed;
};
struct STradePlan {
 string signal_id;
 EDirection direction;
 EEntryMode mode;
 datetime created,expiration;
 double entry,sl,tp,rr,volume,risk_money,atr_pips,target_level;
 bool pending;
};
struct SRiskSnapshot {
 bool valid,locked;
 string reason;
 double balance,equity,daily_pnl,daily_dd,weekly_dd,total_dd,risk_reserved;
 int trades_today,losses;
};
struct SStatistics {
 int trades,wins,losses,r_samples;
 double net,gross_profit,gross_loss,pf,winrate,max_dd,expectancy_r,realized_rr;
};
struct SDashboardView {
 string state,reason,session,signal,news;
 double balance,equity,daily_pnl,daily_dd,weekly_dd,total_dd,risk_percent,spread,atr,sl_pips,rr,winrate,net,pf,expectancy_r;
 int trades,losses,closed_trades;
 EEntryMode entry_mode;
 bool paused,entries_enabled,risk_locked;
};
#endif
