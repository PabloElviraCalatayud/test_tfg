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