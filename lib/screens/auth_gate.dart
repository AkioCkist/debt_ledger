import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import 'login_screen.dart';
import 'lobby_screen.dart';

/// Lắng nghe trạng thái đăng nhập và điều hướng giữa LoginScreen / LobbyScreen.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _authService = AuthService();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: _authService.authStateChanges,
      initialData: AuthState(
        AuthChangeEvent.initialSession,
        Supabase.instance.client.auth.currentSession,
      ),
      builder: (context, snapshot) {
        final session = snapshot.data?.session;
        if (session != null) {
          // key theo user id để rebuild lại toàn bộ cây (sảnh, danh bạ) khi
          // đổi tài khoản
          return LobbyScreen(key: ValueKey(session.user.id));
        }
        return const LoginScreen();
      },
    );
  }
}
