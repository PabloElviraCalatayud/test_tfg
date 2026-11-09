// lib/core/services/history_service.dart
//
// Persistencia local del historial de pasos (sqflite). Es el unico sitio
// que sabe leer/escribir las tablas daily_steps/step_events -- todo lo
// demas pasa por esta clase.

import 'dart:convert';
import 'dart:math';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../../shared/models/daily_step_entry.dart';
import '../../shared/models/step_event.dart';
import '../../shared/models/gait_phase.dart';
import '../../shared/models/recording_sample.dart';
import '../../shared/models/recording_session.dart';

class HistoryService {
  Database? _db;

  String _dateKey(DateTime d) {
    // 'YYYY-MM-DD', fecha local (sin hora), para poder usarla como
    // PRIMARY KEY y en comparaciones de rango por texto.
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  Future<Database> _database() async {
    if (_db != null) return _db!;

    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'gait_history.db');

    _db = await openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE daily_steps (
            date       TEXT PRIMARY KEY,
            step_count INTEGER NOT NULL DEFAULT 0,
            updated_at INTEGER NOT NULL
          )
        ''');
        await _createStepEventsTable(db);
        await _createRecordingTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createStepEventsTable(db);
        }
        if (oldVersion < 3) {
          await _createRecordingTables(db);
        }
      },
    );

    return _db!;
  }

  Future<void> _createStepEventsTable(Database db) async {
    // fsr/temperature se guardan como JSON de una lista de doubles: sqlite
    // no tiene tipo array nativo y son solo 12+4 numeros, no hace falta
    // normalizar en columnas ni en una tabla aparte por sensor.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS step_events (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        date        TEXT NOT NULL,
        timestamp   INTEGER NOT NULL,
        fsr         TEXT NOT NULL,
        temperature TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_step_events_date ON step_events(date)',
    );
  }

  Future<void> _createRecordingTables(Database db) async {
    // Grabaciones explícitas, iniciadas por el usuario desde la pantalla
    // de Sesiones -- a diferencia de step_events (solo una instantánea
    // por paso detectado), aquí se guarda CADA muestra recibida mientras
    // dura la grabación, para poder reconstruir series temporales
    // completas de presión/temperatura/fase de marcha y exportarlas a
    // CSV para generar gráficas.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS recording_sessions (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        started_at INTEGER NOT NULL,
        ended_at   INTEGER,
        label      TEXT NOT NULL,
        source     TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS recording_samples (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        t_ms       INTEGER NOT NULL,
        fsr         TEXT NOT NULL,
        temperature TEXT NOT NULL,
        acc_x  REAL NOT NULL, acc_y  REAL NOT NULL, acc_z  REAL NOT NULL,
        gyro_x REAL NOT NULL, gyro_y REAL NOT NULL, gyro_z REAL NOT NULL,
        roll REAL NOT NULL, pitch REAL NOT NULL, yaw REAL NOT NULL,
        gait_phase TEXT NOT NULL,
        step_edge  INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_recording_samples_session '
      'ON recording_samples(session_id)',
    );
  }

  // ─────────────────────────────────────────────────────────
  // GRABACIÓN DE SESIONES (para exportar y generar gráficas)
  // ─────────────────────────────────────────────────────────

  /// Crea una nueva sesión de grabación y devuelve su id. `source` debe
  /// ser 'ble' o 'fake', para dejar claro en cualquier export si los
  /// datos vienen de un dispositivo real o de la simulación.
  Future<int> startRecordingSession({
    required String source,
    String? label,
  }) async {
    final db = await _database();
    final now = DateTime.now();
    final effectiveLabel = label ?? _defaultSessionLabel(now);

    return db.insert('recording_sessions', {
      'started_at': now.millisecondsSinceEpoch,
      'ended_at': null,
      'label': effectiveLabel,
      'source': source,
    });
  }

  String _defaultSessionLabel(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'Sesión ${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}';
  }

  /// Inserta un lote de muestras de golpe (db.batch) -- se llama cada
  /// pocos segundos con el buffer acumulado en memoria, nunca una a una
  /// por paquete BLE, para no machacar sqlite a 30-50 escrituras/segundo.
  Future<void> appendRecordingSamples(
    int sessionId,
    List<RecordingSample> samples,
  ) async {
    if (samples.isEmpty) return;
    final db = await _database();
    final batch = db.batch();

    for (final s in samples) {
      batch.insert('recording_samples', {
        'session_id': sessionId,
        't_ms': s.tMs,
        'fsr': jsonEncode(s.fsr),
        'temperature': jsonEncode(s.temperature),
        'acc_x': s.accX, 'acc_y': s.accY, 'acc_z': s.accZ,
        'gyro_x': s.gyroX, 'gyro_y': s.gyroY, 'gyro_z': s.gyroZ,
        'roll': s.roll, 'pitch': s.pitch, 'yaw': s.yaw,
        'gait_phase': s.gaitPhase.csvCode,
        'step_edge': s.stepEdge ? 1 : 0,
      });
    }

    await batch.commit(noResult: true);
  }

  Future<void> endRecordingSession(int sessionId) async {
    final db = await _database();
    await db.update(
      'recording_sessions',
      {'ended_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  /// Lista todas las sesiones de grabación, más recientes primero, con el
  /// número de muestras y de pasos detectados ya agregados -- evita que
  /// la pantalla de Sesiones tenga que hacer una consulta aparte por fila.
  Future<List<RecordingSession>> getRecordingSessions() async {
    final db = await _database();
    final rows = await db.rawQuery('''
      SELECT s.id, s.started_at, s.ended_at, s.label, s.source,
             COUNT(r.id) AS sample_count,
             COALESCE(SUM(r.step_edge), 0) AS step_count
      FROM recording_sessions s
      LEFT JOIN recording_samples r ON r.session_id = s.id
      GROUP BY s.id
      ORDER BY s.started_at DESC
    ''');

    return rows.map((r) {
      final endedAtRaw = r['ended_at'] as int?;
      return RecordingSession(
        id: r['id'] as int,
        startedAt: DateTime.fromMillisecondsSinceEpoch(r['started_at'] as int),
        endedAt: endedAtRaw == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(endedAtRaw),
        label: r['label'] as String,
        source: r['source'] as String,
        sampleCount: r['sample_count'] as int,
        stepCount: (r['step_count'] as num).toInt(),
      );
    }).toList();
  }

  /// Todas las muestras de una sesión, en orden temporal, como filas
  /// crudas -- es justo lo que necesita ExportService para volcarlas a
  /// CSV sin tener que decodificar primero a RecordingSample y perder
  /// tiempo/memoria con una sesión larga.
  Future<List<Map<String, Object?>>> getRecordingSamplesRaw(
    int sessionId,
  ) async {
    final db = await _database();
    return db.query(
      'recording_samples',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 't_ms ASC',
    );
  }

  Future<void> deleteRecordingSession(int sessionId) async {
    final db = await _database();
    await db.delete(
      'recording_samples',
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
    await db.delete(
      'recording_sessions',
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  /// Suma `by` pasos al total del dia de hoy (upsert).
  Future<void> incrementToday(int by) async {
    final db = await _database();
    final key = _dateKey(DateTime.now());
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.rawInsert('''
      INSERT INTO daily_steps (date, step_count, updated_at)
      VALUES (?, ?, ?)
      ON CONFLICT(date) DO UPDATE SET
        step_count = step_count + excluded.step_count,
        updated_at = excluded.updated_at
    ''', [key, by, now]);
  }

  Future<int> getTodaySteps() async {
    final db = await _database();
    final key = _dateKey(DateTime.now());

    final rows = await db.query(
      'daily_steps',
      columns: ['step_count'],
      where: 'date = ?',
      whereArgs: [key],
    );

    if (rows.isEmpty) return 0;
    return rows.first['step_count'] as int;
  }

  /// Historial entre `from` y `to` (ambos inclusive), ordenado por fecha.
  /// Devuelve una entrada por dia del rango, con 0 pasos en los dias sin
  /// datos (para que un grafico de barras no tenga huecos).
  Future<List<DailyStepEntry>> getRange(DateTime from, DateTime to) async {
    final db = await _database();
    final fromKey = _dateKey(from);
    final toKey = _dateKey(to);

    final rows = await db.query(
      'daily_steps',
      columns: ['date', 'step_count'],
      where: 'date >= ? AND date <= ?',
      whereArgs: [fromKey, toKey],
    );

    final byDate = <String, int>{
      for (final r in rows) r['date'] as String: r['step_count'] as int,
    };

    final result = <DailyStepEntry>[];
    var cursor = DateTime(from.year, from.month, from.day);
    final last = DateTime(to.year, to.month, to.day);

    while (!cursor.isAfter(last)) {
      result.add(DailyStepEntry(
        date: cursor,
        steps: byDate[_dateKey(cursor)] ?? 0,
      ));
      cursor = cursor.add(const Duration(days: 1));
    }

    return result;
  }

  /// Guarda una instantanea de FSR/termistores asociada al paso que se
  /// acaba de detectar -- es lo que permite la trazabilidad del historial.
  Future<void> recordStepEvent({
    required List<double> fsr,
    required List<double> temperature,
  }) async {
    final db = await _database();
    final now = DateTime.now();

    await db.insert('step_events', {
      'date': _dateKey(now),
      'timestamp': now.millisecondsSinceEpoch,
      'fsr': jsonEncode(fsr),
      'temperature': jsonEncode(temperature),
    });
  }

  List<double> _decodeDoubleList(Object? raw) {
    final list = jsonDecode(raw as String) as List;
    return list.map((e) => (e as num).toDouble()).toList();
  }

  /// Eventos de paso entre `from` y `to` (ambos inclusive), ordenados en
  /// el tiempo. En uso real puede haber miles en un dia muy activo -- el
  /// llamador debe pintarlos en una lista perezosa (ListView.builder), no
  /// cargarlos todos de golpe en pantalla.
  Future<List<StepEvent>> getStepEvents(DateTime from, DateTime to) async {
    final db = await _database();
    final fromKey = _dateKey(from);
    final toKey = _dateKey(to);

    final rows = await db.query(
      'step_events',
      where: 'date >= ? AND date <= ?',
      whereArgs: [fromKey, toKey],
      orderBy: 'timestamp ASC',
    );

    return rows
        .map((r) => StepEvent(
              timestamp: DateTime.fromMillisecondsSinceEpoch(r['timestamp'] as int),
              fsr: _decodeDoubleList(r['fsr']),
              temperature: _decodeDoubleList(r['temperature']),
            ))
        .toList();
  }

  Future<List<StepEvent>> getStepEventsForDay(DateTime day) =>
      getStepEvents(day, day);

  /// Borra todo el historial (pasos diarios + trazabilidad). Pensado para
  /// el boton "Borrar historial" de la pantalla de Debug -- no se llama
  /// nunca desde el flujo normal de la app.
  Future<void> clearAllHistory() async {
    final db = await _database();
    await db.delete('daily_steps');
    await db.delete('step_events');
  }

  // ─────────────────────────────────────────────────────────
  // DATOS DE PRUEBA (solo para poder ver/probar la pantalla de Historial
  // sin esperar semanas de uso real o depender del ESP32-S3).
  // ─────────────────────────────────────────────────────────

  static List<double> _demoFsr(Random rng) =>
      [for (int i = 0; i < 12; i++) 0.02 + rng.nextDouble() * 0.9];

  static List<double> _demoTemperature(Random rng) => [
        28 + rng.nextDouble() * 7,
        28 + rng.nextDouble() * 7,
        30 + rng.nextDouble() * 6,
        30 + rng.nextDouble() * 6,
      ];

  /// Rellena `days` dias hacia atras (sin tocar el dia de hoy, para no
  /// pisar pasos reales ya acumulados) con un total diario plausible y una
  /// muestra representativa de eventos de paso -- NO una fila por cada
  /// paso simulado, porque para un dia de ~7000 pasos serian decenas de
  /// miles de filas solo para poder probar la pantalla. Con 6-40 eventos
  /// por dia ya hay de sobra para navegar la trazabilidad de ejemplo.
  Future<void> seedDemoHistory({int days = 100}) async {
    final db = await _database();
    final rng = Random();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final batch = db.batch();

    for (int d = days; d >= 1; d--) {
      final day = today.subtract(Duration(days: d));
      final key = _dateKey(day);
      final isWeekend =
          day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;
      // Dia de descanso ocasional (~1 de cada 12), para que el calendario
      // no se vea artificialmente uniforme -- un historial real siempre
      // tiene dias flojos.
      final isRestDay = rng.nextInt(12) == 0;

      final steps = isRestDay
          ? rng.nextInt(800)
          : (isWeekend ? 3000 : 5000) + rng.nextInt(isWeekend ? 6000 : 7000);

      batch.insert(
        'daily_steps',
        {
          'date': key,
          'step_count': steps,
          'updated_at': day.millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      final sampleCount = steps == 0 ? 0 : 6 + rng.nextInt(35);
      for (int i = 0; i < sampleCount; i++) {
        final secondsIntoDay = 6 * 3600 + rng.nextInt(16 * 3600); // 06:00-22:00
        final ts = day.add(Duration(seconds: secondsIntoDay));
        batch.insert('step_events', {
          'date': key,
          'timestamp': ts.millisecondsSinceEpoch,
          'fsr': jsonEncode(_demoFsr(rng)),
          'temperature': jsonEncode(_demoTemperature(rng)),
        });
      }
    }

    await batch.commit(noResult: true);
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
