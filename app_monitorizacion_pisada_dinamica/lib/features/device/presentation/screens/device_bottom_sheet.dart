// lib/features/device/presentation/screens/device_bottom_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/providers/device_provider.dart';

// Estado del botón de firmware — local a este sheet
enum _FwState { idle, checking, upToDate }
final _fwStateProvider = StateProvider.autoDispose<_FwState>((_) => _FwState.idle);

class DeviceBottomSheet extends ConsumerWidget {
  const DeviceBottomSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device   = ref.watch(deviceProvider);
    final notifier = ref.read(deviceProvider.notifier);

    return DraggableScrollableSheet(
      initialChildSize: 0.52,
      minChildSize:     0.32,
      maxChildSize:     0.85,
      expand: false,
      builder: (_, sc) => Container(
        decoration: const BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: _sheetBody(context, ref, device, notifier, sc),
      ),
    );
  }

  Widget _sheetBody(
      BuildContext context,
      WidgetRef ref,
      DeviceInfo device,
      DeviceNotifier notifier,
      ScrollController sc,
      ) {
    return SingleChildScrollView(
      controller: sc,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Handle(),
          _TitleRow(device: device),
          const SizedBox(height: 12),
          const Divider(color: AppColors.divider),
          const SizedBox(height: 12),

          // ── Mensaje de error ──────────────────────────────────────────────
          if (device.errorMessage != null)
            _ErrorBanner(message: device.errorMessage!),

          // ── Contenido según estado ────────────────────────────────────────
          if (device.status == DeviceStatus.connected)
            _ConnectedContent(device: device, ref: ref, notifier: notifier)
          else if (device.status == DeviceStatus.connecting)
            const _ConnectingContent()
          else if (device.status == DeviceStatus.scanning)
              _ScanningContent(ref: ref, notifier: notifier)
            else
              _DisconnectedContent(notifier: notifier),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ─── Handle ───────────────────────────────────────────────────────────────────

class _Handle extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 36, height: 4,
      margin: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.textDisabled,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

// ─── Title row ────────────────────────────────────────────────────────────────

class _TitleRow extends StatelessWidget {
  final DeviceInfo device;
  const _TitleRow({required this.device});

  String get _title {
    switch (device.status) {
      case DeviceStatus.connected:    return 'Dispositivo conectado';
      case DeviceStatus.connecting:   return 'Conectando...';
      case DeviceStatus.scanning:     return 'Buscando dispositivos';
      case DeviceStatus.disconnected: return 'Sin dispositivo';
    }
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(Icons.sensors, color: AppColors.accent, size: 20),
      const SizedBox(width: 10),
      Text(_title, style: const TextStyle(
          color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
      const Spacer(),
      _StatusBadge(status: device.status),
    ],
  );
}

// ─── Connected ────────────────────────────────────────────────────────────────

class _ConnectedContent extends ConsumerWidget {
  final DeviceInfo     device;
  final WidgetRef      ref;
  final DeviceNotifier notifier;
  const _ConnectedContent({
    required this.device,
    required this.ref,
    required this.notifier,
  });

  @override
  Widget build(BuildContext context, WidgetRef wRef) {
    final fwState = wRef.watch(_fwStateProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _InfoRow(icon: Icons.device_hub_outlined,  label: 'Nombre',   value: device.name     ?? '—'),
        _InfoRow(icon: Icons.memory_outlined,       label: 'Firmware', value: device.firmware  ?? '—'),
        _InfoRow(icon: Icons.battery_std_outlined,  label: 'Batería',  value: device.battery != null ? '${device.battery}%' : '—'),
        _InfoRow(icon: Icons.tag_outlined,          label: 'ID',       value: device.deviceId != null
            ? '${device.deviceId!.substring(0, 8)}…'
            : '—'),
        const SizedBox(height: 20),

        // Firmware update
        _FwButton(fwState: fwState, onTap: () => _checkFw(wRef)),
        const SizedBox(height: 10),

        // OTA Flash
        _ActionButton(
          icon:  Icons.upload_outlined,
          label: 'Actualizar firmware (OTA)',
          color: AppColors.accent,
          onTap: () {
            Navigator.pop(context);
            Navigator.of(context).pushNamed('/ota');
          },
        ),
        const SizedBox(height: 10),

        // Disconnect
        _ActionButton(
          icon:  Icons.bluetooth_disabled_outlined,
          label: 'Desconectar',
          color: AppColors.danger,
          onTap: () { notifier.disconnect(); Navigator.pop(context); },
        ),
      ],
    );
  }

  Future<void> _checkFw(WidgetRef wRef) async {
    wRef.read(_fwStateProvider.notifier).state = _FwState.checking;
    await Future.delayed(const Duration(seconds: 2));
    if (wRef.context.mounted) {
      wRef.read(_fwStateProvider.notifier).state = _FwState.upToDate;
      Future.delayed(const Duration(seconds: 4), () {
        if (wRef.context.mounted) {
          wRef.read(_fwStateProvider.notifier).state = _FwState.idle;
        }
      });
    }
  }
}

// ─── Scanning ────────────────────────────────────────────────────────────────

class _ScanningContent extends ConsumerWidget {
  final WidgetRef      ref;
  final DeviceNotifier notifier;
  const _ScanningContent({required this.ref, required this.notifier});

  @override
  Widget build(BuildContext context, WidgetRef wRef) {
    final results = wRef.watch(scanResultsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Barra de progreso animada
        const LinearProgressIndicator(
          backgroundColor: AppColors.bgCardAlt,
          color: AppColors.accent,
          minHeight: 2,
        ),
        const SizedBox(height: 16),

        if (results.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Column(children: [
                Icon(Icons.bluetooth_searching, color: AppColors.textDisabled, size: 40),
                SizedBox(height: 12),
                Text('Buscando dispositivos BLE...',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ]),
            ),
          )
        else ...[
          Text('${results.length} dispositivo(s) encontrado(s)',
              style: const TextStyle(
                  color: AppColors.textDisabled, fontSize: 10, letterSpacing: 1)),
          const SizedBox(height: 8),
          ...results.map((r) => _DeviceTile(
            result: r,
            onTap: () => notifier.connectTo(r),
          )),
        ],

        const SizedBox(height: 16),
        _ActionButton(
          icon:  Icons.stop,
          label: 'Detener búsqueda',
          color: AppColors.warning,
          onTap: notifier.stopScan,
        ),
      ],
    );
  }
}

// ─── Connecting ───────────────────────────────────────────────────────────────

class _ConnectingContent extends StatelessWidget {
  const _ConnectingContent();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 32),
    child: Center(
      child: Column(children: [
        CircularProgressIndicator(color: AppColors.bleConnecting),
        SizedBox(height: 16),
        Text('Estableciendo conexión BLE...',
            style: TextStyle(color: AppColors.textSecondary)),
        SizedBox(height: 8),
        Text('Negociando MTU 247 bytes',
            style: TextStyle(color: AppColors.textDisabled, fontSize: 11)),
      ]),
    ),
  );
}

// ─── Disconnected ─────────────────────────────────────────────────────────────

class _DisconnectedContent extends StatelessWidget {
  final DeviceNotifier notifier;
  const _DisconnectedContent({required this.notifier});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'No hay ningún dispositivo emparejado.\n'
            'Asegúrate de que el GaitSole ESP32 está encendido y en rango BLE.',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5),
      ),
      const SizedBox(height: 24),
      _ActionButton(
        icon:  Icons.bluetooth_searching,
        label: 'Buscar dispositivos BLE',
        color: AppColors.accent,
        onTap: notifier.startScan,
      ),
    ],
  );
}

// ─── Device tile ─────────────────────────────────────────────────────────────

class _DeviceTile extends StatelessWidget {
  final ScanResult result;
  final VoidCallback onTap;
  const _DeviceTile({required this.result, required this.onTap});

  Color get _rssiColor {
    if (result.rssi > -60) return AppColors.success;
    if (result.rssi > -80) return AppColors.warning;
    return AppColors.danger;
  }

  IconData get _rssiIcon {
    if (result.rssi > -60) return Icons.signal_cellular_alt;
    if (result.rssi > -80) return Icons.signal_cellular_alt_2_bar;
    return Icons.signal_cellular_alt_1_bar;
  }

  // Destaca el dispositivo objetivo
  bool get _isTarget =>
      result.name.contains('ESP32') || result.name.contains('DAS');

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _isTarget
            ? AppColors.accent.withOpacity(0.07)
            : AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isTarget
              ? AppColors.accent.withOpacity(0.35)
              : AppColors.divider,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.bluetooth,
            color: _isTarget ? AppColors.accent : AppColors.textDisabled,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  result.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color:      _isTarget ? AppColors.accent : AppColors.textPrimary,
                    fontSize:   13,
                    fontWeight: _isTarget ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                Text(
                  result.id,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppColors.textDisabled, fontSize: 10),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Icon(_rssiIcon, color: _rssiColor, size: 16),
          const SizedBox(width: 4),
          Text('${result.rssi} dBm',
              style: TextStyle(color: _rssiColor, fontSize: 10)),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right, color: AppColors.textDisabled, size: 16),
        ],
      ),
    ),
  );
}

// ─── Firmware button ─────────────────────────────────────────────────────────

class _FwButton extends StatelessWidget {
  final _FwState fwState;
  final VoidCallback onTap;
  const _FwButton({required this.fwState, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isLoading = fwState == _FwState.checking;
    final Color color;
    final IconData icon;
    final String label;

    switch (fwState) {
      case _FwState.idle:
        color = AppColors.accent; icon = Icons.system_update_outlined;
        label = 'Buscar actualizaciones'; break;
      case _FwState.checking:
        color = AppColors.warning; icon = Icons.sync;
        label = 'Comprobando...'; break;
      case _FwState.upToDate:
        color = AppColors.success; icon = Icons.check_circle_outline;
        label = 'Firmware al día'; break;
    }

    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            isLoading
                ? SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: color))
                : Icon(icon, color: color, size: 18),
            const SizedBox(width: 10),
            Text(label, style: TextStyle(
                color: color, fontSize: 14, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final DeviceStatus status;
  const _StatusBadge({required this.status});

  Color get _color {
    switch (status) {
      case DeviceStatus.connected:    return AppColors.bleConnected;
      case DeviceStatus.connecting:   return AppColors.bleConnecting;
      case DeviceStatus.scanning:     return AppColors.bleConnecting;
      case DeviceStatus.disconnected: return AppColors.bleDisconnected;
    }
  }

  IconData get _icon {
    switch (status) {
      case DeviceStatus.connected:    return Icons.check_circle_outline;
      case DeviceStatus.connecting:   return Icons.pending_outlined;
      case DeviceStatus.scanning:     return Icons.search;
      case DeviceStatus.disconnected: return Icons.cancel_outlined;
    }
  }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(_icon, color: _color, size: 13),
      const SizedBox(width: 4),
      Text(status.name.toUpperCase(),
          style: TextStyle(
              color: _color, fontSize: 10,
              fontWeight: FontWeight.w700, letterSpacing: 0.8)),
    ],
  );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String   label, value;
  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 11),
    child: Row(
      children: [
        Icon(icon, color: AppColors.textDisabled, size: 16),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        const Spacer(),
        Text(value, style: const TextStyle(
            color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    ),
  );
}

class _ActionButton extends StatelessWidget {
  final IconData icon; final String label; final Color color; final VoidCallback onTap;
  const _ActionButton({required this.icon, required this.label,
    required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w600)),
      ]),
    ),
  );
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.danger.withOpacity(0.1),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.danger.withOpacity(0.3)),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline, color: AppColors.danger, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(message,
            style: const TextStyle(color: AppColors.danger, fontSize: 12))),
      ],
    ),
  );
}