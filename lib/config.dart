import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Cấu hình Supabase, ưu tiên giá trị trong .env và hỗ trợ --dart-define.
class AppConfig {
  static String get supabaseUrl =>
      dotenv.maybeGet('SUPABASE_URL') ??
      const String.fromEnvironment('SUPABASE_URL');
  static String get supabaseAnonKey =>
      dotenv.maybeGet('SUPABASE_ANON_KEY') ??
      const String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
