import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/ble_service.dart';

// ─── BLE SERVICE (singleton) ────────────────────────────────────────────────

final bleServiceProvider = Provider<BleService>((ref) {
  final svc = BleService();
  ref.onDispose(() => svc.dispose());
  return svc;
});

// ─── MODELO DE ESTADO ───────────────────────────────────────────────────────

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

// ─── SCAN RESULTS ───────────────────────────────────────────────────────────

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

// ─── NOTIFIER ───────────────────────────────────────────────────────────────

class DeviceNotifier extends StateNotifier<DeviceInfo> {
  final BleService _ble;
  final Ref _ref;

  StreamSubscription? _connSub;
  StreamSubscription? _scanSub;

  DeviceNotifier(this._ble, this._ref)
      : super(const DeviceInfo()) {
    _init();
  }

  void _log(String msg) {
    print('[UI] $msg');
  }

  void _init() {
    _log('Inicializando DeviceNotifier');

    _connSub = _ble.connectionStateStream.listen(_onBleStateChange);

    _scanSub = _ble.scanResultsStream.listen((results) {
      _log('Scan results recibidos: ${results.length}');

      _ref.read(scanResultsProvider.notifier).state = results
          .map((r) => ScanResult(
        id: r.id,
        name: r.name,
        rssi: r.rssi,
      ))
          .toList();
    });
  }

  // ─── BLE → UI STATE ──────────────────────────────────────────────────────

  void _onBleStateChange(BleConnectionState bleState) {
    _log('BLE state -> $bleState');

    switch (bleState) {
      case BleConnectionState.disconnected:
        state = state.copyWith(
          status: DeviceStatus.disconnected,
        );
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
        state = state.copyWith(
          status: DeviceStatus.connected,
          firmware: 'N/A',
          battery: null,
        );
        break;
    }
  }

  // ─── API PÚBLICA ─────────────────────────────────────────────────────────

  Future<void> startScan() async {
    _log('startScan()');

    state = state.copyWith(
      status: DeviceStatus.scanning,
      errorMessage: null,
    );

    try {
      await _ble.startScan();
    } catch (e) {
      _log('Error en scan: $e');

      state = DeviceInfo(
        status: DeviceStatus.disconnected,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> stopScan() async {
    _log('stopScan()');
    await _ble.stopScan();
  }

  Future<void> connectTo(ScanResult result) async {
    _log('connectTo() -> ${result.name} (${result.id})');

    state = state.copyWith(
      status: DeviceStatus.connecting,
      name: result.name,
      deviceId: result.id,
      errorMessage: null,
    );

    try {
      await _ble.connectToDevice(result.id);
      // ❗ NO tocar estado aquí → lo controla el stream BLE
    } catch (e) {
      _log('Error conectando: $e');

      state = DeviceInfo(
        status: DeviceStatus.disconnected,
        errorMessage: 'Error al conectar: ${e.toString()}',
      );
    }
  }

  Future<void> disconnect() async {
    _log('DeviceNotifier.disconnect() llamado');

    try {
      await _ble.disconnect();
      _log('BLE disconnect() completado');
    } catch (e) {
      _log('Error en disconnect: $e');
    }
  }

  // ─── CLEANUP ─────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _log('dispose()');

    _connSub?.cancel();
    _scanSub?.cancel();

    super.dispose();
  }
}

// ─── PROVIDER ───────────────────────────────────────────────────────────────

final deviceProvider =
StateNotifierProvider<DeviceNotifier, DeviceInfo>((ref) {
  final ble = ref.watch(bleServiceProvider);
  return DeviceNotifier(ble, ref);
});