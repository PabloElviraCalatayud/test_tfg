// lib/features/ota/presentation/screens/ota_screen.dart

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/services/ble_service.dart';
import '../../../../shared/providers/device_provider.dart';

// ─── Estado ────────────────────────────────────────────────────────────────

enum OtaState { idle, flashing, success, error }

class OtaScreenState {
  final OtaState  state;
  final String?   fileName;
  final int?      fileSize;
  final double    progress;
  final String?   errorMessage;

  const OtaScreenState({
    this.state        = OtaState.idle,
    this.fileName,
    this.fileSize,
    this.progress     = 0.0,
    this.errorMessage,
  });

  OtaScreenState copyWith({
    OtaState? state,
    String?   fileName,
    int?      fileSize,
    double?   progress,
    String?   errorMessage,
  }) => OtaScreenState(
    state:        state        ?? this.state,
    fileName:     fileName     ?? this.fileName,
    fileSize:     fileSize     ?? this.fileSize,
    progress:     progress     ?? this.progress,
    errorMessage: errorMessage,
  );
}

// ─── Notifier ──────────────────────────────────────────────────────────────

class OtaNotifier extends StateNotifier<OtaScreenState> {
  final BleService _ble;

  OtaNotifier(this._ble) : super(const OtaScreenState());

  Future<void> pickLocalFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['bin'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final file = result.files.first;

      if (file.bytes == null) {
        throw Exception('No se pudo leer el fichero');
      }

      state = state.copyWith(
        fileName: file.name,
        fileSize: file.size,
      );

      await _flash(Uint8List.fromList(file.bytes!));

    } catch (e) {
      state = state.copyWith(
        state: OtaState.error,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> _flash(Uint8List binary) async {
    state = state.copyWith(state: OtaState.flashing, progress: 0);

    try {
      await _ble.flashFirmware(
        binary,
        onProgress: (p) {
          state = state.copyWith(progress: p);
        },
        onError: (e) {
          state = state.copyWith(
            state: OtaState.error,
            errorMessage: e,
          );
        },
      );

      if (state.state != OtaState.error) {
        state = state.copyWith(
          state: OtaState.success,
          progress: 1.0,
        );
      }

    } catch (e) {
      state = state.copyWith(
        state: OtaState.error,
        errorMessage: e.toString(),
      );
    }
  }

  void reset() => state = const OtaScreenState();
}

final otaProvider =
StateNotifierProvider.autoDispose<OtaNotifier, OtaScreenState>((ref) {
  return OtaNotifier(ref.read(bleServiceProvider));
});

// ─── UI ─────────────────────────────────────────────────────────────────────

class OtaScreen extends ConsumerWidget {
  const OtaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ota      = ref.watch(otaProvider);
    final device   = ref.watch(deviceProvider);
    final notifier = ref.read(otaProvider.notifier);
    final isConnected = device.status == DeviceStatus.connected;

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        title: const Text('Actualización OTA'),
        backgroundColor: AppColors.bgPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              _DeviceStatusCard(device: device),
              const SizedBox(height: 20),

              if (ota.fileName != null) ...[
                _FileInfoCard(ota: ota),
                const SizedBox(height: 16),
              ],

              _StatusSection(ota: ota, onRetry: notifier.reset),
              const SizedBox(height: 24),

              if (ota.state == OtaState.idle || ota.state == OtaState.error) ...[
                _SectionLabel('SELECCIONAR FIRMWARE'),
                const SizedBox(height: 10),

                _OtaButton(
                  icon:     Icons.upload_file,
                  title:    'Subir firmware (.bin)',
                  subtitle: 'Selecciona el archivo desde tu dispositivo',
                  color:    AppColors.accent,
                  enabled:  isConnected,
                  onTap:    () => notifier.pickLocalFile(),
                ),

                if (!isConnected) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppColors.warning.withOpacity(0.3)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.warning_amber_outlined,
                            color: AppColors.warning, size: 16),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Conecta un dispositivo antes de actualizar el firmware.',
                            style: TextStyle(
                                color: AppColors.warning, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Widgets auxiliares ─────────────────────────────────────────────────────

class _DeviceStatusCard extends StatelessWidget {
  final DeviceInfo device;
  const _DeviceStatusCard({required this.device});

  @override
  Widget build(BuildContext context) {
    final isConnected = device.status == DeviceStatus.connected;
    final color = isConnected ? AppColors.bleConnected : AppColors.bleDisconnected;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(isConnected ? Icons.sensors : Icons.sensors_off_outlined,
              color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isConnected ? (device.name ?? 'Dispositivo') : 'Sin dispositivo',
              style: TextStyle(
                  color: color, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _FileInfoCard extends StatelessWidget {
  final OtaScreenState ota;
  const _FileInfoCard({required this.ota});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.bgCard,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.divider),
    ),
    child: Row(
      children: [
        const Icon(Icons.memory, color: AppColors.accent),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            ota.fileName!,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textPrimary),
          ),
        ),
      ],
    ),
  );
}

class _StatusSection extends StatelessWidget {
  final OtaScreenState ota;
  final VoidCallback onRetry;

  const _StatusSection({required this.ota, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    if (ota.state == OtaState.flashing) {
      return Column(
        children: [
          LinearProgressIndicator(value: ota.progress),
          const SizedBox(height: 10),
          Text('${(ota.progress * 100).toStringAsFixed(0)}%'),
        ],
      );
    }

    if (ota.state == OtaState.success) {
      return const Text('Firmware actualizado correctamente');
    }

    if (ota.state == OtaState.error) {
      return Column(
        children: [
          Text('Error: ${ota.errorMessage}'),
          ElevatedButton(onPressed: onRetry, child: const Text('Reintentar')),
        ],
      );
    }

    return const SizedBox.shrink();
  }
}

class _OtaButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  const _OtaButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: enabled ? onTap : null,
    child: Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title),
              Text(subtitle),
            ],
          ),
        ],
      ),
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(fontSize: 10));
}