// lib/shared/models/recording_sample.dart
//
// Una fila de una grabación: una lectura completa de sensores en un
// instante dado, con la fase de marcha derivada y si en ese instante se
// detectó el inicio de un paso. Es la unidad que se guarda en
// `recording_samples` y la que se exporta a CSV.

import 'gait_phase.dart';

class RecordingSample {
  /// Milisegundos desde el inicio de la grabación (no un timestamp
  /// absoluto) -- así el CSV exportado tiene un eje X que empieza en 0,
  /// listo para graficar sin tener que restar nada.
  final int tMs;
  final List<double> fsr;
  final List<double> temperature;
  final double accX, accY, accZ;
  final double gyroX, gyroY, gyroZ;
  final double roll, pitch, yaw;
  final GaitPhase gaitPhase;
  final bool stepEdge;

  const RecordingSample({
    required this.tMs,
    required this.fsr,
    required this.temperature,
    required this.accX,
    required this.accY,
    required this.accZ,
    required this.gyroX,
    required this.gyroY,
    required this.gyroZ,
    required this.roll,
    required this.pitch,
    required this.yaw,
    required this.gaitPhase,
    required this.stepEdge,
  });
}
