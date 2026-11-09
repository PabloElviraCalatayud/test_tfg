// lib/features/recording/presentation/screens/recording_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/models/gait_phase.dart';
import '../../../../shared/models/recording_session.dart';
import '../../../../shared/providers/sensor_provider.dart';
import '../../../../shared/providers/recording_provider.dart';
import '../../../../shared/providers/history_provider.dart';
import '../widgets/gait_phase_badge.dart';
import '../widgets/live_pressure_chart.dart';

/// Pantalla de grabación de sesiones: permite capturar una serie temporal
/// completa (presión, temperatura, IMU, fase de marcha) y exportarla a
/// CSV para generar gráficas -- de presión, temperatura o del propio
/// ciclo de marcha -- fuera de la app (p.ej. para incluir en la memoria).
///
/// Funciona tanto con el dispositivo real conectado por BLE como en modo
/// de datos simulados: útil para poder generar una sesión de ejemplo sin
/// depender de tener el ESP32-S3 a mano.
class RecordingScreen extends ConsumerWidget {
  const RecordingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isRecording = ref.watch(isRecordingProvider);
    final sensorData = ref.watch(sensorDataProvider);
    final useFake = ref.watch(useFakeDataProvider);
    final sessionsAsync = ref.watch(recordingSessionsProvider);

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'GRABACIÓN DE SESIONES',
              style: TextStyle(
                color: AppColors.textDisabled,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Captura presión, temperatura, IMU y fase de marcha a lo largo '
              'del tiempo, y expórtalo como CSV para generar tus propias '
              'gráficas.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
            ),
            const SizedBox(height: 16),

            _RecorderCard(
              isRecording: isRecording,
              useFake: useFake,
              currentPhase: sensorData.gaitPhase,
            ),

            const SizedBox(height: 24),
            const Text(
              'SESIONES GUARDADAS',
              style: TextStyle(
                color: AppColors.textDisabled,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 10),

            sessionsAsync.when(
              data: (sessions) {
                if (sessions.isEmpty) {
                  return const _EmptySessions();
                }
                return Column(
                  children: [
                    for (final s in sessions) ...[
                      _SessionTile(session: s),
                      const SizedBox(height: 8),
                    ],
                  ],
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.accent),
                ),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'No se pudo cargar el listado de sesiones: $e',
                  style: const TextStyle(color: AppColors.danger, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Tarjeta de grabación activa ───────────────────────────────────────────

class _RecorderCard extends ConsumerWidget {
  final bool isRecording;
  final bool useFake;
  final GaitPhase currentPhase;

  const _RecorderCard({
    required this.isRecording,
    required this.useFake,
    required this.currentPhase,
  });

  String _formatElapsed(DateTime? startedAt) {
    if (startedAt == null) return '00:00';
    final d = DateTime.now().difference(startedAt);
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final startedAt = ref.watch(recordingStartedAtProvider);
    final stepCount = ref.watch(recordingStepCountProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: isRecording
            ? Border.all(color: AppColors.danger.withOpacity(0.5))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GaitPhaseBadge(phase: currentPhase, large: true),
              const Spacer(),
              if (isRecording)
                Row(
                  children: [
                    const Icon(Icons.fiber_manual_record,
                        color: AppColors.danger, size: 12),
                    const SizedBox(width: 6),
                    Text(
                      _formatElapsed(startedAt),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Icon(
                      useFake ? Icons.science_outlined : Icons.sensors,
                      color: AppColors.textSecondary,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      useFake ? 'Modo simulado' : 'Dispositivo real',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 14),
          const LivePressureChart(),
          const SizedBox(height: 14),
          if (isRecording)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                '$stepCount pasos detectados en esta grabación',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    isRecording ? AppColors.danger : AppColors.accent,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: Icon(
                isRecording ? Icons.stop_rounded : Icons.fiber_manual_record,
                color: Colors.black,
              ),
              label: Text(
                isRecording ? 'Detener grabación' : 'Iniciar grabación',
                style: const TextStyle(
                    color: Colors.black, fontWeight: FontWeight.bold),
              ),
              onPressed: () async {
                final notifier = ref.read(sensorDataProvider.notifier);
                if (isRecording) {
                  await notifier.stopRecording();
                } else {
                  await notifier.startRecording();
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Lista vacía ────────────────────────────────────────────────────────────

class _EmptySessions extends StatelessWidget {
  const _EmptySessions();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Column(
        children: [
          Icon(Icons.timeline, color: AppColors.textDisabled, size: 28),
          SizedBox(height: 10),
          Text(
            'Todavía no hay sesiones grabadas',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 4),
          Text(
            'Pulsa "Iniciar grabación" arriba, incluso en modo simulado, '
            'para generar tu primera sesión de ejemplo.',
            style: TextStyle(color: AppColors.textDisabled, fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─── Fila de sesión guardada ────────────────────────────────────────────────

class _SessionTile extends ConsumerStatefulWidget {
  final RecordingSession session;
  const _SessionTile({required this.session});

  @override
  ConsumerState<_SessionTile> createState() => _SessionTileState();
}

class _SessionTileState extends ConsumerState<_SessionTile> {
  bool _exporting = false;

  String _formatDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60);
    return m > 0 ? '${m}m ${s}s' : '${s}s';
  }

  Future<void> _export() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(exportServiceProvider).exportAndShare(widget.session);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('No se pudo exportar la sesión: $e')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: const Text('Borrar sesión',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Se borrará "${widget.session.label}" y todas sus muestras. '
          'Esta acción no se puede deshacer.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Borrar', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(historyServiceProvider).deleteRecordingSession(widget.session.id);
    ref.invalidate(recordingSessionsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: (s.isFake ? AppColors.warning : AppColors.success)
                  .withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              s.isFake ? Icons.science_outlined : Icons.sensors,
              color: s.isFake ? AppColors.warning : AppColors.success,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_formatDate(s.startedAt)} · ${_formatDuration(s.duration)} · '
                  '${s.sampleCount} muestras · ${s.stepCount} pasos',
                  style: const TextStyle(
                      color: AppColors.textDisabled, fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Exportar CSV',
            icon: _exporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.accent),
                  )
                : const Icon(Icons.ios_share, color: AppColors.accent, size: 20),
            onPressed: _export,
          ),
          IconButton(
            tooltip: 'Borrar',
            icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 20),
            onPressed: _delete,
          ),
        ],
      ),
    );
  }
}
