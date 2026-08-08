// lib/features/history/presentation/widgets/step_bar_chart.dart
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/models/daily_step_entry.dart';

const List<String> _dayLabels = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

class StepBarChart extends StatelessWidget {
  final List<DailyStepEntry> entries;
  final int goal;

  const StepBarChart({super.key, required this.entries, required this.goal});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      child: CustomPaint(
        size: Size.infinite,
        painter: _BarChartPainter(entries: entries, goal: goal),
      ),
    );
  }
}

class _BarChartPainter extends CustomPainter {
  final List<DailyStepEntry> entries;
  final int goal;

  const _BarChartPainter({required this.entries, required this.goal});

  @override
  void paint(Canvas canvas, Size size) {
    if (entries.isEmpty) return;

    final maxSteps = entries.map((e) => e.steps).fold<int>(goal, (a, b) => a > b ? a : b);
    final chartH = size.height - 24; // deja espacio para las etiquetas de dia
    final barAreaW = size.width / entries.length;
    final barW = barAreaW * 0.5;

    // Linea de objetivo
    if (goal > 0 && maxSteps > 0) {
      final goalY = chartH - (goal / maxSteps) * chartH;
      canvas.drawLine(
        Offset(0, goalY),
        Offset(size.width, goalY),
        Paint()
          ..color = AppColors.warning.withOpacity(0.5)
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke,
      );
    }

    for (int i = 0; i < entries.length; i++) {
      final e = entries[i];
      final cx = barAreaW * i + barAreaW / 2;
      final h = maxSteps > 0 ? (e.steps / maxSteps) * chartH : 0.0;
      final isComplete = goal > 0 && e.steps >= goal;
      final isToday = _isSameDay(e.date, DateTime.now());

      final color = isComplete ? AppColors.success : AppColors.accent;

      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(cx - barW / 2, chartH - h, barW, h == 0 ? 2 : h),
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
      );
      canvas.drawRRect(
        rect,
        Paint()..color = color.withOpacity(isToday ? 0.95 : 0.55),
      );

      // Etiqueta del dia (L, M, X...)
      final tp = TextPainter(
        text: TextSpan(
          text: _dayLabels[e.date.weekday - 1],
          style: TextStyle(
            color: isToday ? AppColors.textPrimary : AppColors.textDisabled,
            fontSize: 10,
            fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(cx - tp.width / 2, size.height - tp.height));
    }
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  bool shouldRepaint(_BarChartPainter old) =>
      old.entries != entries || old.goal != goal;
}
