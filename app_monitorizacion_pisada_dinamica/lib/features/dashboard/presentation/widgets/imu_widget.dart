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

          // ── Axis rows — all use fixed-width value containers ──────────
          _AxisRow(label: 'ROLL',  value: data.roll,  color: AppColors.accent),
          const SizedBox(height: 6),
          _AxisRow(label: 'PITCH', value: data.pitch, color: AppColors.warning),
          const SizedBox(height: 6),
          _AxisRow(label: 'YAW',   value: data.yaw,   color: Colors.purpleAccent),

          const Divider(height: 24, color: AppColors.divider),

          // ── 9-DOF raw — fixed-height grid ─────────────────────────────
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              '9-DOF RAW',
              style: TextStyle(
                color: AppColors.textDisabled,
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
          ),
          // IntrinsicHeight ensures all three groups are the same height
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _SensorGroup(title: 'ACC (m/s²)',
                    labels: const ['X', 'Y', 'Z'],
                    values: [data.accX, data.accY, data.accZ])),
                const VerticalDivider(color: AppColors.divider, width: 1),
                Expanded(child: _SensorGroup(title: 'GYRO (°/s)',
                    labels: const ['X', 'Y', 'Z'],
                    values: [data.gyroX, data.gyroY, data.gyroZ])),
                const VerticalDivider(color: AppColors.divider, width: 1),
                Expanded(child: _SensorGroup(title: 'MAG (µT)',
                    labels: const ['X', 'Y', 'Z'],
                    values: [data.magX, data.magY, data.magZ])),
              ],
            ),
          ),
        ],
      ),
    );
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

// ─── Axis Row ─────────────────────────────────────────────────────────────────

class _AxisRow extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const _AxisRow({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    // Clamp display range to -30..+30 degrees
    final barVal = ((value + 30) / 60).clamp(0.0, 1.0);

    return SizedBox(
      height: 20, // fixed height — never grows/shrinks with content
      child: Row(
        children: [
          // Fixed-width label
          SizedBox(
            width: 44,
            child: Text(
              label,
              style: TextStyle(
                color: color.withOpacity(0.85),
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
          ),
          // Progress bar fills remaining space
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: barVal,
                backgroundColor: AppColors.bgCardAlt,
                valueColor: AlwaysStoppedAnimation(color.withOpacity(0.6)),
                minHeight: 4,
              ),
            ),
          ),
          // Fixed-width value — tabular figures, sign always shown
          SizedBox(
            width: 58,
            child: Text(
              '${value >= 0 ? '+' : ''}${value.toStringAsFixed(1)}°',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Sensor Group ─────────────────────────────────────────────────────────────

class _SensorGroup extends StatelessWidget {
  final String title;
  final List<String> labels;
  final List<double> values;

  const _SensorGroup({
    required this.title,
    required this.labels,
    required this.values,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textDisabled,
              fontSize: 8,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          for (int i = 0; i < labels.length; i++)
          // Each value row has a fixed height of 18px
            SizedBox(
              height: 18,
              child: Row(
                children: [
                  Text(
                    '${labels[i]}: ',
                    style: const TextStyle(
                      color: AppColors.textDisabled,
                      fontSize: 10,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      values[i].toStringAsFixed(2),
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        fontFeatures: [FontFeature.tabularFigures()],
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

    canvas.drawRect(
      Rect.fromLTWH(-r * 2, -r * 2, r * 4, r * 2 + pitchOffset),
      Paint()..color = const Color(0xFF0A1E3D),
    );
    canvas.drawRect(
      Rect.fromLTWH(-r * 2, pitchOffset, r * 4, r * 2),
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