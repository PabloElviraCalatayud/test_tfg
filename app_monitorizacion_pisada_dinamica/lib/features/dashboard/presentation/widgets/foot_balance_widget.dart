// lib/features/dashboard/presentation/widgets/foot_balance_widget.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/providers/sensor_provider.dart';

// Agrupación de los 12 índices FSR (mismo orden que _fsrPositions en
// pressure_map_widget.dart / centerOfPressure en sensor_data.dart) en las
// dos zonas que un usuario sin formación técnica puede interpretar de un
// vistazo: borde interno/externo del pie, y talón/planta.
const List<int> _medialIdx   = [0, 3, 4, 7, 9];       // borde interno
const List<int> _lateralIdx  = [1, 2, 5, 6, 8, 10, 11]; // borde externo
const List<int> _heelIdx     = [9, 10, 11];             // talón
const List<int> _forefootIdx = [0, 1, 2, 3, 4, 5, 6, 7, 8]; // planta y dedos

/// Widget pensado para el objetivo de accesibilidad del proyecto: un
/// usuario sin conocimientos técnicos no necesita ver 12 sensores en
/// gramos, necesita saber "¿piso más de un lado o del otro?". Este
/// widget traduce el reparto relativo de presión (ver
/// SensorData.relativePercent) a dos barras simples más una frase.
class FootBalanceWidget extends ConsumerWidget {
  const FootBalanceWidget({super.key});

  double _sumIdx(List<double> pct, List<int> idx) {
    double s = 0;
    for (final i in idx) {
      if (i < pct.length) s += pct[i];
    }
    return s;
  }

  String _describeBalance({
    required double medialPct,
    required double lateralPct,
    required double heelPct,
    required double forefootPct,
  }) {
    final total = medialPct + lateralPct;
    if (total < 5) return 'Sin presión detectada en este momento.';

    final parts = <String>[];

    final medialShare = medialPct / total;
    if (medialShare >= 0.62) {
      parts.add('cargas más el borde interno del pie');
    } else if (medialShare <= 0.38) {
      parts.add('cargas más el borde externo del pie');
    }

    final hfTotal = heelPct + forefootPct;
    final heelShare = hfTotal > 0 ? heelPct / hfTotal : 0.5;
    if (heelShare >= 0.62) {
      parts.add('apoyas más en el talón');
    } else if (heelShare <= 0.38) {
      parts.add('apoyas más en la parte delantera del pie');
    }

    if (parts.isEmpty) {
      return 'Reparto equilibrado entre ambos lados del pie y entre el talón y la planta.';
    }
    return 'Ahora mismo ${parts.join(' y ')}.';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(sensorDataProvider);
    final pct = data.relativePercent;

    final medial = _sumIdx(pct, _medialIdx);
    final lateral = _sumIdx(pct, _lateralIdx);
    final heel = _sumIdx(pct, _heelIdx);
    final forefoot = _sumIdx(pct, _forefootIdx);

    final message = _describeBalance(
      medialPct: medial,
      lateralPct: lateral,
      heelPct: heel,
      forefootPct: forefoot,
    );

    return Container(
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
          const Text(
            'RESUMEN DE TU PISADA',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 18),
          _BalanceBar(
            leftLabel: 'Borde interno',
            leftPct: medial,
            leftColor: AppColors.accent,
            rightLabel: 'Borde externo',
            rightPct: lateral,
            rightColor: AppColors.warning,
          ),
          const SizedBox(height: 14),
          _BalanceBar(
            leftLabel: 'Talón',
            leftPct: heel,
            leftColor: AppColors.success,
            rightLabel: 'Planta y dedos',
            rightPct: forefoot,
            rightColor: AppColors.accentDim,
          ),
        ],
      ),
    );
  }
}

class _BalanceBar extends StatelessWidget {
  final String leftLabel, rightLabel;
  final double leftPct, rightPct;
  final Color leftColor, rightColor;

  const _BalanceBar({
    required this.leftLabel,
    required this.leftPct,
    required this.rightLabel,
    required this.rightPct,
    required this.leftColor,
    required this.rightColor,
  });

  @override
  Widget build(BuildContext context) {
    final total = leftPct + rightPct;
    final hasData = total > 0.5;
    // Expanded exige flex >= 1: con hasData=false pintamos una pista vacía.
    final leftFlex = max(1, leftPct.round());
    final rightFlex = max(1, rightPct.round());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(leftLabel,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 11)),
            const Spacer(),
            Text(rightLabel,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 11)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: SizedBox(
            height: 10,
            child: hasData
                ? Row(
                    children: [
                      Expanded(
                          flex: leftFlex,
                          child: Container(color: leftColor)),
                      Expanded(
                          flex: rightFlex,
                          child: Container(color: rightColor)),
                    ],
                  )
                : Container(color: AppColors.bgCardAlt),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text('${hasData ? leftPct.round() : 0}%',
                style: TextStyle(
                    color: leftColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('${hasData ? rightPct.round() : 0}%',
                style: TextStyle(
                    color: rightColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ],
    );
  }
}
