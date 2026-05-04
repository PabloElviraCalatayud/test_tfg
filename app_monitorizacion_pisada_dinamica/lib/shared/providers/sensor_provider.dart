// lib/shared/providers/sensor_provider.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/sensor_data.dart';
import '../../core/utils/fake_data.dart';
import '../../core/utils/packet_decoder.dart';
import '../../core/services/ble_service.dart';
import 'device_provider.dart';

/// Alterna entre datos simulados y datos BLE reales.
final useFakeDataProvider = StateProvider<bool>((ref) => true);

/// Pasos acumulados durante la sesión de datos simulados.
final _extraStepsProvider = StateProvider<int>((ref) => 0);

/// Objetivo de pasos editable por el usuario.
final stepGoalProvider = StateProvider<int>((ref) => FakeData.stepGoal);

/// Proveedor principal de datos de sensores.
/// • useFakeData = true  → genera datos aleatorios cada 1 segundo.
/// • useFakeData = false → espera notificaciones BLE reales del ESP32.
final sensorDataProvider =
StateNotifierProvider<SensorDataNotifier, SensorData>((ref) {
  return SensorDataNotifier(ref);
});

class SensorDataNotifier extends StateNotifier<SensorData> {
  final Ref _ref;
  Timer?              _fakeTimer;
  StreamSubscription? _bleSub;

  SensorDataNotifier(this._ref)
      : super(SensorData.fromSnapshot(FakeData.generateRandom())) {
    Future.microtask(_init);
  }

  Future<void> _init() async {
    if (!mounted) return;

    // Reacciona a cambios del toggle simulado/real
    _ref.listen<bool>(useFakeDataProvider, (_, useFake) {
      _stopAll();
      if (useFake) {
        _startFakeTimer();
      } else {
        _startBleListener();
        // Estado neutro inmediato hasta que llegue el primer paquete BLE
        state = SensorData.fromSnapshot(FakeData.zero());
      }
    });

    // Arranca según el valor inicial
    if (_ref.read(useFakeDataProvider)) {
      _startFakeTimer();
    } else {
      _startBleListener();
      state = SensorData.fromSnapshot(FakeData.zero());
    }
  }

  // ── Datos simulados ──────────────────────────────────────────────────────────

  void _startFakeTimer() {
    _fakeTimer?.cancel();
    _fakeTimer = Timer.periodic(const Duration(seconds: 1), (_) => _fakeTick());
    _fakeTick(); // primer valor inmediato
  }

  void _fakeTick() {
    if (!mounted) return;
    final extra = _ref.read(_extraStepsProvider) + 1;
    _ref.read(_extraStepsProvider.notifier).state = extra;
    state = SensorData.fromSnapshot(
      FakeData.generateRandom(stepCount: 6842 + extra),
    );
  }

  // ── Datos BLE reales ──────────────────────────────────────────────────────────

  void _startBleListener() {
    final ble = _ref.read(bleServiceProvider);
    _bleSub?.cancel();
    _bleSub = ble.packetStream.listen((packet) {
      if (!mounted) return;
      if (packet is SensorPacket) {
        // Preservar el objetivo de pasos que el usuario puede haber editado
        final goal = _ref.read(stepGoalProvider);
        state = SensorData(
          fsr:         packet.data.fsr,
          temperature: packet.data.temperature,
          accX:  packet.data.accX,  accY: packet.data.accY,  accZ: packet.data.accZ,
          gyroX: packet.data.gyroX, gyroY: packet.data.gyroY, gyroZ: packet.data.gyroZ,
          magX:  packet.data.magX,  magY: packet.data.magY,  magZ: packet.data.magZ,
          roll:  packet.data.roll,  pitch: packet.data.pitch, yaw: packet.data.yaw,
          stepCount: packet.data.stepCount,
          stepGoal:  goal,
        );
      }
    });
  }

  void _stopAll() {
    _fakeTimer?.cancel();
    _fakeTimer = null;
    _bleSub?.cancel();
    _bleSub = null;
  }

  @override
  void dispose() {
    _stopAll();
    super.dispose();
  }
}