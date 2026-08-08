// lib/core/services/foreground_service.dart
//
// Mantiene vivo el proceso de la app (con notificación persistente en
// Android) mientras hay una plantilla BLE conectada, para que la
// conexión sobreviva a minimizar la app / apagar la pantalla. La
// conexión GATT en sí la sigue gestionando BleService exactamente igual
// que en foreground — este servicio no hace ningún trabajo periódico
// propio, solo evita que Android mate el proceso.
//
// NOTA: la API de flutter_foreground_task (TaskHandler, ForegroundTaskOptions)
// puede variar entre versiones mayores del paquete; verificar con
// `flutter pub get` + `flutter analyze` tras instalar la versión fijada
// en pubspec.yaml.

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

@pragma('vm:entry-point')
void _foregroundTaskStartCallback() {
  FlutterForegroundTask.setTaskHandler(_KeepAliveTaskHandler());
}

/// No hace trabajo periódico: solo existe para satisfacer la API del
/// plugin (requiere un TaskHandler registrado para poder arrancar el
/// foreground service). La conexión BLE la gestiona BleService en el
/// isolate principal de Flutter, no aquí.
class _KeepAliveTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

class ForegroundBleService {
  static bool _initialized = false;

  static void _ensureInit() {
    if (_initialized) return;
    _initialized = true;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'gait_ble_service',
        channelName: 'Conexión BLE activa',
        channelDescription:
            'Mantiene la conexión con la plantilla mientras la app está en segundo plano.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: false,
        allowWifiLock: false,
      ),
    );
  }

  /// Arranca el foreground service (Android) para que el proceso no se
  /// mate al minimizar la app mientras hay una plantilla conectada.
  static Future<void> start({required String deviceName}) async {
    _ensureInit();
    await FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: 'GaitSole conectado',
      notificationText: 'Recibiendo datos de $deviceName en segundo plano',
      callback: _foregroundTaskStartCallback,
    );
  }

  /// Para el foreground service al desconectar a propósito.
  static Future<void> stop() async {
    await FlutterForegroundTask.stopService();
  }
}
