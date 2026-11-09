// lib/shared/providers/recording_provider.dart
//
// Providers de estado para la grabación de sesiones. La lógica de
// arrancar/parar/guardar vive en SensorDataNotifier (sensor_provider.dart),
// que es quien recibe los paquetes -- este fichero solo expone el estado
// que la UI necesita leer y el listado de sesiones ya guardadas.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/recording_session.dart';
import '../../core/services/export_service.dart';
import 'history_provider.dart';

final exportServiceProvider = Provider<ExportService>((ref) {
  return ExportService(ref.watch(historyServiceProvider));
});

/// true mientras hay una grabación activa (desde "Iniciar" hasta "Detener").
final isRecordingProvider = StateProvider<bool>((ref) => false);

/// Momento en el que arrancó la grabación activa -- null si no hay
/// ninguna en curso. La pantalla de Sesiones lo usa para el cronómetro.
final recordingStartedAtProvider = StateProvider<DateTime?>((ref) => null);

/// Pasos detectados durante la grabación activa (iniciado basado en fase
/// de marcha, no en el detector de pasos persistente -- ver
/// sensor_provider.dart).
final recordingStepCountProvider = StateProvider<int>((ref) => 0);

final recordingSessionsProvider = FutureProvider<List<RecordingSession>>((ref) {
  return ref.read(historyServiceProvider).getRecordingSessions();
});
