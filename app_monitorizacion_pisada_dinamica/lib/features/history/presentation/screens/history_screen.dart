// lib/features/history/presentation/screens/history_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/models/daily_step_entry.dart';
import '../../../../shared/providers/history_provider.dart';
import '../../../../shared/providers/sensor_provider.dart';
import '../widgets/step_bar_chart.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekly = ref.watch(weeklyStepsProvider);
    final goal = ref.watch(stepGoalProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 14, top: 4),
            child: Text(
              'HISTORIAL DE PASOS',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'ÚLTIMOS 7 DÍAS',
                  style: TextStyle(
                    color: AppColors.textDisabled,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 16),
                weekly.when(
                  data: (entries) => StepBarChart(entries: entries, goal: goal),
                  loading: () => const SizedBox(
                    height: 180,
                    child: Center(child: CircularProgressIndicator(color: AppColors.accent)),
                  ),
                  error: (e, _) => SizedBox(
                    height: 180,
                    child: Center(
                      child: Text(
                        'No se pudo cargar el historial',
                        style: const TextStyle(color: AppColors.danger, fontSize: 12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          weekly.when(
            data: (entries) => _SummaryRow(entries: entries, goal: goal),
            loading: () => const SizedBox.shrink(),
            error: (e, _) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final List<DailyStepEntry> entries;
  final int goal;
  const _SummaryRow({required this.entries, required this.goal});

  @override
  Widget build(BuildContext context) {
    final steps = entries.map((e) => e.steps).toList();
    final total = steps.isEmpty ? 0 : steps.reduce((a, b) => a + b);
    final avg = steps.isEmpty ? 0 : (total / steps.length).round();
    final daysComplete = steps.where((s) => goal > 0 && s >= goal).length;

    return Row(
      children: [
        Expanded(child: _StatCard(label: 'TOTAL', value: '$total')),
        const SizedBox(width: 12),
        Expanded(child: _StatCard(label: 'MEDIA/DÍA', value: '$avg')),
        const SizedBox(width: 12),
        Expanded(child: _StatCard(label: 'DÍAS OBJETIVO', value: '$daysComplete/7')),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textDisabled,
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}
