// lib/features/recording/presentation/widgets/live_pressure_chart.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/models/gait_phase.dart';
import '../../../../shared/providers/sensor_provider.dart';

/// Tira de presión máxima en vivo, con el fondo coloreado según la fase
/// de marcha detectada en cada instante -- la misma idea que la franja
/// superior del diagrama de ciclo de marcha de la memoria, pero con datos
/// reales (o simulados) en lugar de una ilustración estática.
class LivePressureChart extends ConsumerStatefulWidget {
  const LivePressureChart({super.key});

  @override
  ConsumerState<LivePressureChart> createState() => _LivePressureChartState();
}

class _LivePressureChartState extends ConsumerState<LivePressureChart> {
  // ~120 muestras cubren unos 14 s en modo simulado (120 ms/muestra) --
  // suficiente para ver 10-12 zancadas seguidas sin que la tira se vuelva
  // ilegible.
  static const int _maxSamples = 120;

  final List<double> _values = [];
  final List<GaitPhase> _phases = [];

  void _push(double value, GaitPhase phase) {
    _values.add(value);
    _phases.add(phase);
    if (_values.length > _maxSamples) {
      _values.removeAt(0);
      _phases.removeAt(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sensorDataProvider, (prev, next) {
      if (next.fsr.isEmpty) return;
      final peak = next.fsr.reduce((a, b) => a > b ? a : b);
      setState(() => _push(peak, next.gaitPhase));
    });

    return SizedBox(
      height: 140,
      child: CustomPaint(
        size: Size.infinite,
        painter: _StripChartPainter(
          values: List.of(_values),
          phases: List.of(_phases),
        ),
      ),
    );
  }
}

class _StripChartPainter extends CustomPainter {
  final List<double> values;
  final List<GaitPhase> phases;

  const _StripChartPainter({required this.values, required this.phases});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) {
      final tp = TextPainter(
        text: const TextSpan(
          text: 'Esperando datos…',
          style: TextStyle(color: AppColors.textDisabled, fontSize: 12),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(
        (size.width - tp.width) / 2,
        (size.height - tp.height) / 2,
      ));
      return;
    }

    final denom = values.length > 1 ? values.length - 1 : 1;
    final stepX = size.width / denom;

    // Franjas de fondo por fase de marcha.
    for (int i = 0; i < phases.length; i++) {
      final x0 = (stepX * i - stepX / 2).clamp(0.0, size.width);
      canvas.drawRect(
        Rect.fromLTWH(x0, 0, stepX, size.height),
        Paint()..color = phases[i].color.withOpacity(0.10),
      );
    }

    // Líneas guía horizontales.
    final gridPaint = Paint()
      ..color = AppColors.divider
      ..strokeWidth = 1;
    for (final frac in [0.25, 0.5, 0.75]) {
      final y = size.height * (1 - frac);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final path = Path();
    for (int i = 0; i < values.length; i++) {
      final x = stepX * i;
      final y = size.height * (1 - values[i].clamp(0.0, 1.0));
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeJoin = StrokeJoin.round,
    );

    final lastY = size.height * (1 - values.last.clamp(0.0, 1.0));
    canvas.drawCircle(
      Offset(stepX * (values.length - 1), lastY),
      4,
      Paint()..color = AppColors.accent,
    );
  }

  @override
  bool shouldRepaint(_StripChartPainter oldDelegate) =>
      oldDelegate.values != values;
}
