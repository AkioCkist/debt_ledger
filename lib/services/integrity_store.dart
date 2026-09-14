import 'package:shared_preferences/shared_preferences.dart';

import '../models/sync_checkpoint.dart';

/// Lưu mốc đối soát trên máy, tách riêng theo từng tài khoản.
///
/// Không chứa secret: đây chỉ là bản chụp trạng thái để so sánh, mất dữ liệu
/// cũng chỉ khiến app chốt lại mốc mới chứ không làm hỏng sổ nợ.
class IntegrityStore {
  IntegrityStore._();

  static final IntegrityStore instance = IntegrityStore._();

  static const _keyPrefix = 'debt_ledger.integrity.checkpoint.';

  Future<SyncCheckpoint?> read(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_keyPrefix$userId');
      if (raw == null) return null;
      return SyncCheckpoint.fromJson(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(SyncCheckpoint checkpoint) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_keyPrefix${checkpoint.userId}',
        checkpoint.encode(),
      );
    } catch (_) {
      // Không lưu được mốc không phải lỗi chặn app.
    }
  }

  Future<void> clear(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_keyPrefix$userId');
    } catch (_) {}
  }
}
