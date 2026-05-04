// lib/features/profile/presentation/screens/profile_screen.dart
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/providers/user_provider.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late String _sex;
  late double _weight;
  late double _height;
  late int    _age;

  @override
  void initState() {
    super.initState();
    final p = ref.read(userProfileProvider);
    _sex    = p.sex;
    _weight = p.weight;
    _height = p.height;
    _age    = p.age;
  }

  // ── Image picker ──────────────────────────────────────────────────────────

  Future<void> _pickImage() async {
    // Request permission
    PermissionStatus status = await Permission.photos.request();

    // On Android 13+ photos permission may be 'limited' or granted
    if (status.isDenied) {
      status = await Permission.storage.request();
    }

    if (!status.isGranted && !status.isLimited) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Permiso denegado. Actívalo en los ajustes del sistema.'),
          backgroundColor: AppColors.danger.withOpacity(0.85),
          action: SnackBarAction(
            label: 'Ajustes',
            textColor: Colors.white,
            onPressed: () => openAppSettings(),
          ),
        ),
      );
      return;
    }

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );

    if (picked != null) {
      await ref.read(userProfileProvider.notifier).updateAvatar(picked.path);
    }
  }

  // ── Wheel pickers ─────────────────────────────────────────────────────────

  Future<void> _pickWeight() async {
    double selected = _weight;
    // Range 20–300 in 0.5 steps
    final values = [
      for (double v = 20.0; v <= 300.0; v += 0.5) v,
    ];
    int initialIdx = values.indexWhere((v) => (v - _weight).abs() < 0.25);
    if (initialIdx < 0) initialIdx = 110; // ~75 kg

    await _showWheelPicker(
      title: 'Peso',
      unit: 'kg',
      itemCount: values.length,
      initialIndex: initialIdx,
      labelBuilder: (i) => values[i].toStringAsFixed(1),
      onConfirm: (i) => setState(() => _weight = values[i]),
    );
  }

  Future<void> _pickHeight() async {
    // Range 100–250 cm in 1 cm steps
    final values = [for (int v = 100; v <= 250; v++) v.toDouble()];
    int initialIdx = (_height - 100).round().clamp(0, values.length - 1);

    await _showWheelPicker(
      title: 'Altura',
      unit: 'cm',
      itemCount: values.length,
      initialIndex: initialIdx,
      labelBuilder: (i) => '${values[i].toInt()}',
      onConfirm: (i) => setState(() => _height = values[i]),
    );
  }

  Future<void> _pickAge() async {
    // Range 5–120 in 1-year steps
    final values = [for (int v = 5; v <= 120; v++) v];
    int initialIdx = (_age - 5).clamp(0, values.length - 1);

    await _showWheelPicker(
      title: 'Edad',
      unit: 'años',
      itemCount: values.length,
      initialIndex: initialIdx,
      labelBuilder: (i) => '${values[i]}',
      onConfirm: (i) => setState(() => _age = values[i]),
    );
  }

  Future<void> _showWheelPicker({
    required String title,
    required String unit,
    required int itemCount,
    required int initialIndex,
    required String Function(int) labelBuilder,
    required void Function(int) onConfirm,
  }) async {
    int currentIdx = initialIndex;

    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: SizedBox(
            height: 320,
            child: Column(
              children: [
                // Handle
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 4),
                  child: Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.textDisabled,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Title row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancelar',
                            style: TextStyle(color: AppColors.textSecondary)),
                      ),
                      Text(title,
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 16)),
                      TextButton(
                        onPressed: () {
                          onConfirm(currentIdx);
                          Navigator.pop(ctx);
                        },
                        child: const Text('OK',
                            style: TextStyle(
                                color: AppColors.accent,
                                fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
                const Divider(color: AppColors.divider, height: 1),
                // Wheel
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 140,
                        child: CupertinoPicker(
                          scrollController: FixedExtentScrollController(
                              initialItem: initialIndex),
                          itemExtent: 44,
                          backgroundColor: Colors.transparent,
                          selectionOverlay: CupertinoPickerDefaultSelectionOverlay(
                            background: AppColors.accent.withOpacity(0.08),
                          ),
                          onSelectedItemChanged: (i) => currentIdx = i,
                          children: [
                            for (int i = 0; i < itemCount; i++)
                              Center(
                                child: Text(
                                  labelBuilder(i),
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w300,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(unit,
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 16)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    await ref.read(userProfileProvider.notifier).saveAll(
      sex: _sex, weight: _weight, height: _height, age: _age,
    );
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Perfil guardado'),
        backgroundColor: AppColors.bgCard,
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider);

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        title: const Text('Perfil'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Guardar',
                style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // ── Avatar ────────────────────────────────────────────────
            _AvatarSection(
              avatarPath: profile.avatarPath,
              name: profile.name,
              onTap: _pickImage,
            ),
            const SizedBox(height: 28),

            const _SectionLabel('DATOS FISIOLÓGICOS'),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: AppColors.bgCard,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  // Sex
                  _PickerRow(
                    icon: Icons.wc_outlined,
                    label: 'Sexo',
                    value: _sex,
                    onTap: () async {
                      await _showWheelPicker(
                        title: 'Sexo',
                        unit: '',
                        itemCount: 2,
                        initialIndex: _sex == 'Hombre' ? 0 : 1,
                        labelBuilder: (i) => i == 0 ? 'Hombre' : 'Mujer',
                        onConfirm: (i) => setState(() => _sex = i == 0 ? 'Hombre' : 'Mujer'),
                      );
                    },
                  ),
                  const Divider(color: AppColors.divider, height: 1),
                  // Weight
                  _PickerRow(
                    icon: Icons.monitor_weight_outlined,
                    label: 'Peso',
                    value: '${_weight.toStringAsFixed(1)} kg',
                    onTap: _pickWeight,
                  ),
                  const Divider(color: AppColors.divider, height: 1),
                  // Height
                  _PickerRow(
                    icon: Icons.height_outlined,
                    label: 'Altura',
                    value: '${_height.toInt()} cm',
                    onTap: _pickHeight,
                  ),
                  const Divider(color: AppColors.divider, height: 1),
                  // Age
                  _PickerRow(
                    icon: Icons.cake_outlined,
                    label: 'Edad',
                    value: '$_age años',
                    onTap: _pickAge,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// ─── Avatar Section ───────────────────────────────────────────────────────────

class _AvatarSection extends StatelessWidget {
  final String? avatarPath;
  final String name;
  final VoidCallback onTap;

  const _AvatarSection({
    required this.avatarPath,
    required this.name,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasAvatar = avatarPath != null && avatarPath!.isNotEmpty;
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Stack(
            children: [
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.bgCard,
                  border: Border.all(color: AppColors.accent.withOpacity(0.5), width: 2),
                  image: hasAvatar
                      ? DecorationImage(
                    image: FileImage(File(avatarPath!)),
                    fit: BoxFit.cover,
                  )
                      : null,
                ),
                child: hasAvatar
                    ? null
                    : const Icon(Icons.person, size: 48, color: AppColors.textSecondary),
              ),
              Positioned(
                right: 0, bottom: 0,
                child: Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.bgPrimary, width: 2),
                  ),
                  child: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(name,
            style: const TextStyle(
                color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: onTap,
          child: const Text('Cambiar foto',
              style: TextStyle(color: AppColors.accent, fontSize: 13)),
        ),
      ],
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(label,
          style: const TextStyle(
              color: AppColors.textDisabled, fontSize: 10,
              fontWeight: FontWeight.w600, letterSpacing: 1.5)),
    );
  }
}

class _PickerRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _PickerRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            Icon(icon, color: AppColors.textDisabled, size: 18),
            const SizedBox(width: 12),
            Text(label,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
            const Spacer(),
            Text(value,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, color: AppColors.textDisabled, size: 16),
          ],
        ),
      ),
    );
  }
}