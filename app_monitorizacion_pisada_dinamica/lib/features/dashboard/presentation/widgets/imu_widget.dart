// lib/features/dashboard/presentation/widgets/imu_widget.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/providers/sensor_provider.dart';

class ImuWidget extends ConsumerWidget {
  const ImuWidget({super.key});

  String _pronationLabel(double roll) {
    if (roll.abs() < 2.0) return 'NEUTRO';
    return roll > 0 ? 'PRONACIÓN' : 'SUPINACIÓN';
  }

  Color _pronationColor(double roll) {
    if (roll.abs() < 2.0) return AppColors.success;
    if (roll.abs() < 6.0) return AppColors.warning;
    return AppColors.danger;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(sensorDataProvider);

    return Container(
      // Fixed width — prevents any horizontal layout instability
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header ────────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'ORIENTACIÓN / IMU',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                ),
              ),
              _PronationBadge(roll: data.roll),
            ],
          ),
          const SizedBox(height: 16),

          // ── Artificial horizon ────────────────────────────────────────
          // Fixed aspect ratio → height is deterministic regardless of data
          AspectRatio(
            aspectRatio: 1.6,
            child: CustomPaint(
              painter: _HorizonPainter(
                roll: data.roll,
                pitch: data.pitch,
                yaw: data.yaw,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Lectura simple: nada de grados en crudo por delante, solo
          // una barra que se inclina como un nivel de burbuja (mismo
          // signo que usa el horizonte de arriba) más una palabra. El
          // roll ya lo cubre el badge de pronación de la cabecera, así
          // que aquí solo van pitch (balanceo frontal) y yaw (giro) —
          // los datos en crudo (ACC/GYRO/MAG de los 9 ejes) se han
          // movido a la pantalla de Debug, donde sí tienen sentido.
          _TiltIndicatorRow(
            label: 'BALANCEO FRONTAL',
            angleDeg: data.pitch,
            magnitudeLabel: _tiltMagnitudeLabel(data.pitch, word: 'Inclinación'),
            color: _tiltColor(data.pitch),
          ),
          const SizedBox(height: 10),
          _TiltIndicatorRow(
            label: 'GIRO',
            angleDeg: data.yaw,
            magnitudeLabel: _tiltMagnitudeLabel(data.yaw, word: 'Giro'),
            color: _tiltColor(data.yaw),
          ),
        ],
      ),
    );
  }

  static String _tiltMagnitudeLabel(double deg, {required String word}) {
    final a = deg.abs();
    if (a < 3) return 'Nivelado';
    if (a < 8) return '$word ligero';
    if (a < 15) return '$word moderado';
    return '$word pronunciado';
  }

  static Color _tiltColor(double deg) {
    final a = deg.abs();
    if (a < 3) return AppColors.success;
    if (a < 8) return AppColors.warning;
    return AppColors.danger;
  }
}

// ─── Pronation Badge ──────────────────────────────────────────────────────────

class _PronationBadge extends StatelessWidget {
  final double roll;
  const _PronationBadge({required this.roll});

  String get _label {
    if (roll.abs() < 2.0) return 'NEUTRO';
    return roll > 0 ? 'PRONACIÓN' : 'SUPINACIÓN';
  }

  Color get _color {
    if (roll.abs() < 2.0) return AppColors.success;
    if (roll.abs() < 6.0) return AppColors.warning;
    return AppColors.danger;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _color.withOpacity(0.4)),
      ),
      child: Text(
        _label,
        style: TextStyle(
          color: _color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// ─── Tilt Indicator Row ─────────────────────────────────────────────────────

/// Fila de lectura simple para pitch/yaw: una barra que se inclina como un
/// nivel de burbuja (mismo ángulo/signo que usa `_HorizonPainter` arriba,
/// así que gira exactamente igual que el horizonte) más una palabra de
/// magnitud. El grado exacto se muestra pequeño y secundario -- el dato
/// crudo sigue disponible, pero no es lo primero que se lee.
class _TiltIndicatorRow extends StatelessWidget {
  final String label;
  final double angleDeg;
  final String magnitudeLabel;
  final Color color;

  const _TiltIndicatorRow({
    required this.label,
    required this.angleDeg,
    required this.magnitudeLabel,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final clamped = angleDeg.clamp(-45.0, 45.0);

    return Row(
      children: [
        SizedBox(
          width: 44,
          height: 28,
          child: Center(
            child: Transform.rotate(
              angle: clamped * pi / 180,
              child: Container(
                width: 34,
                height: 4,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textDisabled,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.0,
                ),
              ),
              Text(
                magnitudeLabel,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Text(
          '${angleDeg.toStringAsFixed(0)}°',
          style: const TextStyle(color: AppColors.textDisabled, fontSize: 11),
        ),
      ],
    );
  }
}

// ─── Horizon Painter ──────────────────────────────────────────────────────────

class _HorizonPainter extends CustomPainter {
  final double roll;
  final double pitch;
  final double yaw;

  const _HorizonPainter({
    required this.roll,
    required this.pitch,
    required this.yaw,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r  = size.height / 2 - 4;

    // ── Clip to circle ───────────────────────────────────────────────────
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r)));

    // ── Sky / ground with roll and pitch ─────────────────────────────────
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(roll * pi / 180);

    final pitchOffset = pitch * (r / 45);

    // El circulo visible (radio r) es invariante ante la rotacion de roll,
    // asi que su extension local sigue siendo [-r, r] en ambos ejes pase
    // lo que pase con roll. El unico riesgo real es pitchOffset: con pitch
    // cerca de ±90° puede desplazar hasta ±2r el horizonte, y un alto fijo
    // de r*2 en cada rectangulo no llega a cubrir el circulo entero en el
    // lado que se "encoge" (aparecen huecos en blanco). Con un alcance
    // generoso (independiente de pitchOffset) en ambas franjas se cubre
    // el circulo completo para cualquier pitch realista.
    final farExtent = r * 8;

    canvas.drawRect(
      Rect.fromLTWH(-farExtent, -farExtent, farExtent * 2, farExtent + pitchOffset),
      Paint()..color = const Color(0xFF0A1E3D),
    );
    canvas.drawRect(
      Rect.fromLTWH(-farExtent, pitchOffset, farExtent * 2, farExtent),
      Paint()..color = const Color(0xFF2D1B00),
    );

    // Horizon line
    canvas.drawLine(
      Offset(-r, pitchOffset), Offset(r, pitchOffset),
      Paint()..color = Colors.white.withOpacity(0.8)..strokeWidth = 1.5,
    );

    // Pitch ladder
    for (final deg in [-10, -5, 5, 10]) {
      final yOff = pitchOffset - deg * (r / 45);
      final lw   = deg.abs() == 10 ? r * 0.5 : r * 0.3;
      canvas.drawLine(
        Offset(-lw, yOff), Offset(lw, yOff),
        Paint()..color = Colors.white.withOpacity(0.35)..strokeWidth = 0.8,
      );
    }

    canvas.restore(); // undo rotate

    // ── Fixed aircraft reference ─────────────────────────────────────────
    final refPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx - 40, cy), Offset(cx - 16, cy), refPaint);
    canvas.drawLine(Offset(cx - 16, cy), Offset(cx - 16, cy + 8), refPaint);
    canvas.drawLine(Offset(cx + 40, cy), Offset(cx + 16, cy), refPaint);
    canvas.drawLine(Offset(cx + 16, cy), Offset(cx + 16, cy + 8), refPaint);
    canvas.drawCircle(Offset(cx, cy), 3, Paint()..color = Colors.white);

    canvas.restore(); // undo clip

    // ── Outer ring ───────────────────────────────────────────────────────
    canvas.drawCircle(
      Offset(cx, cy), r,
      Paint()
        ..color = AppColors.divider
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // ── Roll arc indicator ────────────────────────────────────────────────
    final rollNorm  = (roll / 45).clamp(-1.0, 1.0);
    final rollSweep = rollNorm * (pi / 3);
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r + 10),
      -pi / 2, rollSweep, false,
      Paint()
        ..color = AppColors.accent.withOpacity(0.7)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    // Zero tick
    canvas.drawLine(
      Offset(cx, cy - r - 6), Offset(cx, cy - r + 6),
      Paint()..color = AppColors.textDisabled..strokeWidth = 1.5,
    );

    // ── Yaw arrow ─────────────────────────────────────────────────────────
    _drawYawArrow(canvas, cx, size.height - 14, yaw);
  }

  void _drawYawArrow(Canvas canvas, double cx, double y, double yawDeg) {
    if (yawDeg.abs() < 0.5) return;

    final paint = Paint()
      ..color = Colors.purpleAccent.withOpacity(0.65)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final sweep = (yawDeg / 90 * pi / 2).clamp(-pi / 2, pi / 2);
    canvas.drawArc(
      Rect.fromCenter(center: Offset(cx, y), width: 80, height: 16),
      pi, sweep, false, paint,
    );

    final endAngle = pi + sweep;
    final ex = cx + 40 * cos(endAngle);
    final ey = y  +  8 * sin(endAngle);
    final d  = yawDeg > 0 ? 1 : -1;

    canvas.drawLine(Offset(ex, ey), Offset(ex + d * 6, ey - 5), paint);
    canvas.drawLine(Offset(ex, ey), Offset(ex + d * 6, ey + 5), paint);

    final tp = TextPainter(
      text: TextSpan(
        text: 'YAW ${yawDeg > 0 ? '▶' : '◀'} ${yawDeg.abs().toStringAsFixed(1)}°',
        style: const TextStyle(color: Colors.purpleAccent, fontSize: 8, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, y - 22));
  }

  @override
  bool shouldRepaint(_HorizonPainter old) =>
      old.roll != roll || old.pitch != pitch || old.yaw != yaw;
}