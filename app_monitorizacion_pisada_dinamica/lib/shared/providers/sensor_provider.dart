import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/sensor_data.dart';
import '../models/mqtt_message.dart';
import '../../core/utils/fake_data.dart';
import '../../core/utils/packet_decoder.dart';
import '../../core/services/ble_service.dart';
import 'device_provider.dart';
import '../../core/services/mqtt_service.dart';

final useFakeDataProvider = StateProvider<bool>((ref) => true);
final _extraStepsProvider = StateProvider<int>((ref) => 0);
final stepGoalProvider = StateProvider<int>((ref) => FakeData.stepGoal);

final sensorDataProvider =
StateNotifierProvider<SensorDataNotifier, SensorData>((ref) {
  return SensorDataNotifier(ref);
});

class SensorDataNotifier extends StateNotifier<SensorData>
    with WidgetsBindingObserver {
  final Ref _ref;
  Timer? _fakeTimer;
  StreamSubscription? _bleSub;

  // ─────────────────────────────────────────────────────────
  // DETECCIÓN DE PASOS (datos BLE reales)
  // ─────────────────────────────────────────────────────────
  // El firmware no calcula pasos (packet_decoder siempre manda
  // stepCount=0): se detectan aquí por umbral con histéresis sobre el
  // pico de presión de los 12 FSR (valores normalizados 0..1). Se usa
  // el máximo (no la media) para que un único sensor presionado —como
  // al probar pulsando los FSR con la mano— ya cuente como paso.
  static const double _stepPressThreshold = 0.15;
  static const double _stepReleaseThreshold = 0.08;

  int _stepCount = 0;
  bool _stepArmed = true;

  int _detectSteps(List<double> fsr) {
    if (fsr.isEmpty) return _stepCount;

    final peak = fsr.reduce((a, b) => a > b ? a : b);

    if (_stepArmed && peak >= _stepPressThreshold) {
      _stepCount++;
      _stepArmed = false;
    } else if (!_stepArmed && peak <= _stepReleaseThreshold) {
      _stepArmed = true;
    }

    return _stepCount;
  }

  SensorDataNotifier(this._ref)
      : super(SensorData.fromSnapshot(FakeData.generateRandom())) {
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(_init);
  }

  Future<void> _init() async {
    if (!mounted) return;

    _ref.listen<bool>(useFakeDataProvider, (_, useFake) {
      _restartFlow();
    });

    _restartFlow();
  }

  // ─────────────────────────────────────────────────────────
  // LIFECYCLE
  // ─────────────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _onResume();
    }
  }

  void _onResume() {
    _restartFlow();
  }

  void _restartFlow() {
    _stopAll();

    if (_ref.read(useFakeDataProvider)) {
      _startFakeTimer();
    } else {
      _startBleListener();
      state = SensorData.fromSnapshot(FakeData.zero());
    }
  }

  // ─────────────────────────────────────────────────────────
  // MQTT
  // ─────────────────────────────────────────────────────────

  void _publish(MqttMessage msg) {
    final mqtt = _ref.read(mqttServiceProvider);
    if (!mqtt.isConnected) return;

    mqtt.publish(msg.topic, msg.toJson());
  }

  void _publishAll(SensorData data) {
    final rawDeviceId = _ref.read(deviceProvider).deviceId ?? "unknown";
    final topicDeviceId = rawDeviceId.replaceAll(':', '');

    _publish(
      MqttMessage(
        topic: "flutter_pisada/$topicDeviceId/telemetry",
        deviceId: rawDeviceId,
        timestamp: DateTime.now(),
        data: {
          "fsr": data.fsr,
          "temperature": data.temperature,

          "acc_x": data.accX,
          "acc_y": data.accY,
          "acc_z": data.accZ,

          "gyro_x": data.gyroX,
          "gyro_y": data.gyroY,
          "gyro_z": data.gyroZ,

          "mag_x": data.magX,
          "mag_y": data.magY,
          "mag_z": data.magZ,

          "roll": data.roll,
          "pitch": data.pitch,
          "yaw": data.yaw,

          "step_count": data.stepCount,
          "step_goal": data.stepGoal,
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // FAKE DATA
  // ─────────────────────────────────────────────────────────

  void _startFakeTimer() {
    _fakeTimer?.cancel();
    _fakeTimer = Timer.periodic(const Duration(seconds: 1), (_) => _fakeTick());
    _fakeTick();
  }

  void _fakeTick() {
    if (!mounted) return;

    final extra = _ref.read(_extraStepsProvider) + 1;
    _ref.read(_extraStepsProvider.notifier).state = extra;

    final newData = SensorData.fromSnapshot(
      FakeData.generateRandom(stepCount: 6842 + extra),
    );

    state = newData;
    _publishAll(newData);
  }

  // ─────────────────────────────────────────────────────────
  // BLE DATA
  // ─────────────────────────────────────────────────────────

  void _startBleListener() {
    final ble = _ref.read(bleServiceProvider);

    _bleSub?.cancel();
    _bleSub = ble.packetStream.listen((packet) {
      if (!mounted) return;

      if (packet is SensorPacket) {
        final goal = _ref.read(stepGoalProvider);

        final newData = SensorData(
          fsr: packet.data.fsr,
          temperature: packet.data.temperature,
          accX: packet.data.accX,
          accY: packet.data.accY,
          accZ: packet.data.accZ,
          gyroX: packet.data.gyroX,
          gyroY: packet.data.gyroY,
          gyroZ: packet.data.gyroZ,
          magX: packet.data.magX,
          magY: packet.data.magY,
          magZ: packet.data.magZ,
          roll: packet.data.roll,
          pitch: packet.data.pitch,
          yaw: packet.data.yaw,
          stepCount: _detectSteps(packet.data.fsr),
          stepGoal: goal,
        );

        state = newData;
        _publishAll(newData);
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
    WidgetsBinding.instance.removeObserver(this);
    _stopAll();
    super.dispose();
  }
}