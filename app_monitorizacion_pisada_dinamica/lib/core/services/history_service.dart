// lib/core/services/history_service.dart
//
// Persistencia local del historial de pasos (sqflite). Es el unico sitio
// que sabe leer/escribir la tabla daily_steps -- todo lo demas pasa por
// esta clase.

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../../shared/models/daily_step_entry.dart';

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
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE daily_steps (
            date       TEXT PRIMARY KEY,
            step_count INTEGER NOT NULL DEFAULT 0,
            updated_at INTEGER NOT NULL
          )
        ''');
      },
    );

    return _db!;
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

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
