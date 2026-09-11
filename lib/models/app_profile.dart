class AppProfile {
  final String id;
  final String displayName;
  final String email;

  const AppProfile({
    required this.id,
    required this.displayName,
    required this.email,
  });

  factory AppProfile.fromMap(Map<String, dynamic> map) {
    return AppProfile(
      id: map['id'] as String,
      displayName: (map['display_name'] as String?)?.trim().isNotEmpty == true
          ? map['display_name'] as String
          : (map['email'] as String? ?? 'Người dùng'),
      email: map['email'] as String? ?? '',
    );
  }
}
