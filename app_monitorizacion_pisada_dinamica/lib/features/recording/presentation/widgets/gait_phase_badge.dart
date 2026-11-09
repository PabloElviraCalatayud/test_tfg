// lib/features/recording/presentation/widgets/gait_phase_badge.dart
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/models/gait_phase.dart';

/// Pequeña píldora de color con la fase de marcha actual. Se usa tanto en
/// el dashboard (lectura rápida sin entrar a Sesiones) como en la propia
/// pantalla de grabación.
class GaitPhaseBadge extends StatelessWidget {
  final GaitPhase phase;
  final bool large;

  const GaitPhaseBadge({super.key, required this.phase, this.large = false});

  @override
  Widget build(BuildContext context) {
    final color = phase.color;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 16 : 10,
        vertical: large ? 10 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(large ? 14 : 20),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: large ? 10 : 7,
            height: large ? 10 : 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          SizedBox(width: large ? 10 : 6),
          Text(
            phase.label,
            style: TextStyle(
              color: color,
              fontSize: large ? 15 : 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
