import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'config.dart';
import 'services/auth_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initializeDateFormatting('vi_VN', null);
  await dotenv.load(isOptional: true);

  if (!AppConfig.isConfigured) {
    runApp(const _MissingConfigApp());
    return;
  }

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
    authOptions: FlutterAuthClientOptions(
      localStorage: RememberLoginStorage.instance,
    ),
  );

  runApp(const DebtLedgerApp());
}

/// Màn hình hiển thị khi chưa truyền SUPABASE_URL / SUPABASE_ANON_KEY lúc build.
class _MissingConfigApp extends StatelessWidget {
  const _MissingConfigApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFFAFAF8),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.settings_outlined, size: 40, color: Color(0xFF6F6D68)),
                SizedBox(height: 16),
                Text(
                  'Thiếu cấu hình Supabase',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 8),
                Text(
                  'Hãy chạy app với:\n'
                  'flutter run --dart-define-from-file=.env\n\n'
                  'Xem chi tiết trong README.md',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13.5, color: Color(0xFF6F6D68)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
