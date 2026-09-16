import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_profile.dart';

class ProfileService {
  SupabaseClient get _client => Supabase.instance.client;

  /// Hồ sơ của chính mình
  Future<AppProfile> fetchMyProfile(String uid) async {
    final row = await _client.from('profiles').select().eq('id', uid).single();
    return AppProfile.fromMap(row);
  }

  /// Hồ sơ của nhiều người trong một lượt (danh bạ ở sảnh).
  ///
  /// RLS chỉ trả về người mình được phép thấy: chính mình, người đã pair,
  /// hoặc người đang có lời mời với mình. Id không thấy được thì đơn giản là
  /// không có trong kết quả.
  Future<Map<String, AppProfile>> fetchProfilesByIds(
    Iterable<String> ids,
  ) async {
    final unique = ids.toSet().toList();
    if (unique.isEmpty) return const {};

    final rows = await _client.from('profiles').select().inFilter('id', unique);
    return {
      for (final row in rows)
        row['id'] as String: AppProfile.fromMap(row),
    };
  }
}
