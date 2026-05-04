// lib/shared/providers/user_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';
import '../../core/utils/fake_data.dart';

// ── Keys ──────────────────────────────────────────────────────────────────────
const _kSex    = 'profile_sex';
const _kWeight = 'profile_weight';
const _kHeight = 'profile_height';
const _kAge    = 'profile_age';
const _kAvatar = 'profile_avatar';
const _kName   = 'profile_name';

class UserProfileNotifier extends StateNotifier<UserProfile> {
  UserProfileNotifier()
      : super(const UserProfile(
    name:   FakeData.userName,
    sex:    FakeData.userSex,
    weight: FakeData.userWeight,
    height: FakeData.userHeight,
    age:    FakeData.userAge,
  )) {
    _load();
  }

  // ── Persistence ─────────────────────────────────────────────────────────────

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = UserProfile(
      name:       prefs.getString(_kName)   ?? FakeData.userName,
      sex:        prefs.getString(_kSex)    ?? FakeData.userSex,
      weight:     prefs.getDouble(_kWeight) ?? FakeData.userWeight,
      height:     prefs.getDouble(_kHeight) ?? FakeData.userHeight,
      age:        prefs.getInt(_kAge)       ?? FakeData.userAge,
      avatarPath: prefs.getString(_kAvatar),
    );
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kName,   state.name);
    await prefs.setString(_kSex,    state.sex);
    await prefs.setDouble(_kWeight, state.weight);
    await prefs.setDouble(_kHeight, state.height);
    await prefs.setInt(_kAge,       state.age);
    if (state.avatarPath != null) {
      await prefs.setString(_kAvatar, state.avatarPath!);
    }
  }

  // ── Updaters ─────────────────────────────────────────────────────────────────

  Future<void> saveAll({
    required String sex,
    required double weight,
    required double height,
    required int age,
  }) async {
    state = state.copyWith(sex: sex, weight: weight, height: height, age: age);
    await _save();
  }

  Future<void> updateAvatar(String path) async {
    state = state.copyWith(avatarPath: path);
    await _save();
  }
}

final userProfileProvider =
StateNotifierProvider<UserProfileNotifier, UserProfile>(
      (ref) => UserProfileNotifier(),
);