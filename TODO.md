# TODO — mejoras pendientes

Lista de trabajo pendiente sobre la app y las herramientas, para retomar
directamente en la próxima sesión de programación sin tener que redescubrir
qué falta. Ordenada por prioridad dentro de cada bloque.

## Bloqueante: verificar que compila

- [ ] Todo el código de `lib/features/recording/`, `lib/shared/models/gait_phase.dart`,
  `recording_sample.dart`, `recording_session.dart`, `lib/shared/providers/recording_provider.dart`
  y los cambios en `sensor_provider.dart` / `history_service.dart` / `fake_data.dart`
  se escribieron **sin Flutter/Dart SDK disponible** en el entorno de esa sesión.
  Solo se verificó balance de llaves/paréntesis y lectura manual — nunca se
  compiló, analizó (`flutter analyze`) ni ejecutó. Primer paso obligatorio:
  `flutter pub get && flutter analyze && flutter run` y corregir lo que falle.

## Clasificador de fase de marcha (`gait_phase.dart`)

- [ ] El `GaitPhaseClassifier` solo compara talón (`_heelIdx`) contra
  antepié/dedos (`_foreIdx`); nunca mira la zona del arco/mediopié. Por eso
  `midStance` es casi un instante de transición en vez de una fase sostenida
  en los datos sintéticos (ver limitación documentada en el commit). Añadir
  los índices del arco y usar su carga relativa debería dar un `midStance`
  más realista.
- [ ] Validar con datos de un dispositivo real (ahora solo se ha probado
  contra el simulador `GaitWalkSimulator`). El ruido/offset real de los FSR
  puede requerir retocar `_dominanceRatio`, `_swingRatio` o `_minPeak`.
- [ ] Sin tests automatizados. Añadir un test unitario de
  `GaitPhaseClassifier.classify()` con secuencias FSR sintéticas por fase
  (ahora mismo la única validación fue visual, vía `plot_session.py --demo`).

## Grabación de sesiones

- [ ] ¿Qué pasa si el BLE se desconecta a mitad de una grabación? No se ha
  revisado si `stopRecording()` se llama automáticamente o la sesión queda
  "activa" para siempre en la base de datos. Decidir comportamiento y
  probarlo.
- [ ] No hay aviso en la UI si se exporta una sesión con 0 muestras (parar
  justo después de iniciar). Comprobar que `ExportService` no explota con
  CSV vacío y, si procede, deshabilitar/ocultar el export en ese caso.
- [ ] `getRecordingSamplesRaw` carga todas las muestras de la sesión en
  memoria de golpe. Bien para sesiones cortas; para grabaciones muy largas
  (varios minutos a ~8 Hz o más) considerar export por streaming o un aviso
  de tamaño.
- [ ] No hay límite ni aviso de almacenamiento para grabaciones muy largas en
  SQLite. Añadir un tope razonable o un aviso tipo "sesión larga, puede
  tardar en exportarse".
- [ ] No se puede renombrar una sesión después de grabarla, ni filtrar la
  lista de sesiones por fecha (la pantalla de Historial sí tiene filtros
  temporales). Añadir paridad si merece la pena.

## `tools/plot_session.py`

- [ ] Añadir una gráfica de orientación (roll/pitch/yaw) además de las tres
  actuales (presión, temperatura, ciclo de marcha).
- [ ] Añadir un modo de validación que superponga `step_edge` sobre la
  presión total, para comparar visualmente el detector de pasos ya
  existente (`_detectSteps` en `sensor_provider.dart`) con la fase de marcha
  derivada — útil para justificar en la memoria que son señales
  independientes y coherentes entre sí.
- [ ] Las figuras de ejemplo enviadas (`presion.png`, `temperatura.png`,
  `ciclo_marcha.png`) son con `--demo` (datos sintéticos). Antes de usarlas
  en la memoria final, regenerarlas con una sesión real grabada desde el
  dispositivo.

## Varios

- [ ] El switch "Datos simulados" del Debug se deshabilita durante una
  grabación (`debug_screen.dart`), pero ese flujo nunca se ha probado en un
  dispositivo real, solo leído.
- [ ] Revisar impacto en batería/rendimiento de los inserts en SQLite durante
  grabaciones largas (`appendRecordingSamples` por lotes) — no medido.
