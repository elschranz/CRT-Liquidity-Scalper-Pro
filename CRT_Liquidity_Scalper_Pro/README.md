# CRT Liquidity Scalper Pro · MT5

Expert Advisor modular en MQL5 nativo para EURUSD: CRT sobre dos velas M5 cerradas y ejecución refinada en M1. Incluye entradas Limit agresivas o confirmación M1, riesgo persistente, dashboard y journal.

**Estado: implementación y revisión estática realizadas; compilación MetaEditor y ejecución MT5 pendientes.** No se entrega un EX5 ni se atribuyen resultados de rentabilidad. Los valores iniciales son hipótesis de trabajo.

## Instalación y compilación

1. Descargar esta rama completa del repositorio. Copiar la carpeta `CRT_Liquidity_Scalper_Pro` a `Archivo > Abrir carpeta de datos > MQL5/Experts`, conservando todas las subcarpetas.
2. Abrir `CRT_Liquidity_Scalper_Pro.mq5` con MetaEditor actualizado y pulsar F7. Solo depende de la biblioteca estándar MT5 `Trade/Trade.mqh`; no usa DLL ni paquetes externos.
3. Guardar el log de compilación y resolver errores/advertencias relevantes. Consultar `Tests/CompilationLog.md`: en esta entrega no hay compilación nativa disponible.
4. En una cuenta **demo**, abrir el símbolo EURUSD exacto del broker —incluido sufijo— y adjuntar el EA a su gráfico. El periodo recomendado para observación/tester es M1; los indicadores y señales usan periodos explícitos.
5. Si `InpSymbol` queda vacío se usa el símbolo del gráfico. Si se configura, debe coincidir con él: las decisiones de entrada dependen de sus ticks.
6. Configurar Magic único, costes, horario/DST del servidor y referencias de riesgo antes de habilitar trading algorítmico. Usar una sola instancia por combinación cuenta/servidor/símbolo/Magic.

Ejemplo opcional en PowerShell, adaptando rutas:

```powershell
& "C:\Program Files\MetaTrader 5\metaeditor64.exe" /compile:"C:\ruta\MQL5\Experts\CRT_Liquidity_Scalper_Pro\CRT_Liquidity_Scalper_Pro.mq5" /log:"C:\ruta\compile.log"
```

## Arquitectura y eventos

| Carpeta | Responsabilidad |
|---|---|
| Core | Inputs centralizados, tipos, estados, utilidades, persistencia y logs |
| Strategy | CRT, liquidez histórica, ATR cerrado, entradas M1, SL/TP y sesiones/DST |
| Trading | Lote monetario, validación broker, intención idempotente, órdenes y posiciones |
| Risk / Filters | DD diario/semanal/total, historial, exposición, spread, ATR, horas y noticias |
| Management | BE demorado, trailing M1 y parciales opcionales |
| UI | Dashboard retenido, botones, confirmaciones, niveles y notificaciones |
| Analytics | CSV real, estadísticas de posiciones cerradas y ledger virtual independiente |
| Tests | Smoke MQL, comprobadores JS, evidencia y matriz de validación |

`OnTick` decide entradas, invalida liquidez y observa excursiones. `OnTimer` mantiene protecciones, cierres de seguridad, estadísticas y panel aunque este esté oculto. `OnTradeTransaction` reconcilia fills y cierres; `true` de CTrade nunca basta para afirmar ejecución. `OnChartEvent` ejecuta acciones del panel. `OnTester` devuelve beneficio monetario nativo dividido entre 1 + DD monetario de equity: es una función de comparación, no una predicción.

Estados explícitos: IDLE, CRT_DETECTED, WAITING_RETEST, WAITING_M1_CONFIRMATION, ORDER_PENDING, POSITION_OPEN, SIGNAL_EXPIRED, PAUSED y RISK_LOCKED.

## Señal y entradas

El detector usa shifts M5 2 y 1. BUY exige barrer L1 más el mínimo, mecha suficiente, cierre estrictamente dentro de L1/H1 y ausencia de ruptura H1. SELL es simétrico. Rechaza OHLC incoherente, datos incompletos, barras no consecutivas y barrida doble. Persiste la última barra procesada antes de aceptar la señal.

- **ENTRY_AGGRESSIVE:** Buy Limit en L1 + offset; Sell Limit en H1 − offset. Debe ser una Limit válida respecto a Ask/Bid y restricciones broker. Nunca se convierte a mercado. Expira según el menor plazo permitido y se cancela si rompe el extremo manipulador o alcanza TP antes de entrar.
- **ENTRY_CONFIRMED:** exige retorno observado después de confirmarse CRT; BUY observa Bid y SELL Ask para el área. Una M1 completamente cerrada debe tocar/rechazar el nivel y cerrar a favor. La entrada a mercado usa Ask/Bid ejecutable, con límite de persecución y validación vigente.
- **ENTRY_BOTH_COMPARE:** ejecuta únicamente `InpRealComparisonMode`; observa A y B en ledgers virtuales. Mantiene una cohorte hasta que ambas modalidades concluyan o expiren, por lo que puede reducir la cadencia frente a ejecuciones aisladas.

La liquidez se congela con datos anteriores a la vela manipuladora: pivotes confirmados, extremos recientes, agrupaciones equal high/low, Asia/Londres completadas y día previo. Los niveles alcanzados/consumidos se invalidan y persisten. CRT puro no exige confluencia, pero TP dinámico sigue necesitando un objetivo histórico fiable salvo fallback explícito.

## SL, TP y costes

ATR M5(14), shift 1. El SL por defecto usa:

`max(distancia a extremo M5 + buffer, ATR × 0.45, 0.7 pip)`

Máximo inicial 3 pips: si no cabe la estructura, se descarta. Redondeo del SL hacia fuera con tick size; nunca se recorta estructura ni se amplía el SL después de abrir. M1+ATR requiere confirmación M1; en modalidad agresiva falla de forma segura. SL fijo es comparativo y también debe respetar la estructura.

Objetivo efectivo = distancia al siguiente nivel intacto × 90%. Se elige el mayor RR de 9/7/5/3 que cabe entre mínimo/máximo; por debajo de 3R se descarta. Fallback está desactivado. `MinimumRR` es RR **bruto de distancias**, conforme a la especificación; adicionalmente se exige beneficio neto estimado positivo. Comisión y reserva de slippage se incluyen en el riesgo monetario.

El lote usa `OrderCalcProfit`, divisa de cuenta, comisión estimada de ida/vuelta por lote y reserva de slippage; redondea volumen hacia abajo y valida `OrderCalcMargin`. Un lote calculado menor al mínimo se rechaza. Los costes reales pueden superar la estimación.

Tras el fill se recalculan riesgo/RR y TP desde el precio real, conservando SL inicial o uno ya estrechado por gestión. Un fill inválido activa cierre de seguridad por defecto: cola persistente, hasta tres intentos sobre ticket propio con cooldown. Un timeout sin evidencia no se reenvía a ciegas; el residuo queda bloqueado y exige intervención. **Ese cierre puede fallar o generar pérdidas: no neutraliza gaps ni slippage.**

## Riesgo y persistencia

Predeterminados: riesgo 0.25%, techo duro 0.50%, pérdida diaria interna 0.75%, semanal 2%, DD total 4%, tres pérdidas consecutivas por día de reset, tres posiciones iniciadas/día, una posición y una pendiente como máximos. La estrategia solo mantiene una exposición/setup real activo.

La referencia por trade puede ser equity o balance. DD fijo/trailing y referencias balance/equity son configurables; el high-water se actualiza con observaciones disponibles. Se reservan stops propios, pendientes, costes y pérdidas flotantes de toda la cuenta de forma conservadora. La equity y el DD incluyen operaciones ajenas; el EA no cierra ni modifica esas operaciones.

- Locks diario/semanal se liberan únicamente al reset horario correspondiente del servidor. El lock total persiste. START, cambio de riesgo y RESET LAYOUT no borran límites.
- Al bloquearse entradas se cancelan pendientes propias. Las posiciones permanecen abiertas salvo opt-in `InpCloseOwnPositionsOnRiskLock` por DD real/datos de protección inválidos.
- Globals persistentes y archivos se separan por cuenta, servidor, símbolo y Magic. Las pasadas del tester usan un namespace propio. Una referencia corrupta, historial incompleto detectable o persistencia fallida bloquea entradas.
- Primera instalación sin actividad propia puede crear referencia. Con actividad anterior y referencia perdida se bloquea; `InpRecoveryReferenceBalance` solo permite recuperación explícita con una referencia auditada. No restaura un high-water histórico desconocido.
- No borrar Globals/archivos para eludir un bloqueo. MT5 puede eliminar Globals no accedidas durante cuatro semanas; conservar copia y auditar cualquier recuperación.
- Al reiniciar se recupera la gestión de exposición y contexto estructural si existe, pero un setup no enviado no vuelve a ejecutarse. Si no se puede reconstruir la pendiente, se cancela.
- Una intención de apertura tiene un solo intento; incluso un rechazo definitivo consume la señal. Una respuesta incierta bloquea nuevas entradas hasta reconciliación.
- El EA exige expiración broker `ORDER_TIME_SPECIFIED` para Limits; rechaza brokers que solo permitan GTC.
- En netting se examina el historial del identificador antes de modificar/cerrar. Una operación manual mezclada puede suspender la gestión automática por seguridad; requiere revisión manual. En hedging se actúa por ticket propio.

## Horario, calendario y parámetros

Todos los inputs están en `Core/Config.mqh`, agrupados por GENERAL/EXECUTION, CRT, LIQUIDITY, ENTRY M1, ATR/STOP, RR, RISK, PROP FIRM, HOURS, NEWS, POSITION MANAGEMENT, DASHBOARD, NOTIFICATIONS y ANALYTICS.

| Parámetro | Inicial |
|---|---|
| MinSweep / MinWick | 0.2 / 0.3 pip |
| Offset / expiración señal y pendiente | 0.1 pip / 15 minutos |
| RejectionWick / cierre M1 mínimo / chase | 0.2 / 0.1 / 1.0 pip |
| ATR period / multiplier / buffer | 14 / 0.45 / 0.2 pip |
| Spread máximo | 0.3 pip |
| Comisión / slippage estimado | 7 por lote ida/vuelta, divisa cuenta / 0.1 pip |
| Broker invierno/verano | UTC+2 / UTC+3, regla europea |
| Londres / Nueva York | 08–17 hora local de cada centro |
| Noticias EUR/USD alto impacto | bloqueo ±15 minutos, fail closed |

Los offsets del servidor son **configuración del broker**, no la zona horaria del ordenador ni la del usuario. Se admiten reglas Europa/EE.UU./sin DST; reglas estadounidenses vigentes desde 2007. La hora repetida al terminar DST es ambigua sin información adicional; verificar semanas de cambio y datos del broker. La mayoría de cambios ocurre con FX cerrado.

Se prioriza calendario económico nativo. En Strategy Tester no está disponible y el valor seguro por defecto bloquea trading. Los perfiles de comparación de esta entrega permiten calendario ausente **solo para explorar la lógica sin noticias históricas**; esos resultados no validan el filtro de noticias. Un calendario vacío que responde correctamente no acredita completitud del proveedor.

## Dashboard

Paleta oscura, acento naranja, cinco pestañas, métricas, progreso DD, motivo de rechazo y estado de noticias. Posición inicial arriba a la derecha; arrastrar el título; posición/minimización persistentes. En gráficos pequeños se minimiza automáticamente.

Botones: START/PAUSE, modalidad, entradas ON/OFF, cancelar pendientes, cerrar propias con segundo clic en cinco segundos, BE válido, minimizar, niveles, estadísticas y reset de layout. Selector 0.10/0.25/0.50% sujeto al techo. Cambiar modalidad/pausar/cancelar consume el setup actual: se espera un CRT nuevo. Ocultar el panel no suspende protección. Los dibujos manuales no se borran.

## CSV y métricas

Archivos en `MQL5/Files` (sandbox propio del agente en tester), con prefijo CRT específico:

- `*_real.csv`: señales/solicitudes/fills/cierres, extremos, nivel, ATR, modalidad, sesión, precios, SL/TP/RR, comisión/swap/fee, spread, slippage observado cuando existe, MFE/MAE y tiempo de retest.
- `*_breakdown.csv`: agregados reales por sesión, modalidad, RR y tramo ATR; categoría UNKNOWN si falta contexto. En PERFORMANCE, clic en la fila de desglose cambia SESSION/MODE/RR/ATR; el tooltip muestra detalle y tamaño de muestra de R.
- `*_virtual.csv`: simulación separada A/B en R; nunca contribuye a neto real ni reserva riesgo real.
- Contexto por posición y Globals de riesgo inicial: permiten recuperar atribución y excluir R desconocido.

Winrate, neto y PF agrupan posiciones completamente cerradas, con fills y parciales agrupados. PF sin pérdidas se representa como N/A. Los desgloses usan la primera entrada de cada posición, RR planificado 3/5/7/9 y ATR <2 / 2–5 / 5–10 / ≥10 pips. Esperanza/resultado medio en R usa solo muestras con riesgo inicial fiable. DD estadístico es el de la curva monetaria de trades cerrados, no el DD histórico de equity: para ese dato usar el reporte nativo del tester.

MFE/MAE solo cubre ticks observados, sin reconstrucción de huecos. Cargos sin identificador de posición afectan DD de cuenta, pero no tienen atribución fiable por trade. Una cuenta con crédito distinto de cero se bloquea porque su contabilidad no está soportada.

El ledger virtual usa comisión estimada y slippage configurable; falla si no puede convertir costes. No reproduce cola, profundidad, rechazos, latencia ni cartera monetaria; mantiene SL/TP fijos y puede perder más de 1R en gaps. Sus contadores son de sesión; reiniciar censura trades abiertos y conserva CSV, sin inventar cierres.

## Verificación y límites pendientes

Consultar `Tests/ExecutedChecks.json`, `Tests/CompilationLog.md` y `Tests/TestPlan.md`.

Disponibles: revisión de código, 39 fuentes MQL con guardas/includes acíclicos/identificadores, 33 casos JS sobre cuerpos/expresiones extraídos. Se incluye un smoke **MQL real pendiente de ejecutar**. El comprobador reproducible usa Node estándar, sin dependencias:

```sh
node CRT_Liquidity_Scalper_Pro/Tests/CheckSources.mjs
```

La lógica pasó en JavaScript y también mediante Node en [GitHub Actions](https://github.com/elschranz/CRT-Liquidity-Scalper-Pro/actions/runs/42238852416). No ejecuta APIs ni eventos MT5. El entorno adjunto siguió sin terminal utilizable; la ejecución Node se realizó en el runner de GitHub.

Pendientes: compilación nativa, renderizado/arrastre del dashboard, API de calendario real, broker netting/hedging, fills parciales, desconexiones/reinicios, DST histórico y backtests M1 con ticks reales, comisiones y spreads reales. Cualquier fallo debe resolverse antes de usar fondos reales. Un SL de 0.7–3 pips es extremadamente sensible a spread, tick size, stops/freeze, comisiones y slippage, y puede ser inejecutable.

No hay rentabilidad demostrada ni garantía de cumplimiento de las reglas de una firma de fondeo. Adaptar los límites al contrato concreto y validar primero en demo.
