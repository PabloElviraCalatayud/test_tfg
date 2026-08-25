// lib/features/history/presentation/screens/history_screen.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/models/daily_step_entry.dart';
import '../../../../shared/providers/history_provider.dart';
import '../../../../shared/providers/sensor_provider.dart';
import '../widgets/step_bar_chart.dart';
import '../widgets/month_calendar_heatmap.dart';

const List<String> _monthNames = [
  'ENERO', 'FEBRERO', 'MARZO', 'ABRIL', 'MAYO', 'JUNIO',
  'JULIO', 'AGOSTO', 'SEPTIEMBRE', 'OCTUBRE', 'NOVIEMBRE', 'DICIEMBRE',
];

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(historyRangeProvider);
    final goal = ref.watch(stepGoalProvider);
    final todaySteps = ref.watch(sensorDataProvider).stepCount;
    final activeAsync = range == HistoryRange.week
        ? ref.watch(weeklyStepsProvider)
        : ref.watch(monthlyStepsProvider);

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

          _TodayHeroCard(steps: todaySteps, goal: goal),
          const SizedBox(height: 12),

          _RangeToggle(
            range: range,
            onChanged: (r) => ref.read(historyRangeProvider.notifier).state = r,
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
                  range == HistoryRange.week
                      ? 'ÚLTIMOS 7 DÍAS'
                      : '${_monthNames[DateTime.now().month - 1]} ${DateTime.now().year}',
                  style: const TextStyle(
                    color: AppColors.textDisabled,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 16),
                activeAsync.when(
                  data: (entries) => range == HistoryRange.week
                      ? StepBarChart(entries: entries, goal: goal)
                      : MonthCalendarHeatmap(entries: entries, goal: goal),
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

          activeAsync.when(
            data: (entries) => _SummaryRow(entries: entries, goal: goal),
            loading: () => const SizedBox.shrink(),
            error: (e, _) => const SizedBox.shrink(),
          ),
        ],
      ),
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

// ─── Selector Semana / Mes ─────────────────────────────────────────────────

class _RangeToggle extends StatelessWidget {
  final HistoryRange range;
  final ValueChanged<HistoryRange> onChanged;
  const _RangeToggle({required this.range, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _RangeButton(
              label: 'Semana',
              selected: range == HistoryRange.week,
              onTap: () => onChanged(HistoryRange.week),
            ),
          ),
          Expanded(
            child: _RangeButton(
              label: 'Mes',
              selected: range == HistoryRange.month,
              onTap: () => onChanged(HistoryRange.month),
            ),
          ),
        ],
      ),
    );
  }
}

class _RangeButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _RangeButton({
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
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          border: selected
              ? Border.all(color: AppColors.accent.withOpacity(0.4))
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.accent : AppColors.textSecondary,
            fontSize: 13,
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
