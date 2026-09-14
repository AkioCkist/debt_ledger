import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/debt_transaction.dart';

/// Các phép tính / dấu vân tay dùng chung cho sổ nợ.
///
/// Tách khỏi UI để màn hình chính và màn hình đối soát dùng đúng một công thức.
/// Công thức số dư (theo README): chỉ tính giao dịch `accepted`,
/// cộng `amount` nếu mình là người tạo, trừ `amount` nếu mình là người nhận.
class LedgerMath {
  LedgerMath._();

  static num computeBalance(List<DebtTransaction> txs, String myId) {
    num balance = 0;
    for (final tx in txs) {
      if (!tx.isAccepted) continue;
      balance += tx.createdBy == myId ? tx.amount : -tx.amount;
    }
    return balance;
  }

  /// Bản dùng trực tiếp trên row thô từ Supabase (đối soát không cần parse model).
  static num computeRawBalance(
    Iterable<Map<String, dynamic>> rows,
    String myId,
  ) {
    num balance = 0;
    for (final row in rows) {
      if (row['status'] != 'accepted') continue;
      final amount = row['amount'];
      if (amount is! num) continue;
      balance += row['created_by'] == myId ? amount : -amount;
    }
    return balance;
  }

  /// Id của row, trả về null nếu row hỏng.
  static String? rowId(Map<String, dynamic> row) {
    final id = row['id'];
    return id is String && id.isNotEmpty ? id : null;
  }

  /// Dấu vân tay của các field mà database đã khoá cứng
  /// (`transactions_guard`): không bao giờ được đổi sau khi tạo.
  /// Sai lệch ở đây nghĩa là dữ liệu bị sửa ngoài luồng.
  static String immutableFingerprint(Map<String, dynamic> row) {
    final payload = <String>[
      _text(row['id']),
      _text(row['created_by']),
      _text(row['recipient_id']),
      _text(row['type']),
      _amountKey(row['amount']),
      _text(row['description']),
      // Dùng chuỗi thô do server trả về, không qua DateTime, để tránh
      // sai lệch do làm tròn / đổi múi giờ khi so sánh giữa các lần chạy.
      _text(row['created_at']),
    ].join('');

    return sha256.convert(utf8.encode(payload)).toString();
  }

  /// Trạng thái có thể đổi hợp lệ (waiting -> accepted/declined),
  /// nên phải lưu riêng khỏi [immutableFingerprint].
  static String stateSignature(Map<String, dynamic> row) {
    return '${_text(row['status'])}|${_text(row['responded_at'])}';
  }

  /// Phần `status` của [stateSignature].
  static String statusOf(String stateSignature) {
    final index = stateSignature.indexOf('|');
    return index < 0 ? stateSignature : stateSignature.substring(0, index);
  }

  static int versionOf(Map<String, dynamic> row) {
    final version = row['version'];
    return version is num ? version.toInt() : 0;
  }

  static bool hasVersionColumn(Map<String, dynamic> row) =>
      row['version'] is num;

  static String? maxUpdatedAt(List<Map<String, dynamic>> rows) {
    DateTime? max;
    String? raw;
    for (final row in rows) {
      final value = row['updated_at'] ?? row['created_at'];
      if (value is! String) continue;
      final parsed = DateTime.tryParse(value);
      if (parsed == null) continue;
      if (max == null || parsed.isAfter(max)) {
        max = parsed;
        raw = value;
      }
    }
    return raw;
  }

  /// Số của PostgREST có thể về dạng int (1500000) hoặc double (1500000.0)
  /// tuỳ phiên bản; chuẩn hoá để vân tay không đổi giữa các lần chạy.
  static String _amountKey(Object? value) {
    if (value is! num) return _text(value);
    if (value is int) return value.toString();
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }

  static String _text(Object? value) => value?.toString() ?? '';
}
