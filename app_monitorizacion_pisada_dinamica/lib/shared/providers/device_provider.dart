import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/ble_service.dart';
import '../../core/services/mqtt_service.dart';
import '../../core/services/foreground_service.dart';

// ─── BLE SERVICE ────────────────────────────────────────────────

final bleServiceProvider = Provider<BleService>((ref) {
  final svc = BleService();
  ref.onDispose(() => svc.dispose());
  return svc;
});

// ─── MQTT SERVICE ───────────────────────────────────────────────

final mqttServiceProvider = Provider<MqttService>((ref) {
  final svc = MqttService();
  ref.onDispose(() => svc.disconnect());
  return svc;
});

// ─── MODELO DE ESTADO ───────────────────────────────────────────

enum DeviceStatus { disconnected, scanning, connecting, connected }

class DeviceInfo {
  final DeviceStatus status;
  final String? name;
  final String? firmware;
  final int? battery;
  final String? deviceId;
  final String? errorMessage;

  const DeviceInfo({
    this.status = DeviceStatus.disconnected,
    this.name,
    this.firmware,
    this.battery,
    this.deviceId,
    this.errorMessage,
  });

  DeviceInfo copyWith({
    DeviceStatus? status,
    String? name,
    String? firmware,
    int? battery,
    String? deviceId,
    String? errorMessage,
  }) {
    return DeviceInfo(
      status: status ?? this.status,
      name: name ?? this.name,
      firmware: firmware ?? this.firmware,
      battery: battery ?? this.battery,
      deviceId: deviceId ?? this.deviceId,
      errorMessage: errorMessage,
    );
  }
}

// ─── SCAN RESULTS ───────────────────────────────────────────────

class ScanResult {
  final String id;
  final String name;
  final int rssi;

  ScanResult({
    required this.id,
    required this.name,
    required this.rssi,
  });
}

final scanResultsProvider =
StateProvider<List<ScanResult>>((ref) => []);

// ─── NOTIFIER ───────────────────────────────────────────────────

const _kLastDeviceId = 'ble_last_device_id';
const _kLastDeviceName = 'ble_last_device_name';

class DeviceNotifier extends StateNotifier<DeviceInfo>
    with WidgetsBindingObserver {
  final BleService _ble;
  final Ref _ref;

  StreamSubscription? _connSub;
  StreamSubscription? _scanSub;

  String? _lastDeviceId;
  String? _lastDeviceName;

  // true si el usuario pidio desconectar a proposito -- distingue eso
  // de una caida de conexion real, que si debe reintentar solo.
  bool _userDisconnected = false;

  // Backoff simple para los reintentos de reconexion automatica.
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  static const _reconnectDelaysSeconds = [2, 5, 10];

  DeviceNotifier(this._ble, this._ref)
      : super(const DeviceInfo()) {
    _init();
  }

  void _log(String msg) {
    print('[UI] $msg');
  }

  Future<void> _init() async {
    WidgetsBinding.instance.addObserver(this);

    final prefs = await SharedPreferences.getInstance();
    _lastDeviceId = prefs.getString(_kLastDeviceId);
    _lastDeviceName = prefs.getString(_kLastDeviceName);

    _connSub = _ble.connectionStateStream.listen(_onBleStateChange);

    _scanSub = _ble.scanResultsStream.listen((results) {
      _ref.read(scanResultsProvider.notifier).state = results
          .map((r) => ScanResult(
        id: r.id,
        name: r.name,
        rssi: r.rssi,
      ))
          .toList();
    });
  }

  // ─────────────────────────────────────────────────────────
  // CICLO DE VIDA — reconectar al volver a foreground si hace falta
  // ─────────────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    if (lifecycleState == AppLifecycleState.resumed) {
      _maybeReconnect();
    }
  }

  void _maybeReconnect() {
    if (_userDisconnected) return;
    if (state.status == DeviceStatus.connected ||
        state.status == DeviceStatus.connecting) {
      return;
    }
    if (_lastDeviceId == null) return;

    _log('Intentando reconectar a $_lastDeviceId...');
    _reconnectAttempt = 0;
    _attemptReconnect();
  }

  void _attemptReconnect() {
    _reconnectTimer?.cancel();

    if (_userDisconnected || _lastDeviceId == null) return;
    if (state.status == DeviceStatus.connected) return;

    connectTo(
      ScanResult(id: _lastDeviceId!, name: _lastDeviceName ?? 'Dispositivo', rssi: 0),
      isAutoReconnect: true,
    ).catchError((_) {});
  }

  void _scheduleReconnect() {
    if (_userDisconnected || _lastDeviceId == null) return;

    final delayIdx = _reconnectAttempt.clamp(0, _reconnectDelaysSeconds.length - 1);
    final delay = _reconnectDelaysSeconds[delayIdx];
    _reconnectAttempt++;

    _log('Reconexion automatica en ${delay}s (intento $_reconnectAttempt)...');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delay), _attemptReconnect);
  }

  void _onBleStateChange(BleConnectionState bleState) {
    switch (bleState) {
      case BleConnectionState.disconnected:
        state = state.copyWith(
          status: DeviceStatus.disconnected,
        );

        ForegroundBleService.stop();

        if (!_userDisconnected) {
          _scheduleReconnect();
        }
        break;

      case BleConnectionState.scanning:
        state = state.copyWith(
          status: DeviceStatus.scanning,
          errorMessage: null,
        );
        break;

      case BleConnectionState.connecting:
        state = state.copyWith(
          status: DeviceStatus.connecting,
          errorMessage: null,
        );
        break;

      case BleConnectionState.connected:
        _reconnectAttempt = 0;
        _reconnectTimer?.cancel();

        state = state.copyWith(
          status: DeviceStatus.connected,
          firmware: 'N/A',
          battery: null,
        );

        if (state.name != null) {
          ForegroundBleService.start(deviceName: state.name!);
        }
        break;
    }
  }

  Future<void> startScan() async {
    state = state.copyWith(
      status: DeviceStatus.scanning,
      errorMessage: null,
    );

    try {
      await _ble.startScan();
    } catch (e) {
      state = DeviceInfo(
        status: DeviceStatus.disconnected,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> stopScan() async {
    await _ble.stopScan();
  }

  Future<void> connectTo(ScanResult result, {bool isAutoReconnect = false}) async {
    _userDisconnected = false;

    state = state.copyWith(
      status: DeviceStatus.connecting,
      name: result.name,
      deviceId: result.id,
      errorMessage: null,
    );

    try {
      await _ble.connectToDevice(result.id);

      _lastDeviceId = result.id;
      _lastDeviceName = result.name;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLastDeviceId, result.id);
      await prefs.setString(_kLastDeviceName, result.name);
    } catch (e) {
      state = DeviceInfo(
        status: DeviceStatus.disconnected,
        errorMessage: isAutoReconnect ? null : 'Error al conectar: ${e.toString()}',
      );

      if (!isAutoReconnect) {
        // Fallo de conexion manual: no insistir en bucle, el usuario
        // decide si reintenta.
      } else if (!_userDisconnected) {
        _scheduleReconnect();
      }
    }
  }

  Future<void> disconnect() async {
    // El MQTT no se toca aqui: es independiente de la sesion BLE (ver
    // sensor_provider.dart), sigue conectado publicando datos simulados
    // si el usuario esta en modo demo aunque no haya ningun ESP32-S3.
    _userDisconnected = true;
    _reconnectTimer?.cancel();

    try {
      await ForegroundBleService.stop();
      await _ble.disconnect();
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reconnectTimer?.cancel();
    _connSub?.cancel();
    _scanSub?.cancel();
    super.dispose();
  }
}

// ─── PROVIDER ───────────────────────────────────────────────────

final deviceProvider =
StateNotifierProvider<DeviceNotifier, DeviceInfo>((ref) {
  final ble = ref.watch(bleServiceProvider);
  return DeviceNotifier(ble, ref);
});
