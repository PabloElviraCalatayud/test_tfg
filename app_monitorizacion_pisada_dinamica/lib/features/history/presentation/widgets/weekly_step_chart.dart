// lib/features/history/presentation/widgets/weekly_step_chart.dart
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

/// Un bloque de N días consecutivos con su total de pasos sumado. Se usa
/// para los rangos largos (30 días, 3 meses, personalizado largo), donde
/// una barra por día sería ilegible.
class WeeklyBucket {
  final DateTime start;
  final int totalSteps;
  final int days;

  const WeeklyBucket({
    required this.start,
    required this.totalSteps,
    required this.days,
  });
}

/// Gráfico de barras para rangos largos: cada barra es el total de una
/// ventana de ~7 días, sin línea de objetivo (comparar un total de varios
/// días contra el objetivo de un solo día sería engañoso) -- el color sí
/// distingue si esa ventana alcanzó "objetivo × días que la componen".
class WeeklyStepChart extends StatelessWidget {
  final List<WeeklyBucket> buckets;
  final int goal;

  const WeeklyStepChart({super.key, required this.buckets, required this.goal});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      child: CustomPaint(
        size: Size.infinite,
        painter: _WeeklyChartPainter(buckets: buckets, goal: goal),
      ),
    );
  }
}

class _WeeklyChartPainter extends CustomPainter {
  final List<WeeklyBucket> buckets;
  final int goal;

  const _WeeklyChartPainter({required this.buckets, required this.goal});

  @override
  void paint(Canvas canvas, Size size) {
    if (buckets.isEmpty) return;

    final maxTotal =
        buckets.map((b) => b.totalSteps).fold<int>(1, (a, b) => a > b ? a : b);
    final chartH = size.height - 24;
    final barAreaW = size.width / buckets.length;
    final barW = barAreaW * 0.55;

    for (int i = 0; i < buckets.length; i++) {
      final b = buckets[i];
      final cx = barAreaW * i + barAreaW / 2;
      final h = maxTotal > 0 ? (b.totalSteps / maxTotal) * chartH : 0.0;
      final isComplete = goal > 0 && b.totalSteps >= goal * b.days;
      final isCurrent = i == buckets.length - 1;

      final color = isComplete ? AppColors.success : AppColors.accent;

      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(cx - barW / 2, chartH - h, barW, h == 0 ? 2 : h),
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
      );
      canvas.drawRRect(
        rect,
        Paint()..color = color.withOpacity(isCurrent ? 0.95 : 0.55),
      );

      final label = '${b.start.day}/${b.start.month}';
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: isCurrent ? AppColors.textPrimary : AppColors.textDisabled,
            fontSize: 9,
            fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: barAreaW + 4);
      tp.paint(canvas, Offset(cx - tp.width / 2, size.height - tp.height));
    }
  }

  @override
  bool shouldRepaint(_WeeklyChartPainter old) =>
      old.buckets != buckets || old.goal != goal;
}
