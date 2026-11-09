// lib/core/utils/fake_data.dart
import 'dart:math';

/// Generates fully random sensor data within realistic physiological ranges.
/// No base values — every call produces independently random output.
class FakeData {
  static final _rng = Random();

  // ── Static device/user constants (no variation needed) ───────────────────
  static const String deviceName      = 'GaitSole ESP32';
  static const String firmwareVersion = '0.3.1-alpha';
  static const int    batteryPercent  = 78;

  static const String userName   = 'Alex García';
  static const String userSex    = 'Hombre';
  static const double userWeight = 75.0;
  static const double userHeight = 178.0;
  static const int    userAge    = 28;

  static const int stepGoal = 10000;

  // ── Random helpers ────────────────────────────────────────────────────────

  static double _rand(double min, double max) =>
      min + _rng.nextDouble() * (max - min);

  // ── Fully random snapshot ─────────────────────────────────────────────────

  /// Generates completely random values within physiological ranges.
  /// Call this every second for realistic-looking streaming data.
  static SensorDataSnapshot generateRandom({int stepCount = 6842}) {
    return SensorDataSnapshot(
      fsr: [
        // Toes T1–T3: light contact, occasional lift
        _rand(0.05, 0.60), _rand(0.05, 0.50), _rand(0.02, 0.40),
        // Metatarsals M1–M4: medium-high load
        _rand(0.40, 0.95), _rand(0.45, 0.98), _rand(0.35, 0.90), _rand(0.20, 0.75),
        // Midfoot arch MF1–MF2: low (arch is suspended)
        _rand(0.00, 0.20), _rand(0.00, 0.15),
        // Heel H1–H3: medium-high during stance
        _rand(0.30, 0.85), _rand(0.35, 0.90), _rand(0.25, 0.80),
      ],
      temperature: [
        _rand(29.5, 33.0), // Heel
        _rand(28.5, 32.0), // Arch (slightly cooler)
        _rand(31.0, 35.5), // Metatarsal
        _rand(30.5, 35.0), // Toes
      ],
      accX:  _rand(-2.0, 2.0),
      accY:  _rand(8.5, 10.8),   // ~gravity ±dynamic
      accZ:  _rand(-1.5, 1.5),
      gyroX: _rand(-15.0, 15.0),
      gyroY: _rand(-10.0, 10.0),
      gyroZ: _rand(-8.0, 8.0),
      magX:  _rand(15.0, 30.0),
      magY:  _rand(-20.0, -8.0),
      magZ:  _rand(35.0, 50.0),
      roll:  _rand(-12.0, 8.0),  // pronation/supination range
      pitch: _rand(-8.0, 10.0),
      yaw:   _rand(-20.0, 20.0),
      stepCount: stepCount,
      stepGoal:  stepGoal,
    );
  }

  /// Safe zero snapshot for BLE-disconnected state.
  /// Uses neutral values that prevent division-by-zero in all widgets.
  static SensorDataSnapshot zero() {
    return const SensorDataSnapshot(
      fsr: [0,0,0, 0,0,0,0, 0,0, 0,0,0],
      temperature: [30.5, 30.0, 30.8, 30.3], // safe neutral temps
      accX: 0, accY: 9.81, accZ: 0,
      gyroX: 0, gyroY: 0, gyroZ: 0,
      magX: 0, magY: 0, magZ: 0,
      roll: 0, pitch: 0, yaw: 0,
      stepCount: 0,
      stepGoal: stepGoal,
    );
  }

  // ── Simulación de marcha coherente ────────────────────────────────────────
  // generateRandom() de arriba da un valor independiente por campo y por
  // tick -- bueno para "ver números moviéndose" en el dashboard, pero
  // inútil para demostrar detección de pasos o fases de marcha (no hay
  // ninguna relación temporal entre un tick y el siguiente). Este
  // generador en cambio avanza una posición dentro del ciclo de marcha a
  // cada tick y reconstruye los 12 FSR a partir de las mismas curvas de
  // carga talón/mediopié/antepié del diagrama de la memoria (Capítulo 4,
  // "El ciclo de la marcha"), para poder usar el modo simulado como una
  // fuente de datos de demostración realista -- tanto para ver la fase
  // de marcha en vivo en el dashboard sin hardware conectado, como para
  // grabar y exportar una sesión de ejemplo con la que generar gráficas.
  static final GaitWalkSimulator walkSimulator = GaitWalkSimulator();

  static SensorDataSnapshot generateWalking(Duration dt, {required int stepCount}) {
    return walkSimulator.tick(dt, stepCount: stepCount, stepGoal: stepGoal);
  }
}

/// Avanza una zancada sintética en el tiempo y genera, en cada `tick`, una
/// lectura de sensores coherente con el punto del ciclo de marcha en el
/// que se encuentra (en vez de ruido independiente). Guarda estado propio
/// (posición en el ciclo, duración de zancada), así que debe vivir una
/// única instancia mientras dura una sesión (ver `FakeData.walkSimulator`).
class GaitWalkSimulator {
  final Random _rng = Random();

  double _cyclePos = 0.0; // 0..1, 0 = contacto inicial de esta zancada
  double _strideSeconds = 1.05;
  List<double>? _temp;

  // Puntos de control (porcentaje del ciclo, talón, mediopié, antepié),
  // igual que `loads` en el script que genera figuras/ciclo_marcha.svg --
  // así la simulación y la figura de la memoria cuentan la misma historia.
  static const List<(double, double, double, double)> _keyframes = [
    (0, 0.90, 0.15, 0.00), // contacto inicial
    (6, 0.80, 0.50, 0.10), // respuesta a la carga
    (20, 0.25, 0.90, 0.30), // apoyo medio
    (40, 0.10, 0.55, 0.75), // apoyo terminal
    (55, 0.00, 0.15, 0.90), // pre-oscilación / despegue
    (80, 0.00, 0.00, 0.00), // oscilación
    (100, 0.90, 0.15, 0.00), // contacto inicial de la siguiente zancada
  ];

  (double heel, double mid, double fore) _loadsAt(double pct) {
    for (int i = 0; i < _keyframes.length - 1; i++) {
      final a = _keyframes[i];
      final b = _keyframes[i + 1];
      if (pct >= a.$1 && pct <= b.$1) {
        final span = b.$1 - a.$1;
        final t = span == 0 ? 0.0 : (pct - a.$1) / span;
        return (
          a.$2 + (b.$2 - a.$2) * t,
          a.$3 + (b.$3 - a.$3) * t,
          a.$4 + (b.$4 - a.$4) * t,
        );
      }
    }
    return (0.0, 0.0, 0.0);
  }

  double _jitter(double v, double amount) =>
      (v + (_rng.nextDouble() * 2 - 1) * amount).clamp(0.0, 1.0);

  List<double> _temperatureWalk() {
    _temp ??= [30.5, 30.0, 32.5, 32.0];
    final next = <double>[];
    for (final t in _temp!) {
      next.add((t + (_rng.nextDouble() * 2 - 1) * 0.03).clamp(28.0, 36.0));
    }
    _temp = next;
    return next;
  }

  SensorDataSnapshot tick(Duration dt, {required int stepCount, required int stepGoal}) {
    _cyclePos += (dt.inMilliseconds / 1000.0) / _strideSeconds;
    if (_cyclePos >= 1.0) {
      _cyclePos -= 1.0;
      // Variabilidad de cadencia entre zancadas, como en una marcha real
      // (nunca son exactamente iguales).
      _strideSeconds = 0.95 + _rng.nextDouble() * 0.2;
    }

    final pct = _cyclePos * 100;
    final (heel, mid, fore) = _loadsAt(pct);

    final fsr = [
      // Dedos T1-T3
      _jitter(fore * 0.85, 0.05), _jitter(fore, 0.05), _jitter(fore * 0.70, 0.05),
      // Metatarsos M1-M4
      _jitter(fore, 0.06), _jitter(fore * 0.95, 0.06),
      _jitter(fore * 0.80, 0.06), _jitter(fore * 0.60, 0.06),
      // Arco MF1-MF2
      _jitter(mid, 0.03), _jitter(mid * 0.80, 0.03),
      // Talón H1-H3
      _jitter(heel * 0.90, 0.05), _jitter(heel, 0.05), _jitter(heel * 0.85, 0.05),
    ];

    // Pico de aceleración vertical cerca del contacto inicial (impacto del
    // talón) y balanceo lateral (roll) ligado a la fase del ciclo -- un
    // paseo sintético pero con la misma forma general que una IMU real.
    final impact = heel > 0.6 ? (heel - 0.6) * 5.0 : 0.0;
    final sway = sin(_cyclePos * 2 * pi) * 6.0;

    return SensorDataSnapshot(
      fsr: fsr,
      temperature: _temperatureWalk(),
      accX: sway * 0.2 + (_rng.nextDouble() * 2 - 1) * 0.3,
      accY: 9.81 + impact + (_rng.nextDouble() * 2 - 1) * 0.2,
      accZ: (_rng.nextDouble() * 2 - 1) * 0.4,
      gyroX: sway + (_rng.nextDouble() * 2 - 1) * 1.5,
      gyroY: (_rng.nextDouble() * 2 - 1) * 2.0,
      gyroZ: (_rng.nextDouble() * 2 - 1) * 1.5,
      magX: 22.0 + (_rng.nextDouble() * 2 - 1) * 1.0,
      magY: -14.0 + (_rng.nextDouble() * 2 - 1) * 1.0,
      magZ: 42.0 + (_rng.nextDouble() * 2 - 1) * 1.0,
      roll: sway,
      pitch: (fore - heel) * 6.0,
      yaw: (_rng.nextDouble() * 2 - 1) * 3.0,
      stepCount: stepCount,
      stepGoal: stepGoal,
    );
  }
}

/// Plain data transfer object. Mirrors SensorData fields but lives in
/// core/utils to avoid circular imports with shared/models.
class SensorDataSnapshot {
  final List<double> fsr;
  final List<double> temperature;
  final double accX, accY, accZ;
  final double gyroX, gyroY, gyroZ;
  final double magX, magY, magZ;
  final double roll, pitch, yaw;
  final int stepCount, stepGoal;

  const SensorDataSnapshot({
    required this.fsr,
    required this.temperature,
    required this.accX, required this.accY, required this.accZ,
    required this.gyroX, required this.gyroY, required this.gyroZ,
    required this.magX, required this.magY, required this.magZ,
    required this.roll, required this.pitch, required this.yaw,
    required this.stepCount, required this.stepGoal,
  });
}