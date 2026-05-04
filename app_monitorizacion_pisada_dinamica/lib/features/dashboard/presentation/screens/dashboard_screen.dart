// lib/features/dashboard/presentation/screens/dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../widgets/step_counter_widget.dart';
import '../widgets/pressure_map_widget.dart';
import '../widgets/heat_map_widget.dart';
import '../widgets/imu_widget.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ⚠️  NO Scaffold aquí — ya estamos dentro del Scaffold de AppScaffold.
    //     Anidar Scaffolds causa que SafeArea recalcule insets en cada rebuild
    //     y desplace el layout completo.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      // CrossAxisAlignment.stretch fuerza ancho total en TODOS los hijos,
      // evitando que un widget más estrecho haga colapsar la columna.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 14, top: 4),
            child: Text(
              _formattedDate(),
              style: const TextStyle(
                color: AppColors.textDisabled,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
              ),
            ),
          ),

          // ── Cada widget ocupa el ancho completo ──────────────────────────
          const StepCounterWidget(),
          const SizedBox(height: 12),
          const PressureMapWidget(),
          const SizedBox(height: 12),
          const HeatMapWidget(),
          const SizedBox(height: 12),
          const ImuWidget(),
        ],
      ),
    );
  }

  String _formattedDate() {
    final now = DateTime.now();
    const months = ['ENE','FEB','MAR','ABR','MAY','JUN',
      'JUL','AGO','SEP','OCT','NOV','DIC'];
    const days   = ['LUN','MAR','MIÉ','JUE','VIE','SÁB','DOM'];
    return '${days[now.weekday - 1]} · ${now.day} ${months[now.month - 1]} ${now.year}';
  }
}