// lib/shared/models/sensor_data.dart
import '../../core/utils/fake_data.dart';

class SensorData {
  final List<double> fsr;
  final List<double> temperature;
  final double accX, accY, accZ;
  final double gyroX, gyroY, gyroZ;
  final double magX, magY, magZ;
  final double roll, pitch, yaw;
  final int stepCount, stepGoal;

  const SensorData({
    required this.fsr, required this.temperature,
    required this.accX, required this.accY, required this.accZ,
    required this.gyroX, required this.gyroY, required this.gyroZ,
    required this.magX, required this.magY, required this.magZ,
    required this.roll, required this.pitch, required this.yaw,
    required this.stepCount, required this.stepGoal,
  });

  factory SensorData.fromSnapshot(SensorDataSnapshot s) {
    return SensorData(
      fsr: s.fsr, temperature: s.temperature,
      accX: s.accX, accY: s.accY, accZ: s.accZ,
      gyroX: s.gyroX, gyroY: s.gyroY, gyroZ: s.gyroZ,
      magX: s.magX, magY: s.magY, magZ: s.magZ,
      roll: s.roll, pitch: s.pitch, yaw: s.yaw,
      stepCount: s.stepCount, stepGoal: s.stepGoal,
    );
  }

  /// Average temperature — safe against empty list.
  double get avgTemperature {
    if (temperature.isEmpty) return 30.0;
    return temperature.reduce((a, b) => a + b) / temperature.length;
  }

  /// Min temperature — safe against all-equal values.
  double get minTemperature {
    if (temperature.isEmpty) return 29.0;
    return temperature.reduce((a, b) => a < b ? a : b);
  }

  /// Max temperature — safe, always > minTemperature.
  double get maxTemperature {
    if (temperature.isEmpty) return 35.0;
    final mx = temperature.reduce((a, b) => a > b ? a : b);
    final mn = minTemperature;
    return mx == mn ? mn + 0.1 : mx; // prevent division by zero
  }

  /// Reparto relativo de la presión entre los 12 sensores FSR, en % del
  /// peso total detectado en este instante (suma siempre <= 100%, nunca
  /// se excede). Con sensores de bajo coste como estos, un valor absoluto
  /// (gramos) no es fiable entre sensores -- el reparto relativo si es
  /// interpretable ("el sensor 7 se lleva el 18% de tu peso al pisar") y
  /// no depende de la calibración exacta de cada unidad.
  ///
  /// OJO: es un valor derivado solo para mostrar en pantalla. La detección
  /// de pasos y el centro de presión siguen usando `fsr` (normalizado por
  /// el fondo de escala fijo), no este getter, para no romper su ajuste ya
  /// validado.
  List<double> get relativePercent {
    if (fsr.isEmpty) return const [];
    final total = fsr.fold(0.0, (sum, v) => sum + v);
    if (total <= 0) return List.filled(fsr.length, 0.0);
    return fsr.map((v) => (v / total) * 100).toList();
  }

  /// Pressure-weighted centre of pressure (x, y) in 0..1 space.
  /// x: medial(0) – lateral(1), y: heel(0) – toe(1)
  /// Debe coincidir con _fsrPositions en pressure_map_widget.dart (12 FSR reales).
  (double, double) get centerOfPressure {
    const positions = [
      (0.40, 0.93), (0.50, 0.95), (0.60, 0.92),               // dedos
      (0.32, 0.74), (0.44, 0.77), (0.56, 0.76), (0.66, 0.71), // metatarsos
      (0.36, 0.52), (0.60, 0.50),                              // arco
      (0.36, 0.22), (0.48, 0.19), (0.60, 0.22),                // talón
    ];
    double totalW = 0, cx = 0, cy = 0;
    for (int i = 0; i < fsr.length && i < positions.length; i++) {
      final w = fsr[i];
      cx += positions[i].$1 * w;
      cy += positions[i].$2 * w;
      totalW += w;
    }
    if (totalW == 0) return (0.46, 0.50);
    return (cx / totalW, cy / totalW);
  }
}