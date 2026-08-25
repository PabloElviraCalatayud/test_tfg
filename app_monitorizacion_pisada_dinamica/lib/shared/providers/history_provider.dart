// lib/shared/providers/history_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/history_service.dart';
import '../models/daily_step_entry.dart';

final historyServiceProvider = Provider<HistoryService>((ref) {
  final svc = HistoryService();
  ref.onDispose(() => svc.close());
  return svc;
});

/// Refresca el historial semanal. `refreshHistoryProvider` se puede
/// invalidar (ref.invalidate) para forzar una relectura, ej. al volver
/// a la pantalla de historial.
final weeklyStepsProvider = FutureProvider<List<DailyStepEntry>>((ref) {
  final service = ref.watch(historyServiceProvider);
  final now = DateTime.now();
  return service.getRange(now.subtract(const Duration(days: 6)), now);
});

/// Historial del mes en curso, desde el dia 1 hasta hoy (los dias futuros
/// del mes no tienen entrada -- se pintan vacios en el calendario).
final monthlyStepsProvider = FutureProvider<List<DailyStepEntry>>((ref) {
  final service = ref.watch(historyServiceProvider);
  final now = DateTime.now();
  final firstOfMonth = DateTime(now.year, now.month, 1);
  return service.getRange(firstOfMonth, now);
});

enum HistoryRange { week, month }

/// Selector Semana/Mes de la pantalla de historial.
final historyRangeProvider = StateProvider<HistoryRange>((ref) => HistoryRange.week);
