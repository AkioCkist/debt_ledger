import 'package:supabase_flutter/supabase_flutter.dart';

/// Tên riêng mình đặt cho bạn nợ (bảng `contact_aliases`).
///
/// Chỉ lưu phía mình: RLS bắt mọi lệnh phải có `owner_id = auth.uid()`, nên
/// đối phương không đọc được tên này.
class ContactAliasService {
  SupabaseClient get _client => Supabase.instance.client;

  String? get _uid => _client.auth.currentUser?.id;

  /// Bản đồ `contactId -> alias` của chính mình.
  Future<Map<String, String>> fetchAliases() async {
    final uid = _uid;
    if (uid == null) return const {};

    final rows = await _client
        .from('contact_aliases')
        .select('contact_id, alias')
        .eq('owner_id', uid);

    return {
      for (final row in rows)
        row['contact_id'] as String: row['alias'] as String,
    };
  }

  Future<void> upsertAlias({
    required String contactId,
    required String alias,
  }) async {
    final uid = _uid;
    if (uid == null) return;

    await _client.from('contact_aliases').upsert({
      'owner_id': uid,
      'contact_id': contactId,
      'alias': alias.trim(),
    }, onConflict: 'owner_id,contact_id');
  }

  Future<void> clearAlias(String contactId) async {
    final uid = _uid;
    if (uid == null) return;

    await _client
        .from('contact_aliases')
        .delete()
        .eq('owner_id', uid)
        .eq('contact_id', contactId);
  }
}
