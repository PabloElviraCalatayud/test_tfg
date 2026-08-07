// lib/core/widgets/app_scaffold.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_colors.dart';
import '../../shared/providers/device_provider.dart';
import '../../shared/providers/user_provider.dart';
import '../../features/device/presentation/screens/device_bottom_sheet.dart';

class AppScaffold extends ConsumerWidget {
  final Widget child;
  const AppScaffold({super.key, required this.child});

  int _locationToIndex(String location) {
    if (location.startsWith('/debug')) return 1;
    return 0;
  }

  void _onNavTap(BuildContext context, int index) {
    switch (index) {
      case 0: context.go('/dashboard'); break;
      case 1: context.go('/debug'); break;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location     = GoRouterState.of(context).uri.toString();
    final currentIndex = _locationToIndex(location);
    final device = ref.watch(deviceProvider);
    final user   = ref.watch(userProfileProvider);

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        backgroundColor: AppColors.bgPrimary,
        automaticallyImplyLeading: false,
        titleSpacing: 12,
        title: Row(
          children: [
            // ── Avatar ──────────────────────────────────────
            GestureDetector(
              onTap: () => context.push('/profile'),
              child: _UserAvatar(avatarPath: user.avatarPath),
            ),
            const SizedBox(width: 10),

            // ── Title immediately right of avatar ───────────
            const Text(
              'GAIT',
              style: TextStyle(
                color: AppColors.accent,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: 4,
              ),
            ),

            const Spacer(),

            // ── Device button ────────────────────────────────
            GestureDetector(
              onTap: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const DeviceBottomSheet(),
              ),
              child: _DeviceButton(device: device),
            ),
          ],
        ),
      ),
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (i) => _onNavTap(context, i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Inicio',
          ),
          NavigationDestination(
            icon: Icon(Icons.bug_report_outlined),
            selectedIcon: Icon(Icons.bug_report),
            label: 'Debug',
          ),
        ],
      ),
    );
  }
}

// ─── User Avatar ──────────────────────────────────────────────────────────────

class _UserAvatar extends StatelessWidget {
  final String? avatarPath;
  const _UserAvatar({this.avatarPath});

  @override
  Widget build(BuildContext context) {
    final hasAvatar = avatarPath != null && avatarPath!.isNotEmpty;
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.bgCard,
        border: Border.all(color: AppColors.accent.withOpacity(0.4), width: 1.5),
        image: hasAvatar
            ? DecorationImage(
          image: FileImage(File(avatarPath!)),
          fit: BoxFit.cover,
        )
            : null,
      ),
      child: hasAvatar
          ? null
          : const Icon(Icons.person, color: AppColors.textSecondary, size: 20),
    );
  }
}

// ─── Device Button ────────────────────────────────────────────────────────────

class _DeviceButton extends StatelessWidget {
  final DeviceInfo device;
  const _DeviceButton({required this.device});

  Color get _color {
    switch (device.status) {
      case DeviceStatus.connected:    return AppColors.bleConnected;
      case DeviceStatus.connecting:   return AppColors.bleConnecting;
      case DeviceStatus.scanning:     return AppColors.bleConnecting;
      case DeviceStatus.disconnected: return AppColors.bleDisconnected;
    }
  }

  IconData get _icon {
    switch (device.status) {
      case DeviceStatus.connected:    return Icons.sensors;
      case DeviceStatus.connecting:   return Icons.sensors_outlined;
      case DeviceStatus.scanning:     return Icons.bluetooth_searching;
      case DeviceStatus.disconnected: return Icons.sensors_off_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, color: _color, size: 16),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                switch (device.status) {
                  DeviceStatus.connected    => device.name ?? 'Dispositivo',
                  DeviceStatus.connecting   => 'Conectando...',
                  DeviceStatus.scanning     => 'Buscando...',
                  DeviceStatus.disconnected => 'Sin dispositivo',
                },
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _color, fontSize: 10, fontWeight: FontWeight.w600,
                ),
              ),
              if (device.status == DeviceStatus.connected && device.battery != null)
                Text('${device.battery}%',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 9)),
            ],
          ),
        ],
      ),
    );
  }
}