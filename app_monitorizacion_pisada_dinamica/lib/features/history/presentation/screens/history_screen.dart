// lib/features/history/presentation/screens/history_screen.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/models/daily_step_entry.dart';
import '../../../../shared/models/step_event.dart';
import '../../../../shared/providers/history_provider.dart';
import '../../../../shared/providers/sensor_provider.dart';
import '../widgets/step_bar_chart.dart';
import '../widgets/weekly_step_chart.dart';
import '../widgets/month_calendar_heatmap.dart';

const List<String> _monthNames = [
  'ENERO', 'FEBRERO', 'MARZO', 'ABRIL', 'MAYO', 'JUNIO',
  'JULIO', 'AGOSTO', 'SEPTIEMBRE', 'OCTUBRE', 'NOVIEMBRE', 'DICIEMBRE',
];

const List<String> _weekdayNamesFull = [
  'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo',
];

const List<String> _monthNamesLower = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];

String _fmtShort(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

String _fmtTime(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String _fmtFullDate(DateTime d) =>
    '${_weekdayNamesFull[d.weekday - 1]}, ${d.day} de ${_monthNamesLower[d.month - 1]}';

String _rangeLabel(HistoryFilter filter) {
  switch (filter.preset) {
    case HistoryPreset.last7:
      return 'ÚLTIMOS 7 DÍAS';
    case HistoryPreset.last30:
      return 'ÚLTIMOS 30 DÍAS';
    case HistoryPreset.last90:
      return 'ÚLTIMOS 3 MESES';
    case HistoryPreset.custom:
      return '${_fmtShort(filter.from)} - ${_fmtShort(filter.to)}';
  }
}

List<WeeklyBucket> _bucketWeekly(List<DailyStepEntry> entries) {
  final buckets = <WeeklyBucket>[];
  for (int i = 0; i < entries.length; i += 7) {
    final end = (i + 7 < entries.length) ? i + 7 : entries.length;
    final chunk = entries.sublist(i, end);
    buckets.add(WeeklyBucket(
      start: chunk.first.date,
      totalSteps: chunk.fold(0, (a, e) => a + e.steps),
      days: chunk.length,
    ));
  }
  return buckets;
}

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(historyFilterProvider);
    final goal = ref.watch(stepGoalProvider);
    final todayAsync = ref.watch(todayStepsProvider);
    final filteredAsync = ref.watch(filteredStepsProvider);
    final month = ref.watch(calendarMonthProvider);
    final calendarAsync = ref.watch(calendarMonthStepsProvider);

    final now = DateTime.now();
    final canGoNext =
        month.year < now.year || (month.year == now.year && month.month < now.month);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 14, top: 4),
            child: Text(
              'HISTORIAL DE PASOS',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
              ),
            ),
          ),

          todayAsync.when(
            data: (steps) => _TodayHeroCard(steps: steps, goal: goal),
            loading: () => _TodayHeroCard(steps: 0, goal: goal),
            error: (_, __) => _TodayHeroCard(steps: 0, goal: goal),
          ),
          const SizedBox(height: 14),

          _FilterChips(
            filter: filter,
            onPresetChanged: (preset) =>
                ref.read(historyFilterProvider.notifier).state = HistoryFilter(preset: preset),
            onCustomTap: () => _pickCustomRange(context, ref),
          ),
          const SizedBox(height: 12),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _rangeLabel(filter),
                  style: const TextStyle(
                    color: AppColors.textDisabled,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 16),
                filteredAsync.when(
                  data: (entries) {
                    if (entries.isEmpty) {
                      return const SizedBox(
                        height: 180,
                        child: Center(
                          child: Text('Sin datos en este rango',
                              style: TextStyle(color: AppColors.textDisabled, fontSize: 12)),
                        ),
                      );
                    }
                    if (entries.length <= 14) {
                      return StepBarChart(entries: entries, goal: goal);
                    }
                    return WeeklyStepChart(buckets: _bucketWeekly(entries), goal: goal);
                  },
                  loading: () => const SizedBox(
                    height: 180,
                    child: Center(
                        child: CircularProgressIndicator(color: AppColors.accent)),
                  ),
                  error: (e, _) => const SizedBox(
                    height: 180,
                    child: Center(
                      child: Text(
                        'No se pudo cargar el historial',
                        style: TextStyle(color: AppColors.danger, fontSize: 12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          filteredAsync.when(
            data: (entries) => _SummaryRow(entries: entries, goal: goal),
            loading: () => const SizedBox.shrink(),
            error: (e, _) => const SizedBox.shrink(),
          ),

          const SizedBox(height: 24),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Text(
                      'CALENDARIO',
                      style: TextStyle(
                        color: AppColors.textDisabled,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.chevron_left,
                          color: AppColors.textSecondary, size: 20),
                      onPressed: () => ref
                          .read(calendarMonthProvider.notifier)
                          .update((m) => DateTime(m.year, m.month - 1, 1)),
                    ),
                    SizedBox(
                      width: 130,
                      child: Text(
                        '${_monthNames[month.month - 1]} ${month.year}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: Icon(
                        Icons.chevron_right,
                        color: canGoNext ? AppColors.textSecondary : AppColors.textDisabled,
                        size: 20,
                      ),
                      onPressed: canGoNext
                          ? () => ref
                              .read(calendarMonthProvider.notifier)
                              .update((m) => DateTime(m.year, m.month + 1, 1))
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Toca un día para ver el detalle de sus pasos',
                  style: TextStyle(color: AppColors.textDisabled, fontSize: 10),
                ),
                const SizedBox(height: 12),
                calendarAsync.when(
                  data: (entries) => MonthCalendarHeatmap(
                    entries: entries,
                    goal: goal,
                    onDayTap: (day) => _showDayTraceability(context, day),
                  ),
                  loading: () => const SizedBox(
                    height: 180,
                    child: Center(
                        child: CircularProgressIndicator(color: AppColors.accent)),
                  ),
                  error: (e, _) => const SizedBox(
                    height: 180,
                    child: Center(
                      child: Text(
                        'No se pudo cargar el calendario',
                        style: TextStyle(color: AppColors.danger, fontSize: 12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickCustomRange(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      initialDateRange: DateTimeRange(
        start: now.subtract(const Duration(days: 6)),
        end: now,
      ),
    );
    if (picked == null) return;

    ref.read(historyFilterProvider.notifier).state = HistoryFilter(
      preset: HistoryPreset.custom,
      customFrom: DateTime(picked.start.year, picked.start.month, picked.start.day),
      customTo: DateTime(picked.end.year, picked.end.month, picked.end.day),
    );
  }

  void _showDayTraceability(BuildContext context, DateTime day) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _DayTraceabilitySheet(day: day),
    );
  }
}

// ─── Tarjeta destacada de hoy ─────────────────────────────────────────────

class _TodayHeroCard extends StatelessWidget {
  final int steps;
  final int goal;
  const _TodayHeroCard({required this.steps, required this.goal});

  @override
  Widget build(BuildContext context) {
    final progress = goal > 0 ? (steps / goal).clamp(0.0, 1.0) : 0.0;
    final isComplete = goal > 0 && steps >= goal;
    final pct = goal > 0 ? (steps / goal * 100).round() : 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.bgCard, AppColors.bgCardAlt],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            height: 76,
            child: CustomPaint(
              painter: _HeroRingPainter(progress: progress, complete: isComplete),
              child: Center(
                child: Icon(
                  Icons.directions_walk,
                  color: isComplete ? AppColors.success : AppColors.accent,
                  size: 26,
                ),
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'PASOS HOY',
                  style: TextStyle(
                    color: AppColors.textDisabled,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$steps',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 32,
                    fontWeight: FontWeight.w300,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  goal > 0 ? '$pct% de tu objetivo diario' : 'Sin objetivo definido',
                  style: TextStyle(
                    color: isComplete ? AppColors.success : AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroRingPainter extends CustomPainter {
  final double progress;
  final bool complete;
  const _HeroRingPainter({required this.progress, required this.complete});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 5;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = AppColors.bgCardAlt
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8,
    );

    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2,
        2 * pi * progress,
        false,
        Paint()
          ..color = complete ? AppColors.success : AppColors.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_HeroRingPainter old) =>
      old.progress != progress || old.complete != complete;
}

// ─── Filtro temporal ────────────────────────────────────────────────────────

class _FilterChips extends StatelessWidget {
  final HistoryFilter filter;
  final ValueChanged<HistoryPreset> onPresetChanged;
  final VoidCallback onCustomTap;

  const _FilterChips({
    required this.filter,
    required this.onPresetChanged,
    required this.onCustomTap,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _FilterChip(
            label: '7D',
            selected: filter.preset == HistoryPreset.last7,
            onTap: () => onPresetChanged(HistoryPreset.last7),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: '30D',
            selected: filter.preset == HistoryPreset.last30,
            onTap: () => onPresetChanged(HistoryPreset.last30),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: '3M',
            selected: filter.preset == HistoryPreset.last90,
            onTap: () => onPresetChanged(HistoryPreset.last90),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: filter.preset == HistoryPreset.custom
                ? '${_fmtShort(filter.from)} - ${_fmtShort(filter.to)}'
                : 'Personalizado',
            selected: filter.preset == HistoryPreset.custom,
            onTap: onCustomTap,
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent.withOpacity(0.15) : AppColors.bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.accent.withOpacity(0.5) : AppColors.divider,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.accent : AppColors.textSecondary,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

// ─── Resumen ────────────────────────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  final List<DailyStepEntry> entries;
  final int goal;
  const _SummaryRow({required this.entries, required this.goal});

  @override
  Widget build(BuildContext context) {
    final steps = entries.map((e) => e.steps).toList();
    final total = steps.isEmpty ? 0 : steps.reduce((a, b) => a + b);
    final avg = steps.isEmpty ? 0 : (total / steps.length).round();
    final daysComplete = steps.where((s) => goal > 0 && s >= goal).length;

    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.trending_up,
            label: 'TOTAL',
            value: '$total',
            color: AppColors.accent,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.bar_chart,
            label: 'MEDIA/DÍA',
            value: '$avg',
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.emoji_events,
            label: 'DÍAS OBJETIVO',
            value: '$daysComplete/${steps.length}',
            color: AppColors.success,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 19,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textDisabled,
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Trazabilidad de un día ─────────────────────────────────────────────────

class _DayTraceabilitySheet extends ConsumerWidget {
  final DateTime day;
  const _DayTraceabilitySheet({required this.day});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(dayStepEventsProvider(day));

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _fmtFullDate(day),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              eventsAsync.when(
                data: (events) => Text(
                  events.isEmpty
                      ? 'Sin pasos con trazabilidad registrados'
                      : '${events.length} pasos con trazabilidad registrados',
                  style: const TextStyle(color: AppColors.textDisabled, fontSize: 11),
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: eventsAsync.when(
                  data: (events) {
                    if (events.isEmpty) {
                      return const Center(
                        child: Text(
                          'Sin pasos registrados este día',
                          style: TextStyle(color: AppColors.textDisabled, fontSize: 13),
                        ),
                      );
                    }
                    return ListView.separated(
                      controller: scrollController,
                      itemCount: events.length,
                      separatorBuilder: (_, __) =>
                          const Divider(color: AppColors.divider, height: 1),
                      itemBuilder: (context, i) => _StepEventTile(event: events[i]),
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator(color: AppColors.accent)),
                  error: (e, _) => const Center(
                    child: Text('No se pudo cargar la trazabilidad',
                        style: TextStyle(color: AppColors.danger)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

List<(int, double)> _topSensors(List<double> pct, int n) {
  final indexed = [for (int i = 0; i < pct.length; i++) (i, pct[i])];
  indexed.sort((a, b) => b.$2.compareTo(a.$2));
  return indexed.take(n).toList();
}

class _StepEventTile extends StatelessWidget {
  final StepEvent event;
  const _StepEventTile({required this.event});

  @override
  Widget build(BuildContext context) {
    final top = _topSensors(event.relativePercent, 3);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(
              _fmtTime(event.timestamp),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              top.map((t) => 'Sensor ${t.$1 + 1}: ${t.$2.toStringAsFixed(0)}%').join('  ·  '),
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${event.avgTemperature.toStringAsFixed(1)}°C',
            style: const TextStyle(color: AppColors.textDisabled, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
