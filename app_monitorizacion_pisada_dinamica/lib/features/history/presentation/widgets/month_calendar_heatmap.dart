// lib/features/history/presentation/widgets/month_calendar_heatmap.dart
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/models/daily_step_entry.dart';

const List<String> _weekdayLabels = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

/// Calendario mensual tipo "mapa de calor" (estilo Garmin Connect /
/// contribuciones de GitHub): una celda por día del mes, coloreada según
/// el % del objetivo diario alcanzado ese día. Los días futuros del mes
/// (o los huecos antes del día 1) se muestran vacíos.
class MonthCalendarHeatmap extends StatelessWidget {
  final List<DailyStepEntry> entries; // desde el día 1 del mes hasta hoy
  final int goal;
  final void Function(DateTime day)? onDayTap;

  const MonthCalendarHeatmap({
    super.key,
    required this.entries,
    required this.goal,
    this.onDayTap,
  });

  Color _cellColor(int steps) {
    if (goal <= 0 || steps <= 0) return AppColors.bgCardAlt;
    final frac = steps / goal;
    if (frac < 0.5) return AppColors.accentDim.withOpacity(0.55);
    if (frac < 1.0) return AppColors.accent.withOpacity(0.85);
    return AppColors.success;
  }

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const SizedBox(
        height: 120,
        child: Center(
          child: Text('Sin datos este mes',
              style: TextStyle(color: AppColors.textDisabled, fontSize: 12)),
        ),
      );
    }

    final first = entries.first.date; // siempre el día 1 del mes
    final now = DateTime.now();
    final daysInMonth = DateTime(first.year, first.month + 1, 0).day;
    final leadingBlanks = first.weekday - 1; // Lunes=1 → 0 huecos

    final stepsByDay = <int, int>{
      for (final e in entries) e.date.day: e.steps,
    };

    final cells = <Widget>[
      for (int i = 0; i < leadingBlanks; i++) const SizedBox.shrink(),
      for (int day = 1; day <= daysInMonth; day++)
        _DayCell(
          day: day,
          hasData: stepsByDay.containsKey(day),
          color: stepsByDay.containsKey(day)
              ? _cellColor(stepsByDay[day]!)
              : null,
          isToday: now.year == first.year &&
              now.month == first.month &&
              now.day == day,
          onTap: onDayTap == null
              ? null
              : () => onDayTap!(DateTime(first.year, first.month, day)),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (final l in _weekdayLabels)
              Expanded(
                child: Center(
                  child: Text(
                    l,
                    style: const TextStyle(
                      color: AppColors.textDisabled,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          children: cells,
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  final int day;
  final bool hasData;
  final Color? color;
  final bool isToday;
  final VoidCallback? onTap;

  const _DayCell({
    required this.day,
    required this.hasData,
    required this.color,
    required this.isToday,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: hasData ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: isToday
              ? Border.all(color: AppColors.accent, width: 1.5)
              : (hasData
                  ? null
                  : Border.all(color: AppColors.divider, width: 1)),
        ),
        alignment: Alignment.center,
        child: Text(
          '$day',
          style: TextStyle(
            color: hasData ? Colors.white.withOpacity(0.9) : AppColors.textDisabled,
            fontSize: 10,
            fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
