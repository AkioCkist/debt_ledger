import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_profile.dart';

class ProfileService {
  final SupabaseClient _client = Supabase.instance.client;

  /// Hồ sơ của chính mình
  Future<AppProfile> fetchMyProfile(String uid) async {
    final row = await _client.from('profiles').select().eq('id', uid).single();
    return AppProfile.fromMap(row);
  }

  /// Vì app chỉ có đúng 2 tài khoản, "người kia" là profile còn lại
  Future<AppProfile> fetchOtherProfile(String uid) async {
    final row = await _client
        .from('profiles')
        .select()
        .neq('id', uid)
        .limit(1)
        .maybeSingle();

    if (row == null) {
      throw Exception(
        'Chưa tìm thấy tài khoản thứ hai. Hãy tạo đủ 2 tài khoản trong Supabase Authentication.',
      );
    }
    return AppProfile.fromMap(row);
  }
}
