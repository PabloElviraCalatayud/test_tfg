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
import 'history_provider.dart';

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
  StreamSubscription? _bleConnStateSub;

  // ─────────────────────────────────────────────────────────
  // DETECCIÓN DE PASOS (datos BLE reales)
  // ─────────────────────────────────────────────────────────
  // El firmware no calcula pasos (packet_decoder siempre manda
  // stepCount=0): se detectan aquí sobre el pico de presión de los 12
  // FSR (valores normalizados 0..1). Se usa el máximo (no la media)
  // para que un único sensor presionado —como al probar pulsando los
  // FSR con la mano— ya cuente como paso.
  //
  // Un umbral ABSOLUTO (p.ej. "cuenta si peak >= 0.15") asume que "sin
  // presión" lee cerca de 0. En la práctica el reposo de este hardware
  // se ha visto asentado en ~0.17 (precarga mecánica del sensor/insuela)
  // y ahí se queda siempre por encima de cualquier umbral razonable: se
  // arma una vez al conectar y ya no vuelve a bajar nunca -> nunca vuelve
  // a contar. Por eso se detecta la SUBIDA relativa (delta entre paquetes
  // consecutivos) en vez del nivel absoluto: da igual en que nivel esté
  // el reposo, un paso siempre implica un salto hacia arriba seguido, mas
  // tarde, de uno hacia abajo.
  static const double _stepRiseThreshold = 0.01; // ~1000 g de subida entre paquetes

  double? _lastPeak; // null = aun no se ha fijado la base tras (re)conectar
  int _stepCount = 0;
  bool _stepArmed = true;

  int _detectSteps(List<double> fsr) {
    if (fsr.isEmpty) {
      debugPrint('[STEPS] fsr vacio, no se puede detectar nada');
      return _stepCount;
    }

    final peak = fsr.reduce((a, b) => a > b ? a : b);

    if (_lastPeak == null) {
      // Primera lectura tras (re)conectar: solo fija la base (sea cual
      // sea el reposo real), no cuenta como paso.
      _lastPeak = peak;
      debugPrint('[STEPS] base inicial fijada en peak=${peak.toStringAsFixed(4)}');
      return _stepCount;
    }

    final delta = peak - _lastPeak!;
    _lastPeak = peak;

    if (_stepArmed && delta >= _stepRiseThreshold) {
      _stepCount++;
      _stepArmed = false;
      debugPrint('[STEPS] ¡PASO! peak=${peak.toStringAsFixed(4)} '
          'delta=${delta.toStringAsFixed(4)} -> total=$_stepCount');

      // Fire-and-forget: no bloquea el procesado del siguiente paquete BLE.
      // Solo pasos reales (datos BLE) se persisten -- _fakeTick() nunca
      // llama a _detectSteps, asi que el modo demo no contamina el historial.
      _ref.read(historyServiceProvider).incrementToday(1).catchError((e) {
        debugPrint('[STEPS] Error guardando en el historial: $e');
      });
    } else if (!_stepArmed && delta <= -_stepRiseThreshold) {
      _stepArmed = true;
      debugPrint('[STEPS] rearmado peak=${peak.toStringAsFixed(4)} '
          'delta=${delta.toStringAsFixed(4)}');
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

    // Siembra el contador en memoria con lo ya guardado hoy, para que un
    // relanzamiento de la app el mismo dia no muestre el contador a 0
    // mientras llega el primer paquete BLE.
    try {
      _stepCount = await _ref.read(historyServiceProvider).getTodaySteps();
    } catch (e) {
      debugPrint('[STEPS] Error leyendo historial de hoy: $e');
    }

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

    final useFake = _ref.read(useFakeDataProvider);
    debugPrint('[STEPS] _restartFlow useFakeData=$useFake');

    if (useFake) {
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
    debugPrint('[STEPS] _startBleListener: suscrito a ble.packetStream');

    /*
     * _lastPeak SOLO se re-fija en una conexion GATT genuinamente nueva,
     * nunca aqui. Antes se reseteaba en cada llamada a este metodo, que
     * se dispara en cada _restartFlow() -- y _restartFlow() se llama en
     * CADA resume de la app (ver didChangeAppLifecycleState), pase lo
     * que pase con la conexion BLE real. Resultado: minimizar/reabrir la
     * app a mitad de zancada borraba la base sin motivo, dando la
     * impresion de que el contador de pasos "no funcionaba".
     */
    _bleConnStateSub?.cancel();
    BleConnectionState? lastBleState;
    _bleConnStateSub = ble.connectionStateStream.listen((bleState) {
      if (bleState == BleConnectionState.connected &&
          lastBleState != BleConnectionState.connected) {
        _lastPeak = null;
        _stepArmed = true;
        debugPrint('[STEPS] Conexion BLE nueva -> base de pasos reseteada');
      }
      lastBleState = bleState;
    });

    _bleSub?.cancel();
    _bleSub = ble.packetStream.listen((packet) {
      if (!mounted) return;

      if (packet is SensorPacket) {
        final goal = _ref.read(stepGoalProvider);
        final newStepCount = _detectSteps(packet.data.fsr);

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
          stepCount: newStepCount,
          stepGoal: goal,
        );

        state = newData;
        _publishAll(newData);
      } else {
        debugPrint('[STEPS] Paquete recibido pero NO es SensorPacket: ${packet.runtimeType}');
      }
    });
  }

  void _stopAll() {
    _fakeTimer?.cancel();
    _fakeTimer = null;
    _bleSub?.cancel();
    _bleSub = null;
    _bleConnStateSub?.cancel();
    _bleConnStateSub = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopAll();
    super.dispose();
  }
}