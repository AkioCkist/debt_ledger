import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_storage.dart';

class AuthService {
  final SupabaseClient _client = Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<void> signIn({
    required String email,
    required String password,
    required bool rememberLogin,
  }) async {
    await RememberLoginStorage.instance.setRememberLogin(rememberLogin);
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  /// Tự đăng ký. `display_name` đi vào `raw_user_meta_data` để trigger
  /// `handle_new_user` (supabase/schema.sql) tạo luôn dòng `profiles`.
  ///
  /// Khi project bật xác nhận email, [AuthResponse.session] là null: người
  /// dùng phải bấm link trong mail rồi quay lại đăng nhập.
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String displayName,
  }) {
    return _client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {'display_name': displayName.trim()},
    );
  }

  /// Supabase báo user đã xác nhận email hay chưa.
  ///
  /// Lưu ý: khi project **tắt** "Confirm email" thì GoTrue đóng dấu
  /// `email_confirmed_at` ngay lúc đăng ký, nên hàm này trả `true` — không
  /// phân biệt được. Vì vậy đây chỉ là chốt phòng ngừa, cấu hình đúng ở
  /// Dashboard vẫn là điều kiện bắt buộc.
  static bool isEmailConfirmed(User user) => user.emailConfirmedAt != null;

  Future<void> signOut() {
    return _client.auth.signOut();
  }
}
