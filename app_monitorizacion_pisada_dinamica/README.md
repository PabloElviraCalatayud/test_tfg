# GaitSole — App de monitorización de la pisada dinámica

Aplicación Flutter que se conecta por Bluetooth Low Energy (BLE) a una plantilla
sensorizada basada en ESP32-S3 (12 FSR, 4 termorresistencias, IMU de 9 grados de
libertad), decodifica y calibra los datos en tiempo real, los visualiza, los
publica a un *broker* MQTT y mantiene un historial local. Ver la memoria del
proyecto en `../documentacion/` para el detalle completo de la arquitectura.

## Funcionalidades

- **Dashboard en vivo**: mapa de calor de temperatura, mapa de presión plantar,
  horizonte artificial (orientación del pie), reparto de peso en lenguaje
  llano y una píldora con la fase de marcha detectada en cada instante.
- **Historial**: calendario navegable, filtros temporales (hoy/semana/mes/rango
  personalizado) y trazabilidad por sensor de cada paso detectado.
- **Sesiones** (pestaña nueva): graba una serie temporal completa (presión,
  temperatura, IMU y fase de marcha) y expórtala como CSV para generar tus
  propias gráficas (ver más abajo). Funciona tanto con el dispositivo real
  como en modo de datos simulados, sin necesidad de tener el ESP32-S3 a mano.
- **Debug**: lectura cruda de todos los sensores y utilidades de desarrollo
  (sembrar/borrar historial de prueba, test de publicación MQTT).
- **Perfil** y **actualización de firmware por BLE (OTA)**.

## Generar gráficas para la memoria (presión, temperatura, ciclo de marcha)

1. En la app, abre la pestaña **Sesiones**, pulsa *Iniciar grabación* (puede
   ser en modo simulado si no tienes el dispositivo a mano) y, pasado un
   rato, *Detener grabación*.
2. En la lista de sesiones, pulsa el icono de compartir de esa sesión y
   guarda el CSV donde prefieras.
3. Desde este repositorio, genera las gráficas:

   ```bash
   cd tools
   pip install matplotlib
   python3 plot_session.py /ruta/a/tu_sesion.csv --outdir figuras
   ```

   Esto genera `presion.png`, `temperatura.png` y `ciclo_marcha.png` en
   `figuras/`, listas para incluir en la memoria LaTeX
   (`\includegraphics{figuras/presion.png}`, etc.).

   Si todavía no tienes ninguna sesión grabada, puedes generar una de
   ejemplo directamente:

   ```bash
   python3 plot_session.py --demo --outdir figuras
   ```

## Desarrollo

```bash
flutter pub get
flutter run
```

La app arranca en modo de datos simulados (interruptor "Datos simulados" en
la pestaña Debug); para usar el dispositivo real, desactívalo y empareja el
ESP32-S3 desde el botón de dispositivo de la barra superior.

Mejoras pendientes y limitaciones conocidas: ver [`TODO.md`](../TODO.md) en
la raíz del repositorio.
