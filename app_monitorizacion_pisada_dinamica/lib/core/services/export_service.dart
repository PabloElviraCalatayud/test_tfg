// lib/core/services/export_service.dart
//
// Convierte una sesión grabada (ver history_service.dart /
// recording_provider.dart) en un CSV de columnas anchas -- una fila por
// muestra, una columna por sensor -- listo para abrir en Excel, pandas o
// el script de graficas (tools/plot_session.py) y generar figuras para la
// memoria (presión, temperatura, fase del ciclo de marcha).
//
// No se usa ningún paquete de CSV: el formato es tan simple (números y un
// puñado de códigos de fase sin comas) que escribirlo a mano con
// StringBuffer evita una dependencia más.

import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../shared/models/recording_session.dart';
import 'history_service.dart';

class ExportService {
  final HistoryService _history;
  const ExportService(this._history);

  static const List<String> csvHeader = [
    't_ms',
    'timestamp_iso',
    'fsr_0', 'fsr_1', 'fsr_2', 'fsr_3', 'fsr_4', 'fsr_5',
    'fsr_6', 'fsr_7', 'fsr_8', 'fsr_9', 'fsr_10', 'fsr_11',
    'temp_0', 'temp_1', 'temp_2', 'temp_3',
    'acc_x', 'acc_y', 'acc_z',
    'gyro_x', 'gyro_y', 'gyro_z',
    'roll', 'pitch', 'yaw',
    'gait_phase',
    'step_edge',
  ];

  List<double> _decodeDoubleList(Object? raw, int expectedLength) {
    final list = (jsonDecode(raw as String) as List)
        .map((e) => (e as num).toDouble())
        .toList();
    if (list.length == expectedLength) return list;
    // Defensivo: si algún día cambia el número de sensores, no queremos
    // que una fila con menos/más campos rompa el CSV entero.
    return List<double>.generate(
      expectedLength,
      (i) => i < list.length ? list[i] : 0.0,
    );
  }

  /// Construye el CSV completo como String, sin tocar disco -- separado de
  /// `exportAndShare` para poder generarlo/inspeccionarlo sin I/O.
  Future<String> buildSessionCsv(RecordingSession session) async {
    final rows = await _history.getRecordingSamplesRaw(session.id);

    final buffer = StringBuffer()..writeln(csvHeader.join(','));

    for (final r in rows) {
      final tMs = r['t_ms'] as int;
      final fsr = _decodeDoubleList(r['fsr'], 12);
      final temp = _decodeDoubleList(r['temperature'], 4);
      final ts = session.startedAt.add(Duration(milliseconds: tMs));

      final fields = <String>[
        tMs.toString(),
        ts.toIso8601String(),
        for (final v in fsr) v.toStringAsFixed(4),
        for (final v in temp) v.toStringAsFixed(2),
        (r['acc_x'] as num).toStringAsFixed(4),
        (r['acc_y'] as num).toStringAsFixed(4),
        (r['acc_z'] as num).toStringAsFixed(4),
        (r['gyro_x'] as num).toStringAsFixed(4),
        (r['gyro_y'] as num).toStringAsFixed(4),
        (r['gyro_z'] as num).toStringAsFixed(4),
        (r['roll'] as num).toStringAsFixed(3),
        (r['pitch'] as num).toStringAsFixed(3),
        (r['yaw'] as num).toStringAsFixed(3),
        r['gait_phase'] as String,
        (r['step_edge'] as int).toString(),
      ];
      buffer.writeln(fields.join(','));
    }

    return buffer.toString();
  }

  String _fileNameFor(RecordingSession session) {
    final d = session.startedAt;
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${d.year}${two(d.month)}${two(d.day)}'
        '_${two(d.hour)}${two(d.minute)}${two(d.second)}';
    return 'gaitsole_sesion_${stamp}_${session.source}.csv';
  }

  /// Escribe el CSV en el directorio temporal de la app y abre el panel
  /// nativo para compartir/guardar -- así el usuario decide el destino
  /// (Drive, Archivos, email, AirDrop...) sin que la app pida permisos de
  /// almacenamiento adicionales solo para esto.
  Future<void> exportAndShare(RecordingSession session) async {
    final csv = await buildSessionCsv(session);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${_fileNameFor(session)}');
    await file.writeAsString(csv);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv')],
      subject: session.label,
      text: 'Datos de la sesión "${session.label}" '
          '(${session.sampleCount} muestras, origen: ${session.source}).',
    );
  }
}
