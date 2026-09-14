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

  Future<void> signOut() {
    return _client.auth.signOut();
  }
}
