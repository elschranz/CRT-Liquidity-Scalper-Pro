# Plan de pruebas — CRT Liquidity Scalper Pro

Estado de esta entrega: **no compilado con MetaEditor y no ejecutado en MT5**. El entorno de trabajo no arrancó; no hubo acceso a terminal, MetaEditor, Strategy Tester ni datos de ticks. La recuperación de instrucciones y la escritura del proyecto se hicieron mediante GitHub. Ninguna tabla siguiente representa un backtest realizado.

Los parámetros iniciales son hipótesis. Un resultado positivo de compilación o de pruebas funcionales no acredita rentabilidad ni aptitud para una cuenta fondeada.

## Registro y evidencia

Para cada ejecución conservar: versión de MT5/MetaEditor, hash del commit, broker, símbolo completo, modo netting/hedging, moneda de cuenta, dígitos/tick size, stops/freeze levels, comisión, spread, slippage configurado, zona horaria/DST del servidor, intervalo, calidad y origen de ticks, archivo .set, informe y diario del tester. Anotar pasos, resultado esperado, resultado observado y archivos de evidencia.

| Comprobación | Estado de entrega |
| --- | --- |
| Lectura de CODEX_INSTRUCTIONS.md y diseño según contrato modular | Realizada mediante GitHub |
| Creación del código, includes relativos y revisión estática | Realizada; consultar registro de integración para alcance exacto |
| Compilación del EA y de StrategySmoke.mq5 | Pendiente: MetaEditor no disponible |
| Ejecución de StrategySmoke.mq5 | Pendiente: MT5 no disponible |
| Strategy Tester con ticks reales | Pendiente |
| Broker demo: calendario, fills, restricciones y panel | Pendiente |
| Rentabilidad, robustez estadística y cumplimiento de reglas de una prop firm | No validados |

## Compilación y smoke test nativo

1. Copiar la carpeta CRT_Liquidity_Scalper_Pro completa a MQL5/Experts.
2. Abrir CRT_Liquidity_Scalper_Pro.mq5 en MetaEditor y pulsar F7. Guardar el log completo. Resolver errores y revisar advertencias antes de ejecutar.
3. Compilar Tests/StrategySmoke.mq5. Para ejecutarlo como script, copiar temporalmente la carpeta completa bajo MQL5/Scripts, manteniendo las rutas relativas, y abrir EURUSD demo.
4. Ejecutar el script con los inputs de detección y RR por defecto. Su diario debe mostrar PASS para CRT BUY/SELL, nivel y extremo conservados, barrida doble, cierre fuera de rango, ausencia de barrida, referencia degenerada y selección RR 3/5/7/9; FAIL debe ser cero.
5. El smoke llama al detector y selector RR reales. No comprueba ejecución, historial, persistencia, UI ni resultados económicos. No cambiar sus inputs para ocultar fallos.

## Señales, liquidez y ausencia de datos futuros

| Caso | Procedimiento | Resultado exigido |
| --- | --- | --- |
| CRT BUY válido | Vela 2 cerrada barre únicamente L1, vuelve dentro y supera mecha mínima | Una señal BUY con extremo Low2 y ID estable |
| CRT SELL válido | Espejo de BUY en H1 | Una señal SELL |
| Barrida doble | Vela 2 supera ambos extremos | Rechazo; ninguna orden |
| Cierre fuera del rango | Close2 en/sobre H1 o en/bajo L1 | Rechazo |
| Igualdad de umbrales | Barrida y cierre exactamente en cada frontera | Respetar desigualdades estrictas de las reglas |
| Referencia degenerada/incompleta | High=Low, OHLC incoherente, CopyRates incompleto | Rechazo sin acceso a valores no inicializados |
| M5 todavía abierta | Modificar OHLC de shift 0 entre ticks | No cambia señal; solo shifts cerrados |
| Mismo cierre, múltiples ticks | Repetir ticks sin nueva M5 | Un ID/una señal/una intención de ejecución |
| Expiración | Superar MaxSignalAgeMinutes | SIGNAL_EXPIRED y pendientes propias canceladas |
| Pivote confirmado | Reproducir una secuencia antes y después de sus barras derechas | Nivel disponible solo después de confirmarse |
| Equal highs/lows | Variar tolerancia y contactos mínimos | Nivel solo tras suficientes contactos conocidos |
| Nivel consumido | Barrer/invalidar nivel y reiniciar | No reutilizarlo como liquidez intacta |
| Asia/Londres/día previo | Reproducir cierre de sesión y cambio de día | Extremos solo del tramo histórico completado |
| Comparación truncada | Ejecutar hasta T y luego extender hasta T+n | Señales y decisiones anteriores a T idénticas |

## Entradas y ejecución

| Caso | Procedimiento | Resultado exigido |
| --- | --- | --- |
| A válida | BUY Limit debajo de Ask / SELL Limit encima de Bid | Solo pendiente del tipo correcto y una por señal |
| A inválida | Nivel ya atravesado o distancia broker insuficiente | Rechazo; nunca conversión a mercado |
| A sin retest | No tocar precio hasta expiración | Cancelación, sin fill inventado |
| A invalidada | Romper extremo o alcanzar TP antes de entrada | Cancelar pendiente propia; reconciliar carrera cancelación/fill |
| B retorno real | Ticks aún no tocaron área, pero M1 histórica sí | No confirmar retrospectivamente |
| B vela cerrada | Tocar área después de señal, rechazar y cerrar a favor | Esperar cierre M1 completo; entrar al primer tick elegible |
| B vela abierta | Mecha/cierre provisional favorables en shift 0 | Ninguna confirmación |
| B persecución | Cotización más allá de MaximumChaseDistancePips | No ejecutar |
| BOTH_COMPARE | Seleccionar modalidad real A, después B | Máximo una modalidad real; dos ledgers virtuales separados |
| Reinicio con intención incierta | Cortar conexión tras envío antes de respuesta | Reconciliar órdenes/deals; no reenviar a ciegas |
| Rechazo servidor | Mercado cerrado, volumen/stops inválidos o falta margen | Retcode y razón registrados; sin duplicados |
| Fill parcial | Volumen fraccionado y eventos fuera de orden | Riesgo sobre volumen real; sin duplicar journal o posición |
| Gap/slippage | Forzar precio de fill que invalide RR/riesgo | Aplicar política de seguridad y registrar pérdida real posible |
| Stops/freeze/tick | Broker con restricciones superiores al SL elegido | Rechazo seguro, sin recortar estructura |
| Posición manual | Añadir posición ajena en mismo símbolo netting | No mezclar ni cerrar/modificar exposición ajena |
| Hedging | Varias posiciones manuales y propia | Operaciones por ticket propio |
| Desconexión | Retirar red durante una señal/pendiente/posición | Sin nuevas entradas; recuperar estado de servidor antes de actuar |

## SL, TP y dimensionamiento

| Caso | Procedimiento | Resultado exigido |
| --- | --- | --- |
| SL estructural | Extremo M5 más buffer, ATR mayor/menor | Distancia máxima de estructura, ATR mínimo y MinimumSLPips |
| SL superior al máximo | Estructura exige más que MaximumSLPips | Descartar, nunca cortar SL para hacer caber lote |
| SL M1 experimental | Extremo de rechazo M1 cerrado y ATR; comparar con invalidación M5 | No usar M1 abierta; etiquetar el SL M1 como experimental |
| SL fijo | Comparar con mismas señales/datos | Cumplir validaciones y registrar modalidad |
| TP adaptativo | Disponibles 2.99, 3.01, 5.01, 7.01, 9.01 R | Rechazo, 3R, 5R, 7R, 9R respectivamente |
| Margen de liquidez | Nivel a 10 pips y margen 10% | Objetivo efectivo a 9 pips antes de elegir RR |
| Sin objetivo válido | AllowFallbackTarget=false | Rechazo; ningún nivel inventado |
| Fallback/fijo | Activación explícita | Registrar política distinta y RR; comparar separadamente |
| Lote mínimo | Riesgo calculado requiere volumen inferior al mínimo | No operar; nunca redondear hacia arriba |
| Step y moneda | Steps 0.01/0.1 y cuenta en distintas monedas | OrderCalcProfit monetario y redondeo hacia abajo |
| Costes/margen | Aumentar comisión, reserva slippage y margen requerido | Reducir o rechazar volumen; no superar presupuesto |
| Precio real | Ejecutar distinto del previsto | Revalidar riesgo/RR; no ampliar SL tras abrir |

## Riesgo, persistencia y calendario

| Caso | Procedimiento | Resultado exigido |
| --- | --- | --- |
| Tres pérdidas | Tres posiciones cerradas negativas, con parciales | Bloqueo sin contar cada fill como trade independiente |
| Tres trades/día | Tres posiciones abiertas en el día | Bloqueo de nuevas entradas |
| DD diario 0.75% | Pérdida realizada y flotante alcanza umbral | Bloquear y cancelar solo pendientes propias |
| DD semanal 2% | Cruzar límite entre varios días | Mantener bloqueo semanal hasta reset válido |
| DD total fijo/trailing | Variar referencia/high-water y equity | Umbral según modelo, persistente tras reinicio |
| Riesgo agregado | Pendiente más posición y pérdidas flotantes | No asignar dos veces capital comprometido |
| Estado perdido/corrupto | Eliminar o truncar persistencia | Fail closed; UI no desbloquea referencias de riesgo |
| Reinicio | Reiniciar EA y terminal cerca del reset diario | No restaurar presupuesto consumido ni perder locks |
| Reset horario | Cruzar hora configurada y lunes | Periodos se actualizan una vez, según servidor |
| Depósito/retiro | Movimiento de balance durante periodo | Evitar interpretarlo como beneficio del EA |
| Spread | EURUSD con 0.2, 0.3 y 0.4 pip | Respetar límite por defecto 0.3 sin confundir puntos/pips |
| ATR | Valores bajo mínimo/sobre máximo/datos incompletos | Rechazo con motivo |
| Noticias reales | Evento EUR/USD alto impacto | Bloqueo 15 min antes y después |
| Calendario ausente | Tester/calendario no disponible/error API | Fail closed por defecto; bypass solo mediante input explícito |
| DST | Semanas de cambio europeo y estadounidense, horas repetidas | Sesión y UTC según reglas configuradas del broker |
| Panel oculto/pausado | Minimizar/cerrar panel durante pérdida flotante | Protecciones y gestión continúan funcionando |
| Cambio de inputs | Reducir techo/aumentar lotes/reiniciar | Techo y locks no se evaden |

## Gestión, UI y journal

| Caso | Procedimiento | Resultado exigido |
| --- | --- | --- |
| FIXED_ADAPTIVE_TP | Alcanzar 3R sin tocar TP | Ningún BE/trailing/parcial por defecto |
| DELAYED_BREAK_EVEN | Antes y después de 3R, con costes y freeze | BE solo válido y nunca retrocede SL |
| STRUCTURE_TRAILING_M1 | Pivotes confirmados favorables/desfavorables | Solo mejora SL, sin mirar barras futuras |
| Parcial opcional | Activar, cruzar umbral, reiniciar y repetir ticks | Una sola reducción, volumen broker válido y riesgo no aumenta |
| Botones | START/PAUSE, modalidad, entradas, cancelar, BE | Acción real y estado coherente, sin eludir riesgo |
| Cierre posiciones | Primer y segundo clic dentro/fuera ventana | Solo segundo clic válido ejecuta, solo posiciones propias |
| Layout | Arrastrar, minimizar, cambiar tamaño y reiniciar | Posición persistente; texto legible; reset no toca riesgo |
| Niveles | Alternar niveles/historial; añadir dibujos manuales | Solo objetos CRT propios se eliminan |
| Stats/tabs | Alternar estadísticas y pestañas | Valores reales; virtual identificado aparte |
| Notificaciones | Mismo evento en muchos ticks | Deduplicado; push/sound según input |
| Journal | Señal/retest/plan/fill/parcial/cierre/rechazo | ID, horas, precios, ATR, RR, costes y razón trazables |
| R desconocido | Reiniciar sin metadatos de apertura recuperables | N/A o muestra excluida; no inferir riesgo desde SL trail actual |
| MFE/MAE | Cortar feed durante posición | Registrar solo ticks observados; no inventar extremo del hueco |
| Estadísticas | Varias fills/partials, swap, fee y comisión | Agrupar posición cerrada; neto con todos los costes |
| Virtual gap | Tick cruza Limit y SL simultáneamente | Modelar fill posible y pérdida; no cancelar para borrar el perdedor |
| Reinicio virtual | Detener EA con trade hipotético abierto | CENSORED; contadores de sesión reinician; CSV previo se conserva |

## Matriz de backtest y validación posterior

Usar EURUSD en M1 con modo «Cada tick basado en ticks reales», spread variable, comisiones reales y latencia/slippage cuando permita el tester. No validar entradas M1 con «Solo precios de apertura». Ejecutar como mínimo:

- Entrada A, B y BOTH_COMPARE con cada modalidad real elegida.
- SL M5+ATR, M1+ATR experimental y fijo de comparación.
- TP fijo 3/5/7/9 y TP adaptativo; separar resultados por RR, sesión, ATR y modalidad.
- Gestión fija, BE demorado y trailing M1; parciales desactivados y luego activación explícita.
- Diferentes meses, sesiones, semanas DST, periodos de volatilidad y spreads altos.
- Periodo de diseño y otro fuera de muestra, sin usar el segundo para afinar y declararlo después fuera de muestra.
- Repetición en broker demo netting y hedging con calendario y restricciones reales.

BOTH_COMPARE mantiene una sola cohorte de señal mientras cualquiera de sus trades virtuales siga activo. Esta condición puede reducir la cadencia real frente a A/B por separado y debe constar en los informes. No simula los límites monetarios de una cartera virtual; filtra condiciones comunes de mercado y registra resultados en R por modalidad.

La comparación virtual representa un ledger de precios hacia delante, no el motor de ejecución del broker. Usa bid/ask observados, comisión estimada y slippage de mercado configurable; no reproduce cola, profundidad, latencia, liquidez, rechazos ni ajustes discrecionales. Los trades abiertos al detener el EA quedan censurados, no como ganancia ni pérdida cerrada.

El DD máximo de Analytics/Statistics corresponde a la curva acumulada de operaciones propias cerradas, en moneda de cuenta. No equivale al DD histórico de equity de toda la cuenta; para este último usar el informe nativo del tester y los snapshots de riesgo en vivo. La esperanza en R usa solo posiciones con riesgo inicial monetario recuperado; mostrar su tamaño de muestra, no extrapolar sobre operaciones sin metadatos.

Registrar resultados observados antes de marcar cualquier escenario como aprobado. No se incluyen métricas de rentabilidad en esta entrega.

## Comprobadores de fuente ejecutados

La integración ejecutó en JavaScript la lógica de `CheckSources.mjs`: guardas, grafo de includes, tipos/inputs y delimitadores, más 14 expresiones de riesgo/noticias y 19 casos extraídos del detector CRT/selector RR. Ver `ExecutedChecks.json`. Es una traducción aritmética/estructural, no compilación ni ejecución MQL5. El comando Node queda listo para repetir localmente.

Validar también CSV de desglose real: SESSION de primera entrada; MODE con metadatos; RR3/5/7/9; ATR<2/2–5/5–10/≥10; UNKNOWN sin mapping; muestras R explícitas. Cambiar grupo mediante la fila clicable de PERFORMANCE y comprobar tooltip/CSV. La cola de cierre de seguridad debe reconciliar residuos, limitarse a tres intentos y bloquear incertidumbre sin identidad de orden; no promete cerrar sin pérdida.
