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
- Registro estructurado en ExecutedChecks.json. CheckSources.mjs permite repetir la lógica con Node estándar. El comando Node CLI no se ejecutó aquí, por falta de terminal.

También se revisaron cálculos de referencia para redondeo de lote y cierres acotados; no validan OrderCalcProfit/OrderCalcMargin/CTrade reales y no se presentan como pruebas nativas.

## Repetición en MT5

1. Instalar la carpeta en MQL5/Experts y compilar el EA principal con MetaEditor F7.
2. Conservar log completo y versión/build. Corregir errores y advertencias materiales antes de ejecutar.
3. Compilar/ejecutar StrategySmoke.mq5 conforme a TestPlan.md.
4. Probar en demo calendario, stops/freeze/volumen/margen, expiry/filling, fills parciales, propiedad netting/hedging, reinicios y botones.
5. Ejecutar la matriz con ticks reales, spread variable y costes. Los perfiles .set son parciales: cargar primero los valores predeterminados y después el perfil.
6. Los perfiles permiten explícitamente calendario ausente para comparación sin noticias históricas. No validan el filtro de noticias ni rentabilidad.

Marcar cada caso como aprobado solo al obtener su resultado observado y evidencia nativa.
