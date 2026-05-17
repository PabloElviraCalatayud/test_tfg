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
    final deviceId = _ref.read(deviceProvider).deviceId ?? "unknown";
    final baseTopic = "esp32/$deviceId";
    final now = DateTime.now();

    _publish(MqttMessage(
      topic: "$baseTopic/pressure",
      deviceId: deviceId,
      timestamp: now,
      data: {
        "fsr": data.fsr,
      },
    ));

    _publish(MqttMessage(
      topic: "$baseTopic/temperature",
      deviceId: deviceId,
      timestamp: now,
      data: {
        "temperature": data.temperature,
      },
    ));

    _publish(MqttMessage(
      topic: "$baseTopic/imu",
      deviceId: deviceId,
      timestamp: now,
      data: {
        "acc": [data.accX, data.accY, data.accZ],
        "gyro": [data.gyroX, data.gyroY, data.gyroZ],
        "mag": [data.magX, data.magY, data.magZ],
      },
    ));

    _publish(MqttMessage(
      topic: "$baseTopic/orientation",
      deviceId: deviceId,
      timestamp: now,
      data: {
        "roll": data.roll,
        "pitch": data.pitch,
        "yaw": data.yaw,
      },
    ));

    _publish(MqttMessage(
      topic: "$baseTopic/steps",
      deviceId: deviceId,
      timestamp: now,
      data: {
        "steps": data.stepCount,
        "goal": data.stepGoal,
      },
    ));
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
          stepCount: packet.data.stepCount,
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