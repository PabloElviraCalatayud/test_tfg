// lib/shared/models/recording_session.dart
//
// Metadatos de una sesión de grabación (sin las muestras en sí, ver
// RecordingSample). Es lo que se lista en la pantalla de Sesiones.

class RecordingSession {
  final int id;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String label;

  /// 'ble' (dispositivo real conectado) o 'fake' (datos simulados) --
  /// importante dejarlo claro en cualquier gráfica/export que salga de
  /// aquí, para no confundir una sesión de demostración con una real.
  final String source;

  final int sampleCount;
  final int stepCount;

  const RecordingSession({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    required this.label,
    required this.source,
    required this.sampleCount,
    required this.stepCount,
  });

  bool get isActive => endedAt == null;

  Duration get duration => (endedAt ?? DateTime.now()).difference(startedAt);

  bool get isFake => source == 'fake';
}
