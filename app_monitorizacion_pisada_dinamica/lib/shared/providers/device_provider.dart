// lib/shared/providers/device_provider.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/ble_service.dart';

// ─── Singleton del servicio BLE ───────────────────────────────────────────────
// Se mantiene vivo durante toda la sesión de la app.
final bleServiceProvider = Provider<BleService>((ref) {
  final svc = BleService();
  ref.onDispose(svc.dispose);
  return svc;
});

// ─── Modelo de estado del dispositivo ────────────────────────────────────────

class DeviceInfo {
  final DeviceStatus status;
  final String?      name;
  final String?      firmware;
  final int?         battery;
  final String?      deviceId;
  final String?      errorMessage;

  const DeviceInfo({
    this.status       = DeviceStatus.disconnected,
    this.name,
    this.firmware,
    this.battery,
    this.deviceId,
    this.errorMessage,
  });

  DeviceInfo copyWith({
    DeviceStatus? status,
    String?       name,
    String?       firmware,
    int?          battery,
    String?       deviceId,
    String?       errorMessage,
  }) => DeviceInfo(
    status:       status       ?? this.status,
    name:         name         ?? this.name,
    firmware:     firmware     ?? this.firmware,
    battery:      battery      ?? this.battery,
    deviceId:     deviceId     ?? this.deviceId,
    errorMessage: errorMessage,               // nullable — se pasa explícito
  );
}

enum DeviceStatus { disconnected, scanning, connecting, connected }

// ─── Resultados del scan ──────────────────────────────────────────────────────

class ScanResult {
  final String id;
  final String name;
  final int    rssi;
  ScanResult({required this.id, required this.name, required this.rssi});
}

final scanResultsProvider = StateProvider<List<ScanResult>>((ref) => []);

// ─── Notifier principal ───────────────────────────────────────────────────────

class DeviceNotifier extends StateNotifier<DeviceInfo> {
  final BleService _ble;
  final Ref        _ref;

  StreamSubscription? _connSub;
  StreamSubscription? _scanSub;

  DeviceNotifier(this._ble, this._ref) : super(const DeviceInfo()) {
    _connSub = _ble.connectionStateStream.listen(_onBleStateChange);
    _scanSub = _ble.scanResultsStream.listen((results) {
      _ref.read(scanResultsProvider.notifier).state = results
          .map((r) => ScanResult(id: r.id, name: r.name, rssi: r.rssi))
          .toList();
    });
  }

  void _onBleStateChange(BleConnectionState bleState) {
    switch (bleState) {
      case BleConnectionState.disconnected:
        state = const DeviceInfo(status: DeviceStatus.disconnected);
        break;
      case BleConnectionState.scanning:
        state = state.copyWith(status: DeviceStatus.scanning);
        break;
      case BleConnectionState.connecting:
        state = state.copyWith(status: DeviceStatus.connecting);
        break;
      case BleConnectionState.connected:
      // Nombre del dispositivo viene del BLE scan (ya guardado en deviceId/name)
        state = state.copyWith(
          status:   DeviceStatus.connected,
          firmware: 'N/A', // TODO: leer de característica de info del dispositivo
          battery:  null,  // TODO: leer de Battery Service estándar (0x180F)
        );
        break;
    }
  }

  // ─── API pública ─────────────────────────────────────────────────────────────

  Future<void> startScan() async {
    state = state.copyWith(status: DeviceStatus.scanning, errorMessage: null);
    try {
      await _ble.startScan();
    } catch (e) {
      state = DeviceInfo(
        status:       DeviceStatus.disconnected,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> stopScan() => _ble.stopScan();

  Future<void> connectTo(ScanResult result) async {
    state = DeviceInfo(
      status:   DeviceStatus.connecting,
      name:     result.name,
      deviceId: result.id,
    );
    try {
      await _ble.connectToDevice(result.id);
      state = state.copyWith(
        status: DeviceStatus.connected,
        name:   result.name,
      );
    } catch (e) {
      state = DeviceInfo(
        status:       DeviceStatus.disconnected,
        errorMessage: 'Error al conectar: ${e.toString()}',
      );
    }
  }

  Future<void> disconnect() async {
    await _ble.disconnect();
    state = const DeviceInfo(status: DeviceStatus.disconnected);
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _scanSub?.cancel();
    super.dispose();
  }
}

final deviceProvider =
StateNotifierProvider<DeviceNotifier, DeviceInfo>((ref) {
  final ble = ref.watch(bleServiceProvider);
  return DeviceNotifier(ble, ref);
});