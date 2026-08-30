// lib/shared/models/step_event.dart

/// Instantánea de los 12 FSR y 4 termistores en el momento exacto en que
/// se detectó un paso. Es lo que permite la trazabilidad del historial:
/// no solo "cuántos pasos diste", sino "cómo pisabas" en cada uno.
class StepEvent {
  final DateTime timestamp;
  final List<double> fsr;
  final List<double> temperature;

  const StepEvent({
    required this.timestamp,
    required this.fsr,
    required this.temperature,
  });

  /// Reparto relativo de presión en % del peso total en ese paso concreto
  /// (suma <=100%). Mismo criterio que SensorData.relativePercent, para
  /// que un valor de trazabilidad se lea igual que en el dashboard en vivo.
  List<double> get relativePercent {
    if (fsr.isEmpty) return const [];
    final total = fsr.fold(0.0, (sum, v) => sum + v);
    if (total <= 0) return List.filled(fsr.length, 0.0);
    return fsr.map((v) => (v / total) * 100).toList();
  }

  double get avgTemperature {
    if (temperature.isEmpty) return 0;
    return temperature.reduce((a, b) => a + b) / temperature.length;
  }
}
