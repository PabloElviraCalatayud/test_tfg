// lib/shared/providers/history_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/history_service.dart';
import '../models/daily_step_entry.dart';
import '../models/step_event.dart';

final historyServiceProvider = Provider<HistoryService>((ref) {
  final svc = HistoryService();
  ref.onDispose(() => svc.close());
  return svc;
});

// ─────────────────────────────────────────────────────────
// HOY (para la tarjeta destacada) — SIEMPRE desde la base de datos, nunca
// desde sensorDataProvider.stepCount: ese contador en vivo se infla en
// modo "datos simulados" (sube un paso cada segundo, ver
// SensorDataNotifier._fakeTick) y _fakeTick nunca escribe en el
// historial. Si la tarjeta de hoy leyera el contador en vivo, mostraría
// un número creciente y falso mientras el resto de la pantalla (gráfico,
// resumen) sigue mostrando el dato real persistido -- la inconsistencia
// que hacía que el historial "no mostrara los datos correctamente".
// ─────────────────────────────────────────────────────────
final todayStepsProvider = FutureProvider<int>((ref) {
  final service = ref.watch(historyServiceProvider);
  return service.getTodaySteps();
});

// ─────────────────────────────────────────────────────────
// FILTRO TEMPORAL (gráfico + resumen)
// ─────────────────────────────────────────────────────────

enum HistoryPreset { last7, last30, last90, custom }

class HistoryFilter {
  final HistoryPreset preset;
  final DateTime? customFrom;
  final DateTime? customTo;

  const HistoryFilter({required this.preset, this.customFrom, this.customTo});

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime get from {
    switch (preset) {
      case HistoryPreset.last7:
        return _today.subtract(const Duration(days: 6));
      case HistoryPreset.last30:
        return _today.subtract(const Duration(days: 29));
      case HistoryPreset.last90:
        return _today.subtract(const Duration(days: 89));
      case HistoryPreset.custom:
        return customFrom ?? _today.subtract(const Duration(days: 6));
    }
  }

  DateTime get to => preset == HistoryPreset.custom ? (customTo ?? _today) : _today;

  HistoryFilter copyWith({
    HistoryPreset? preset,
    DateTime? customFrom,
    DateTime? customTo,
  }) {
    return HistoryFilter(
      preset: preset ?? this.preset,
      customFrom: customFrom ?? this.customFrom,
      customTo: customTo ?? this.customTo,
    );
  }
}

final historyFilterProvider =
    StateProvider<HistoryFilter>((ref) => const HistoryFilter(preset: HistoryPreset.last7));

final filteredStepsProvider = FutureProvider<List<DailyStepEntry>>((ref) {
  final service = ref.watch(historyServiceProvider);
  final filter = ref.watch(historyFilterProvider);
  return service.getRange(filter.from, filter.to);
});

// ─────────────────────────────────────────────────────────
// CALENDARIO (navegación mes a mes, independiente del filtro de arriba)
// ─────────────────────────────────────────────────────────

final calendarMonthProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, 1);
});

final calendarMonthStepsProvider = FutureProvider<List<DailyStepEntry>>((ref) {
  final service = ref.watch(historyServiceProvider);
  final month = ref.watch(calendarMonthProvider);
  final now = DateTime.now();
  final isCurrentMonth = month.year == now.year && month.month == now.month;
  final to = isCurrentMonth
      ? DateTime(now.year, now.month, now.day)
      : DateTime(month.year, month.month + 1, 0); // último día de ese mes
  return service.getRange(month, to);
});

// ─────────────────────────────────────────────────────────
// TRAZABILIDAD (FSR/termistores de cada paso de un día concreto)
// ─────────────────────────────────────────────────────────

final dayStepEventsProvider =
    FutureProvider.family<List<StepEvent>, DateTime>((ref, day) {
  final service = ref.watch(historyServiceProvider);
  return service.getStepEventsForDay(day);
});

/// Refresca todos los providers que dependen de la base de datos del
/// historial. Se llama tras cada paso real detectado (para que la
/// pantalla de Historial se actualice sola si está abierta mientras
/// caminas) y tras generar/borrar datos de prueba desde Debug.
///
/// Recibe el METODO `invalidate` en vez del objeto `ref` completo a
/// proposito: `Ref` (dentro de providers) y `WidgetRef` (dentro de
/// widgets) son tipos distintos en Riverpod, ninguno subtipo del otro,
/// pero los dos exponen `invalidate(ProviderOrFamily)` con la misma
/// firma -- pasando ese metodo (`ref.invalidate`) esta funcion sirve
/// para los dos sin duplicar las llamadas en cada sitio donde se usa.
void invalidateHistory(void Function(ProviderOrFamily provider) invalidate) {
  invalidate(todayStepsProvider);
  invalidate(filteredStepsProvider);
  invalidate(calendarMonthStepsProvider);
  invalidate(dayStepEventsProvider);
}
