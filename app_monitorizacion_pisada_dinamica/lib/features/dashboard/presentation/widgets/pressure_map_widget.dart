// lib/features/dashboard/presentation/widgets/pressure_map_widget.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/svg_path_utils.dart';
import '../../../../shared/providers/sensor_provider.dart';

/// Posiciones normalizadas (x, y) de los 15 FSR en espacio sensor.
/// x: 0=medial, 1=lateral  |  y: 0=talón, 1=dedos
const List<(double, double)> _fsrPositions = [
  (0.38, 0.93), (0.48, 0.96), (0.58, 0.95), (0.66, 0.91), // dedos T1-T4
  (0.30, 0.74), (0.40, 0.77), (0.52, 0.76), (0.62, 0.73), // metatarsos M1-M4
  (0.67, 0.68),                                             // M5 lateral
  (0.35, 0.54), (0.47, 0.52), (0.57, 0.53),                // arco MF1-MF3
  (0.35, 0.21), (0.47, 0.18), (0.60, 0.21),                // talón H1-H3
];

Color _pressureColor(double value) {
  const colors = AppColors.pressureGradient;
  final t      = value.clamp(0.0, 1.0);
  final scaled = t * (colors.length - 1);
  final idx    = scaled.floor().clamp(0, colors.length - 2);
  return Color.lerp(colors[idx], colors[idx + 1], scaled - idx)!;
}

class PressureMapWidget extends ConsumerWidget {
  const PressureMapWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(sensorDataProvider);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'PRESIÓN PLANTAR',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          _PressureLegend(),
          const SizedBox(height: 8),
          AspectRatio(
            aspectRatio: 0.52,
            child: CustomPaint(
              painter: _FootPressurePainter(
                fsrValues: data.fsr,
                copX: data.centerOfPressure.$1,
                copY: data.centerOfPressure.$2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Gradient legend ─────────────────────────────────────────────────────────

class _PressureLegend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text('Baja',
            style: TextStyle(color: AppColors.textDisabled, fontSize: 9)),
        const SizedBox(width: 4),
        Expanded(
          child: Container(
            height: 6,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: AppColors.pressureGradient),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
        const SizedBox(width: 4),
        const Text('Alta',
            style: TextStyle(color: AppColors.textDisabled, fontSize: 9)),
      ],
    );
  }
}

// ─── Painter ─────────────────────────────────────────────────────────────────

class _FootPressurePainter extends CustomPainter {
  final List<double> fsrValues;
  final double copX, copY;

  const _FootPressurePainter({
    required this.fsrValues,
    required this.copX,
    required this.copY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final foot = SvgPathUtils.buildFootPath(size);

    // ── Fondo del pie ────────────────────────────────────────────────────
    canvas.drawPath(foot, Paint()..color = const Color(0xFF1A1A22));

    // ── Sensores FSR (clipeados al pie) ──────────────────────────────────
    canvas.save();
    canvas.clipPath(foot);

    for (int i = 0; i < _fsrPositions.length && i < fsrValues.length; i++) {
      final (nx, ny) = _fsrPositions[i];
      final px  = nx * size.width;
      final py  = (1 - ny) * size.height; // flip: y=0 es talón=abajo
      final val = fsrValues[i];

      if (val < 0.02) continue; // sin presión apreciable

      final color  = _pressureColor(val);
      final radius = 14.0 + val * 14.0;

      // Halo exterior
      canvas.drawCircle(
        Offset(px, py),
        radius * 1.8,
        Paint()
          ..color      = color.withOpacity(0.15)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
      );

      // Blob principal
      canvas.drawCircle(
        Offset(px, py),
        radius,
        Paint()
          ..color      = color.withOpacity(0.75)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );

      // Punto central
      canvas.drawCircle(Offset(px, py), 4, Paint()..color = color);
    }

    canvas.restore();

    // ── Contorno del pie ─────────────────────────────────────────────────
    canvas.drawPath(
      foot,
      Paint()
        ..color      = const Color(0xFF8B7355).withOpacity(0.6)
        ..style      = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // ── Centro de presión + flecha de dirección ──────────────────────────
    _drawArrow(canvas, size);
  }

  void _drawArrow(Canvas canvas, Size size) {
    final px = copX * size.width;
    final py = (1 - copY) * size.height;

    // Punto COP
    canvas.drawCircle(
      Offset(px, py),
      6,
      Paint()..color = Colors.white.withOpacity(0.9),
    );
    canvas.drawCircle(
      Offset(px, py),
      6,
      Paint()
        ..color       = AppColors.accent.withOpacity(0.45)
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Dirección de la marcha: hacia los dedos (arriba en canvas = -π/2).
    // Desviación lateral proporcional a la posición medial/lateral del COP:
    //   COP medial (x<0.43)  → ligera inclinación hacia fuera
    //   COP lateral (x>0.55) → ligera inclinación hacia dentro
    // Rango: ±0.35 rad (~20°) — cubre pronación/supinación moderada.
    final lateralBias   = (copX - 0.46) * 0.7;
    final arrowAngle    = -pi / 2 + lateralBias;
    const arrowLen      = 46.0;
    const headLen       = 12.0;
    const headHalfAngle = 0.42; // radianes

    final arrowEnd = Offset(
      px + cos(arrowAngle) * arrowLen,
      py + sin(arrowAngle) * arrowLen,
    );

    // Línea del eje
    canvas.drawLine(
      Offset(px, py),
      arrowEnd,
      Paint()
        ..color       = Colors.white.withOpacity(0.85)
        ..strokeWidth = 2.5
        ..strokeCap   = StrokeCap.round,
    );

    // Triángulo relleno en la punta
    final head1 = Offset(
      arrowEnd.dx + cos(arrowAngle + pi - headHalfAngle) * headLen,
      arrowEnd.dy + sin(arrowAngle + pi - headHalfAngle) * headLen,
    );
    final head2 = Offset(
      arrowEnd.dx + cos(arrowAngle + pi + headHalfAngle) * headLen,
      arrowEnd.dy + sin(arrowAngle + pi + headHalfAngle) * headLen,
    );

    canvas.drawPath(
      Path()
        ..moveTo(arrowEnd.dx, arrowEnd.dy)
        ..lineTo(head1.dx, head1.dy)
        ..lineTo(head2.dx, head2.dy)
        ..close(),
      Paint()..color = Colors.white.withOpacity(0.85),
    );
  }

  @override
  bool shouldRepaint(_FootPressurePainter old) =>
      old.fsrValues != fsrValues ||
          old.copX != copX ||
          old.copY != copY;
}