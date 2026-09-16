import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/connection.dart';
import '../models/pair_code.dart';

/// Quan hệ bạn nợ (bảng `connections`) và mã pairing (bảng `pair_invites`).
///
/// Mã pairing KHÔNG đọc/ghi trực tiếp được từ client: `pair_invites` bật RLS
/// và không có policy nào, chỉ vào được qua hai RPC security definer.
class ConnectionService {
  /// Truy cập muộn để phần ghép dữ liệu thuần test được mà không cần Supabase.
  SupabaseClient get _client => Supabase.instance.client;

  /// Realtime toàn bộ quan hệ liên quan đến mình (RLS tự lọc).
  /// Nhờ vậy người nhận thấy lời mời ngay khi đang mở sảnh.
  Stream<List<DebtConnection>> streamMyConnections() {
    return _client
        .from('connections')
        .stream(primaryKey: ['id'])
        .map((rows) => rows.map(DebtConnection.fromMap).toList());
  }

  Future<List<DebtConnection>> fetchMyConnections() async {
    final rows = await _client.from('connections').select();
    return rows.map(DebtConnection.fromMap).toList();
  }

  /// Sinh mã mới (huỷ mã cũ nếu còn hạn). Mã chỉ dùng được một lần.
  Future<PairCode> createPairCode({int ttlMinutes = 10}) async {
    final response = await _client.rpc(
      'create_pair_code',
      params: {'p_ttl_minutes': ttlMinutes},
    );
    return PairCode.fromMap((response as Map).cast<String, dynamic>());
  }

  /// Nhập mã của người kia để gửi lời mời. Trả về id quan hệ vừa tạo.
  Future<String?> redeemPairCode(String code) async {
    final response = await _client.rpc(
      'redeem_pair_code',
      params: {'p_code': code.toUpperCase()},
    );
    final map = (response as Map).cast<String, dynamic>();
    return map['connection_id'] as String?;
  }

  /// Đồng ý / từ chối lời mời. Database chỉ cho người nhận đổi `status`.
  Future<void> respond({
    required String connectionId,
    required bool accept,
  }) async {
    await _client
        .from('connections')
        .update({'status': accept ? 'accepted' : 'declined'})
        .eq('id', connectionId);
  }
}
