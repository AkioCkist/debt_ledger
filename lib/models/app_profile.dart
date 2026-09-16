class AppProfile {
  final String id;
  final String displayName;
  final String email;

  const AppProfile({
    required this.id,
    required this.displayName,
    required this.email,
  });

  /// Ký tự đầu của tên, dùng làm avatar chữ ở sảnh.
  String get initial {
    final name = displayName.trim();
    return name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();
  }

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
