# CRT Liquidity Scalper Pro — Instrucciones para Codex

## Misión
Desarrolla directamente un Expert Advisor COMPLETO, modular y compilable para MetaTrader 5 en MQL5 llamado `CRT_Liquidity_Scalper_Pro`. El mercado inicial es EURUSD. Detecta CRT / barridas de liquidez en velas M5 **cerradas**, refina y ejecuta en M1 mediante dos modos (agresivo y confirmado), calcula stops estructurales con ATR, objetivos por liquidez con RR adaptativo, y gestiona riesgo de cuentas fondeadas. Incluye un dashboard atractivo, compacto y usable por muchas horas. No entregues solo un archivo .mq5 ni pseudocódigo: genera `.mq5` principal y módulos `.mqh` con lógica real, documentación y plan de pruebas. No supongas rentabilidad ni inventes pruebas.

## Ejecución del trabajo
1. Crea la estructura de carpetas y todos los archivos de proyecto.
2. Implementa todos los componentes de manera integrada, sin stubs ni botones decorativos.
3. Compila con MetaEditor si está disponible y corrige errores y advertencias relevantes. Si no puedes compilar, indica explícitamente qué no se validó y facilita instrucciones para compilar.
4. Genera `README.md` y `Tests/TestPlan.md` y registra limitaciones.
5. No te detengas en una propuesta de arquitectura; escribe el código directamente. No solicites aprobaciones intermedias salvo un bloqueo real.

## Arquitectura modular
Organiza el proyecto (puedes adaptar nombres para resolver dependencias):

```text
CRT_Liquidity_Scalper_Pro/
  CRT_Liquidity_Scalper_Pro.mq5
  Core/Config.mqh
  Core/Types.mqh
  Core/StateManager.mqh
  Core/Logger.mqh
  Core/Utilities.mqh
  Strategy/CRTDetector.mqh
  Strategy/LiquidityDetector.mqh
  Strategy/M1EntryEngine.mqh
  Strategy/AggressiveEntry.mqh
  Strategy/ConfirmedEntry.mqh
  Strategy/ATRManager.mqh
  Strategy/DynamicTargets.mqh
  Strategy/SessionManager.mqh
  Trading/TradeExecutor.mqh
  Trading/OrderManager.mqh
  Trading/PositionManager.mqh
  Trading/LotCalculator.mqh
  Trading/ExecutionValidator.mqh
  Risk/RiskManager.mqh
  Risk/DrawdownManager.mqh
  Risk/PropFirmManager.mqh
  Risk/DailyLimits.mqh
  Filters/SpreadFilter.mqh
  Filters/VolatilityFilter.mqh
  Filters/NewsFilter.mqh
  Filters/TradingHoursFilter.mqh
  Management/BreakEvenManager.mqh
  Management/TrailingManager.mqh
  UI/Dashboard.mqh
  UI/DashboardTheme.mqh
  UI/DashboardComponents.mqh
  UI/DashboardEvents.mqh
  UI/ChartVisualizer.mqh
  UI/Notifications.mqh
  Analytics/Statistics.mqh
  Analytics/TradeJournal.mqh
  Analytics/BacktestMetrics.mqh
  Tests/TestPlan.md
  README.md
```

Usa clases cuando aporten claridad, dependencias acíclicas, guardas de inclusión y prefijos únicos para objetos de gráfico y archivos de persistencia. Evita dependencias externas y DLL. MQL5 nativo con `CTrade`, handles de indicadores y API gráfica nativa / Canvas si conviene.

## Detección CRT en M5: reglas estrictas
Utiliza dos velas **cerradas** consecutivas: vela 1 (`H1`,`L1`) y vela 2 manipuladora. Una señal se genera solo una vez por cierre de vela M5 y recibe ID único.

- **Compra:** `Low2 < L1 - MinSweepPips` y `Close2 > L1` y `Close2 < H1`, sin romper a la vez `H1`; exigir mecha mínima de barrida, guardar extremo `Low2`, nivel `L1`, momento de confirmación y dirección BUY.
- **Venta:** `High2 > H1 + MinSweepPips` y `Close2 < H1` y `Close2 > L1`, sin romper `L1`; guardar `High2`, nivel `H1`, momento y dirección SELL.
- Parámetros iniciales: `MinSweepPips=0.2`, `MinWickPips=0.3`, `RejectDoubleSidedSweep=true`, `MaxSignalAgeMinutes=15`, `CRTTimeframe=PERIOD_M5`.
- Se deben usar solo velas y niveles conocidos en ese instante: nada de repaint ni look-ahead. Rechaza casos degenerados y datos incompletos.

### Liquidez opcional
Detecta máximos/mínimos recientes, pivotes confirmados, equal highs/lows con tolerancia y contactos mínimos, extremos de Asia y Londres y máximos/mínimos del día previo. Los horarios deben manejar bien servidor y DST. Configura modos: CRT puro (predeterminado), CRT + liquidez estructural, CRT + liquidez sesión, CRT + equal highs/lows, CRT + cualquiera. Los niveles históricos deben estar confirmados antes de la señal; marca niveles consumidos o invalidados y no los reutilices.

## Entrada M1 — Dos modos
Tras confirmar el CRT M5, supervisa M1/ticks hasta expiración.

### A. AGGRESSIVE_RETEST
- Compra: colocar **Buy Limit** en `L1 + EntryOffsetPips` (predeterminado 0.1 pip), siempre que sea una orden válida debajo del Ask actual. Venta: **Sell Limit** en `H1 - EntryOffsetPips`, encima del Bid actual.
- No exigir CHoCH, FVG ni confirmación adicional. No transformar retroactivamente una Limit inválida en una orden de mercado.
- Expira tras `PendingExpirationMinutes=15`; cancelar si se rompe el extremo de manipulación antes de ejecución o si el target se alcanzó antes de la entrada. Una pendiente por señal, sin duplicados.

### B. CONFIRMED_M1_RETEST
- Espera retorno real a nivel/área M5 (bid/ask según dirección). Después exige **vela M1 completamente cerrada** que haya tocado/rechazado nivel y cerrado a favor: por encima para compra, por debajo para venta, con distancia mínima configurable.
- Parámetros iniciales `MinRejectionWickPips=0.2`, `MinM1CloseBeyondLevelPips=0.1`, `MaximumChaseDistancePips=1.0`, `ConfirmationExpirationMinutes=15`.
- Entra a mercado al primer tick elegible tras la confirmación, solo si spread, distancia de persecución, riesgo y otras validaciones siguen siendo correctas.

Selector `ENTRY_AGGRESSIVE`, `ENTRY_CONFIRMED`, `ENTRY_BOTH_COMPARE`. `BOTH_COMPARE` registra resultados hipotéticos por separado y únicamente ejecuta una modalidad real elegida por parámetro; no duplica riesgo ni órdenes. Separar operaciones virtuales de reales en estadísticas.

## SL adaptativo M5/M1 y ATR
- ATR sobre M5, periodo 14, **última vela cerrada**, expresado en pips correctamente según símbolo/dígitos.
- Para BUY, invalida debajo de Low2 menos buffer; SELL por encima de High2 más buffer. Calcula SL estructural desde el **precio previsto/ejecutable**, más un ATR mínimo opcional.
- Fórmula de distancia `max(distancia_estructural, ATR_M5_Pips * ATRMultiplier, MinimumSLPips)`, con `ATRMultiplier=0.45`, `MinimumSLPips=0.7`, `MaximumSLPips=3.0`, `StructuralBufferPips=0.2`.
- Si distancia necesaria supera máximo, **descarta** la operación, nunca recortes el SL que invalida estructura. Valida `stops level`, `freeze level` y tick size del broker; si no caben, descarta. No amplíes SL tras abrir.
- Selector: SL estructura M5+ATR (por defecto), SL microestructura M1 confirmada+ATR (experimental), SL fijo (comparación). Documenta que un SL extremadamente estrecho puede ser no ejecutable y sensible al spread/slippage.

## TP dinámico según liquidez y RR
- Busca el siguiente objetivo **preexistente y válido** en dirección operación: swing confirmado, extremo de sesión, equal high/low, etc. No uses futuros ni inventes niveles.
- Distancia efectiva objetivo = distancia al nivel * (1 - `LiquidityTargetMarginPercent/100`), predeterminado 10%.
- `AvailableRR = EffectiveTargetDistance / ActualRiskDistance`.
- Elige el mayor de `{9R,7R,5R,3R}` que esté por debajo del disponible. Sin >=3R, descarta operación. Parámetros `DynamicTPEnabled=true`, `MinimumRR=3`, `MaximumRR=9`, `AllowFallbackTarget=false`, `FallbackFixedRR=3`.
- Modo opcional RR fijo para comparar. Recalcula al precio real ejecutado y valida stop/target y costes. Si la ejecución invalida requisitos, aplica política de seguridad documentada sin asumir que un cierre instantáneo evita pérdida.

## Riesgo profesional y cuentas fondeadas
- `RiskPerTradePercent=0.25`, techo 0.50%, cálculo sobre balance/equity configurable. Dimensiona lote por **pérdida real monetaria prevista**, preferiblemente `OrderCalcProfit`, considerando divisa cuenta, costes estimados, volume min/max/step, margen `OrderCalcMargin` y precio real de SL. Redondea volumen hacia abajo, nunca incrementes riesgo para alcanzar lote mínimo.
- Límites: pérdida diaria interna 0.75%, semanal 2%, tres pérdidas consecutivas, tres trades/día, una posición y una pendiente a la vez, agregación del riesgo de pendientes y posiciones, y reserva de pérdidas flotantes.
- Modelos configurables: DD fijo, trailing, basado en balance/equity y high-water equity. Persistir referencia de DD, reset horario y bloqueos tras reinicios. Si no hay datos fiables, bloquear entradas (fail closed).
- Al alcanzar límite: deshabilitar entradas y cancelar pendientes propias; dejar posiciones abiertas salvo configuración explícita de cierre. No tocar posiciones ajenas salvo opt-in independiente de protección global. No martingala, grid ni promediar pérdidas.
- Filtros: spread máximo 0.3 pip por defecto; rango ATR mínimo/máximo; sesiones Londres / NY y solapamiento; noticias EUR/USD alto impacto con bloqueo 15 minutos antes y después. Priorizar calendario MQL5 nativo, indicar cuando no hay calendario, y política configurable de bloqueo seguro.
- Las protecciones deben funcionar incluso si el panel está oculto, y no pueden resetearse por reiniciar terminal o botón de UI.

## Gestión de operaciones
Tres modos de gestión con backtest comparativo:
1. `FIXED_ADAPTIVE_TP` predeterminado, sin BE ni trailing ni parciales.
2. `DELAYED_BREAK_EVEN` con disparador 3R configurable y buffer para costes.
3. `STRUCTURE_TRAILING_M1` con pivotes confirmados y buffer opcional ATR, nunca retroceder SL.
Parciales opcionales, **desactivados por defecto**. No incrementar riesgo ni sobreoperar durante cierres o modificaciones.

## Dashboard moderno y limpio
Diseña UI nativa MT5, legible tras horas de uso, compacta, responsiva, minimizable, arrastrable, con posición persistente. Posición inicial esquina superior derecha. Sin saturar gráfico.

**Paleta**: fondo #111820, superficies #1D2730 y #26323D, texto #F2F4F7, secundario #9CA8B4, naranja acento #F59E0B/#D97706, verde #43B581, rojo #E35D6A, bordes #34404B. Espaciado regular, jerarquía tipográfica, alineación fina, estados claros.

**Cabecera**: CRT SCALPER PRO · EURUSD M5 → M1, estado (ACTIVE, WAITING CRT, WAITING RETEST, CONFIRMED, POSITION OPEN, PAUSED, RISK LOCKED, NEWS BLOCK).

**Panel compacto**: balance, equity, P&L diario, DD diario/progreso, riesgo, spread, ATR M5, SL propuesto, RR elegido, modo entrada, sesión, trades del día y pérdidas consecutivas. Muestra estado de última señal y razones de descarte.

**Botones de verdad** con `OnChartEvent`: START/PAUSE, AGGRESSIVE/CONFIRMED, ENABLE/DISABLE ENTRIES, CANCEL OWN PENDINGS, CLOSE OWN POSITIONS (doble confirmación), MOVE TO BE (si válido), MINIMIZE, LEVELS ON/OFF, STATS ON/OFF, RESET LAYOUT. Selector rápido riesgo 0.10/0.25/0.50% limitado por techo. Nunca permitir que los botones eludan un bloqueo de riesgo. Pestañas expandidas OVERVIEW / STRATEGY / RISK / PERFORMANCE / SETTINGS. Confirmación para acciones destructivas.

**Gráfico minimalista**: cajas CRT discretas, línea naranja nivel barrido, área de retest, línea de entrada, SL/TP, pequeñas etiquetas dirección y RR. Eliminar objetos expirados/mitigados; permitir ocultar niveles e historial; no borrar objetos manuales. Actualizar solo lo necesario sin flicker, no recrear cada tick, y no tapar velas.

**Notificaciones** configurables: CRT, retest, confirmación, orden, llenado, cierre, SL, TP, bloqueos y errores; terminal, push MT5 si configurado, sonido opcional; deduplicar.

## Estadística y journal
Registrar en CSV y visualizar: winrate, beneficio neto, PF, DD máximo, esperanza en R, RR realizado, rachas, resultado por sesión, RR, ATR y modo entrada. Por cada señal conservar ID/hora, nivel, tipo, extremos, ATR, modo, entrada prevista/real, SL, TP, spread, comisión, slippage estimado/observado cuando exista, MFE, MAE, tiempo hasta retest, motivo de descarte/cierre. Separar datos reales y virtuales. No prometer métricas que no puedas calcular de manera fiable.

## Seguridad de ejecución MT5
- Magic Number único; órdenes solo propias por defecto; soportar netting/hedging sin mezclar posiciones ajenas accidentalmente.
- Validar trading permitido, conexión, sesión, spread, liquidez, volumen, margen, `SYMBOL_TRADE_STOPS_LEVEL`, `SYMBOL_TRADE_FREEZE_LEVEL`, tick size.
- Usar `CTrade`, comprobar retcodes reales tras cada solicitud, y `OnTradeTransaction` para reconciliar estados. Los retornos `true` no demuestran ejecución.
- Reintentos controlados e idempotentes; jamás duplicar por respuesta incierta. Tratamiento de ejecución parcial, rechazos, desconexiones y reinicios.
- Máquina de estados `IDLE`, `CRT_DETECTED`, `WAITING_RETEST`, `WAITING_M1_CONFIRMATION`, `ORDER_PENDING`, `POSITION_OPEN`, `SIGNAL_EXPIRED`, `PAUSED`, `RISK_LOCKED` con transiciones explícitas.
- `OnTick`: decisiones sensibles a precios; `OnTimer`: UI/estadísticas; `OnChartEvent`: botones; `OnTradeTransaction`: sincronización; `OnInit/OnDeinit`: persistencia y limpieza; `OnTester` si aporta métricas. Actualizar ATR y CRT solo cuando haya nueva vela; sin cálculo histórico pesado en cada tick.

## Inputs ordenados
GENERAL, CRT DETECTION, LIQUIDITY, ENTRY M1, ATR & STOP, DYNAMIC TP/RR, RISK, PROP FIRM, HOURS, NEWS, POSITION MANAGEMENT, DASHBOARD, NOTIFICATIONS, BACKTEST/ANALYTICS. Todo configurable sin recompilar cuando sea razonable. Los valores por defecto son **hipótesis iniciales**, no ajustes rentables demostrados.

## Plan de pruebas mínimo
Crea `Tests/TestPlan.md` con escenarios: CRT buy/sell válido, barrida doble, cierre fuera de rango, señal expirada, retest no alcanzado, orden inválida, SL fuera de rango, objetivo insuficiente, spread alto, noticias sin calendario, tres pérdidas, DD diario/total, reinicio de terminal, pérdida de conexión, orden rechazada, fills parciales, DST, posición manual, hedging/netting, botones y cambios de configuración, y backtest M1/ticks reales sin look-ahead. Prueba TP 3/5/7/9 y adaptativo, modalidades A/B y stop M5/M1. Documenta las pruebas ejecutadas y las pendientes.

## Criterios de entrega
Entregar carpetas y código real, README en español (instalación en `MQL5/Experts`, includes relativos, MetaEditor, parámetros, pruebas, riesgos), plan de pruebas, registro de compilación y una lista honesta de funcionalidades verificadas y pendientes. No publicar resultados de rentabilidad sin backtesting real. Ejecuta todas las etapas que permita el entorno, corrige errores y no te detengas tras crear el primer `.mq5`.

**COMIENZA AHORA creando el proyecto y desarrollando el EA completo en MQL5 con sus `.mqh`, dashboard operativo, gestión de riesgo y pruebas.**
