# Registro de compilación y validación

Fecha: 2026-11-06. Plataforma objetivo: MetaTrader 5/MQL5 nativo.

## Compilación nativa

**NO EJECUTADA.** El entorno adjunto no pudo arrancar: inicialmente error de autenticación GitHub HTTP401; después, fallo al consultar capacidades/configuración del executor. No hubo terminal utilizable. Se recuperó acceso al repositorio mediante la conexión GitHub y se escribieron los archivos en una rama de desarrollo.

No se pudo invocar MetaEditor ni comprobar su instalación, versión o disponibilidad. No se conocen aún número de errores/advertencias de compilación. No se generó EX5. No hay informe de Strategy Tester, capturas de UI ni ejecución contra broker.

No interpretar un análisis de includes o una expresión JavaScript como evidencia de compilación MQL5.

## Comprobaciones realizadas

- Lectura completa de CODEX_INSTRUCTIONS.md.
- Revisión independiente de estrategia, ejecución, riesgo e integración.
- Análisis léxico y de dependencias de todas las fuentes MQL: guardas, includes relativos, ciclos, delimitadores, tipos e inputs.
- Ejecución en JavaScript de 14 casos sobre expresiones extraídas de riesgo/noticias y 19 casos sobre cuerpos extraídos de CRT/RR; todos pasan. Transformaciones explícitas en los módulos Tests/*ExpressionChecks.mjs.
- Registro estructurado en ExecutedChecks.json. CheckSources.mjs permite repetir la lógica con Node estándar. El entorno adjunto no tuvo terminal; posteriormente el comando Node CLI se ejecutó correctamente en GitHub Actions.

También se revisaron cálculos de referencia para redondeo de lote y cierres acotados; no validan OrderCalcProfit/OrderCalcMargin/CTrade reales y no se presentan como pruebas nativas.

## Repetición en MT5

1. Instalar la carpeta en MQL5/Experts y compilar el EA principal con MetaEditor F7.
2. Conservar log completo y versión/build. Corregir errores y advertencias materiales antes de ejecutar.
3. Compilar/ejecutar StrategySmoke.mq5 conforme a TestPlan.md.
4. Probar en demo calendario, stops/freeze/volumen/margen, expiry/filling, fills parciales, propiedad netting/hedging, reinicios y botones.
5. Ejecutar la matriz con ticks reales, spread variable y costes. Los perfiles .set son parciales: cargar primero los valores predeterminados y después el perfil.
6. Los perfiles permiten explícitamente calendario ausente para comparación sin noticias históricas. No validan el filtro de noticias ni rentabilidad.

Marcar cada caso como aprobado solo al obtener su resultado observado y evidencia nativa.

## CI ejecutada

[GitHub Actions run 42238852416](https://github.com/elschranz/CRT-Liquidity-Scalper-Pro/actions/runs/42238852416), commit de fuentes `ec1fc22a9eb827a22fb2202af291ae598427465f`: workflow y job `source-checks` completados con `success`; paso `Validate source graph and extracted expressions` correcto. Ejecutó `node CRT_Liquidity_Scalper_Pro/Tests/CheckSources.mjs`: 39 fuentes MQL, 104 inputs, 50 tipos y 33 casos de expresiones. Sigue sin compilación ni ejecución MT5.

## Corrección tras compilación aportada por el usuario

El usuario ejecutó MetaEditor y comunicó **5 errores, 0 advertencias**:
- DashboardComponents.mqh: 44:32, 54:57, 55:33.
- Dashboard.mqh: 47:43, 55:65.
- Diagnóstico común: `constant expected`.

Los cinco argumentos predeterminados usaban CRT_UI_TEXT/CRT_UI_RAISED/CRT_UI_MUTED, declarados como variables globales `const color`. Se reemplazan las diez declaraciones de paleta por macros de literales `C'R,G,B'`, sin cambiar nombres, colores, llamadas ni comportamiento. La fuente de texto permanece `const string` porque no se usa como valor predeterminado.

Comprobación posterior: análisis de fuentes y expresiones mediante Node; auditoría de los cinco usos y conservación exacta de los diez colores. **Recompilación nativa posterior pendiente.** El entorno ya admite terminal y archivos, pero MetaEditor/Wine no están disponibles en PATH. No se afirma una compilación de cero errores.
