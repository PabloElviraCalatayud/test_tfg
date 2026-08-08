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
