// lib/shared/models/user_profile.dart

class UserProfile {
  final String name;
  final String sex; // 'Hombre' | 'Mujer'
  final double weight; // kg
  final double height; // cm
  final int age;
  final String? avatarPath;

  const UserProfile({
    required this.name,
    required this.sex,
    required this.weight,
    required this.height,
    required this.age,
    this.avatarPath,
  });

  UserProfile copyWith({
    String? name,
    String? sex,
    double? weight,
    double? height,
    int? age,
    String? avatarPath,
  }) {
    return UserProfile(
      name: name ?? this.name,
      sex: sex ?? this.sex,
      weight: weight ?? this.weight,
      height: height ?? this.height,
      age: age ?? this.age,
      avatarPath: avatarPath ?? this.avatarPath,
    );
  }
}