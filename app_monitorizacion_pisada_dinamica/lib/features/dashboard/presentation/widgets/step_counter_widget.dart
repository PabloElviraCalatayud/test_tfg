// lib/features/dashboard/presentation/widgets/step_counter_widget.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/providers/sensor_provider.dart';

class StepCounterWidget extends ConsumerWidget {
  const StepCounterWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data     = ref.watch(sensorDataProvider);
    final goal     = ref.watch(stepGoalProvider);
    final steps    = data.stepCount;
    final progress = goal > 0 ? (steps / goal).clamp(0.0, 1.0) : 0.0;
    final isComplete = steps >= goal && goal > 0;

    return GestureDetector(
      onTap: () => _showGoalDialog(context, ref, goal),
      child: Container(
        width: double.infinity,          // ← ancho explícito siempre
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min, // ← no crecer más de lo necesario
          children: [
            // ── Header ──────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'PASOS',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5,
                  ),
                ),
                Row(
                  children: [
                    const Icon(Icons.flag_outlined, size: 12, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Text(
                      _fmt(goal),
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.edit_outlined, size: 11, color: AppColors.textDisabled),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Dial ────────────────────────────────────────────────────
            SizedBox(
              height: 160,
              width: 160,
              child: CustomPaint(
                painter: _RadialStepPainter(progress: progress, isComplete: isComplete),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _fmt(steps),
                        style: TextStyle(
                          color: isComplete ? AppColors.success : AppColors.textPrimary,
                          fontSize: 32,
                          fontWeight: FontWeight.w300,
                          letterSpacing: -1,
                        ),
                      ),
                      Text(
                        '${(progress * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          color: isComplete ? AppColors.success : AppColors.accent,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── "Objetivo alcanzado" — SIEMPRE ocupa espacio para evitar
            //   que la Column cambie de altura entre estados. Visibility
            //   mantiene el espacio reservado cuando está oculta.
            const SizedBox(height: 12),
            Visibility(
              visible: isComplete,
              maintainSize: true,       // ← clave: reserva espacio aunque no sea visible
              maintainAnimation: true,
              maintainState: true,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, color: AppColors.success, size: 14),
                  SizedBox(width: 6),
                  Text(
                    'OBJETIVO ALCANZADO',
                    style: TextStyle(
                      color: AppColors.success,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';

  void _showGoalDialog(BuildContext context, WidgetRef ref, int currentGoal) {
    final ctrl = TextEditingController(text: currentGoal.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: const Text('Objetivo de pasos',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Ej: 10000',
            hintStyle: const TextStyle(color: AppColors.textDisabled),
            enabledBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: AppColors.divider),
                borderRadius: BorderRadius.circular(8)),
            focusedBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: AppColors.accent),
                borderRadius: BorderRadius.circular(8)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              final val = int.tryParse(ctrl.text);
              if (val != null && val > 0 && val <= 100000) {
                ref.read(stepGoalProvider.notifier).state = val;
              }
              Navigator.pop(ctx);
            },
            child: const Text('Guardar',
                style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
  }
}

// ─── Painter ──────────────────────────────────────────────────────────────────

class _RadialStepPainter extends CustomPainter {
  final double progress;
  final bool isComplete;

  const _RadialStepPainter({required this.progress, required this.isComplete});

  @override
  void paint(Canvas canvas, Size size) {
    final center    = Offset(size.width / 2, size.height / 2);
    final radius    = (size.width / 2) - 12;
    const sw        = 10.0;
    const startAngle = -pi / 2;

    // ── Background track (siempre presente) ─────────────────────────────
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle, 2 * pi, false,
      Paint()
        ..color = AppColors.bgCardAlt
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw
        ..strokeCap = StrokeCap.round,
    );

    // ── Inner ring ───────────────────────────────────────────────────────
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 16),
      0, 2 * pi, false,
      Paint()
        ..color = AppColors.divider
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // ── Progress arc — SÓLO se dibuja si hay progreso real ───────────────
    //   Evita crear un SweepGradient degenerado (startAngle == endAngle)
    //   que en Skia produce valores NaN y corrompe el estado del canvas.
    if (progress <= 0.0) return;

    final sweepAngle = 2 * pi * progress;
    final arcRect    = Rect.fromCircle(center: center, radius: radius);
    final arcPaint   = Paint()
      ..style     = PaintingStyle.stroke
      ..strokeWidth = sw
      ..strokeCap = StrokeCap.round;

    if (isComplete) {
      arcPaint.color = AppColors.success;
    } else {
      // Gradiente válido sólo cuando startAngle < endAngle
      arcPaint.shader = SweepGradient(
        startAngle: startAngle,
        endAngle:   startAngle + sweepAngle,
        colors: const [AppColors.accentDim, AppColors.accent],
        tileMode: TileMode.clamp,
      ).createShader(arcRect);
    }

    canvas.drawArc(arcRect, startAngle, sweepAngle, false, arcPaint);
  }

  @override
  bool shouldRepaint(_RadialStepPainter old) =>
      old.progress != progress || old.isComplete != isComplete;
}