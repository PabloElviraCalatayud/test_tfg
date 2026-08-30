import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/providers/device_provider.dart';
import '../../../../shared/providers/sensor_provider.dart';
import '../../../../shared/providers/history_provider.dart';
import '../../../../core/services/mqtt_service.dart';

class DebugScreen extends ConsumerWidget {
  const DebugScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(sensorDataProvider);
    final useFake = ref.watch(useFakeDataProvider);

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Toggle
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.bgCard,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.science_outlined, color: AppColors.warning, size: 18),
                  const SizedBox(width: 10),
                  const Text(
                    'Datos simulados',
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                  ),
                  const Spacer(),
                  Switch(
                    value: useFake,
                    activeThumbColor: AppColors.accent,
                    onChanged: (v) =>
                    ref.read(useFakeDataProvider.notifier).state = v,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            _DebugGroup(title: 'FSR (Presión plantar, normalizado + % relativo)', children: [
              for (int i = 0; i < data.fsr.length; i++)
                _DebugRow(
                    label: 'FSR${i + 1}',
                    value: '${data.fsr[i].toStringAsFixed(3)}  ·  '
                        '${data.relativePercent[i].toStringAsFixed(1)}%'),
            ]),

            const SizedBox(height: 12),

            _DebugGroup(title: 'Termistores (°C)', children: [
              for (int i = 0; i < data.temperature.length; i++)
                _DebugRow(
                    label: 'TEMP${i + 1}',
                    value:
                    '${data.temperature[i].toStringAsFixed(1)} °C'),
            ]),

            const SizedBox(height: 12),

            _DebugGroup(title: 'Acelerómetro (m/s²)', children: [
              _DebugRow(
                  label: 'ACC X',
                  value: data.accX.toStringAsFixed(3)),
              _DebugRow(
                  label: 'ACC Y',
                  value: data.accY.toStringAsFixed(3)),
              _DebugRow(
                  label: 'ACC Z',
                  value: data.accZ.toStringAsFixed(3)),
            ]),

            const SizedBox(height: 12),

            _DebugGroup(title: 'Giróscopo (°/s)', children: [
              _DebugRow(
                  label: 'GYR X',
                  value: data.gyroX.toStringAsFixed(3)),
              _DebugRow(
                  label: 'GYR Y',
                  value: data.gyroY.toStringAsFixed(3)),
              _DebugRow(
                  label: 'GYR Z',
                  value: data.gyroZ.toStringAsFixed(3)),
            ]),

            const SizedBox(height: 12),

            _DebugGroup(title: 'Magnetómetro (µT)', children: [
              _DebugRow(
                  label: 'MAG X',
                  value: data.magX.toStringAsFixed(2)),
              _DebugRow(
                  label: 'MAG Y',
                  value: data.magY.toStringAsFixed(2)),
              _DebugRow(
                  label: 'MAG Z',
                  value: data.magZ.toStringAsFixed(2)),
            ]),

            const SizedBox(height: 12),

            _DebugGroup(title: 'Orientación derivada', children: [
              _DebugRow(
                  label: 'ROLL',
                  value: '${data.roll.toStringAsFixed(2)}°'),
              _DebugRow(
                  label: 'PITCH',
                  value: '${data.pitch.toStringAsFixed(2)}°'),
              _DebugRow(
                  label: 'YAW',
                  value: '${data.yaw.toStringAsFixed(2)}°'),
            ]),

            const SizedBox(height: 24),

            // BOTÓN TEST MQTT
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () async {
                  final mqtt = ref.read(mqttServiceProvider);
                  await mqtt.testPublish();
                },
                child: const Text(
                  'Test MQTT',
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            const Text(
              'HISTORIAL (PRUEBAS)',
              style: TextStyle(
                color: AppColors.textDisabled,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Rellena el historial con datos de ejemplo (o bórralo) para '
              'poder probar la pantalla de Historial sin esperar semanas '
              'de uso real.',
              style: TextStyle(color: AppColors.textDisabled, fontSize: 11),
            ),
            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.accent),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  await ref.read(historyServiceProvider).seedDemoHistory();
                  invalidateHistory(ref);
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Historial de prueba generado')),
                  );
                },
                child: const Text(
                  'Generar historial de prueba',
                  style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold),
                ),
              ),
            ),

            const SizedBox(height: 10),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.danger),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      backgroundColor: AppColors.bgCard,
                      title: const Text('Borrar historial',
                          style: TextStyle(color: AppColors.textPrimary)),
                      content: const Text(
                        'Se borrarán todos los pasos guardados y su trazabilidad, '
                        'de prueba o reales. Esta acción no se puede deshacer.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(dialogContext).pop(false),
                          child: const Text('Cancelar'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(dialogContext).pop(true),
                          child: const Text('Borrar',
                              style: TextStyle(color: AppColors.danger)),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true) return;

                  final messenger = ScaffoldMessenger.of(context);
                  await ref.read(historyServiceProvider).clearAllHistory();
                  invalidateHistory(ref);
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Historial borrado')),
                  );
                },
                child: const Text(
                  'Borrar historial',
                  style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold),
                ),
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _DebugGroup extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _DebugGroup({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.textDisabled,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              for (int i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1)
                  const Divider(color: AppColors.divider, height: 1),
              ]
            ],
          ),
        ),
      ],
    );
  }
}

class _DebugRow extends StatelessWidget {
  final String label;
  final String value;
  const _DebugRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.accent,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}