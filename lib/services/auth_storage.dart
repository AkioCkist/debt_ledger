import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RememberLoginStorage extends LocalStorage {
  RememberLoginStorage._();

  static final instance = RememberLoginStorage._();

  static const _sessionKey = 'debt_ledger.auth.session';
  static const _rememberLoginKey = 'debt_ledger.auth.remember_login';

  late SharedPreferences _preferences;
  bool _rememberLogin = true;

  @override
  Future<void> initialize() async {
    _preferences = await SharedPreferences.getInstance();
    _rememberLogin = _preferences.getBool(_rememberLoginKey) ?? true;
    if (!_rememberLogin) {
      await _removeSession();
    }
  }

  Future<void> setRememberLogin(bool value) async {
    _rememberLogin = value;
    await _preferences.setBool(_rememberLoginKey, value);
    if (!value) {
      await _removeSession();
    }
  }

  @override
  Future<bool> hasAccessToken() async {
    return _rememberLogin && _preferences.containsKey(_sessionKey);
  }

  @override
  Future<String?> accessToken() async {
    return _rememberLogin ? _preferences.getString(_sessionKey) : null;
  }

  @override
  Future<void> removePersistedSession() async {
    await _removeSession();
    await _preferences.remove(_rememberLoginKey);
    _rememberLogin = true;
  }

  Future<void> _removeSession() async {
    await _preferences.remove(_sessionKey);
  }

  @override
  Future<void> persistSession(String session) async {
    if (_rememberLogin) {
      await _preferences.setString(_sessionKey, session);
    }
  }
}