import 'dart:convert';

/// Dấu vân tay của một giao dịch tại thời điểm chốt mốc đối soát.
class RowFingerprint {
  /// SHA-256 các field bất biến (amount, type, created_by...).
  final String immutableHash;

  /// Trạng thái + thời gian phản hồi, dạng thô do server trả về.
  final String state;

  final int version;

  const RowFingerprint({
    required this.immutableHash,
    required this.state,
    required this.version,
  });

  Map<String, dynamic> toJson() => {
        'h': immutableHash,
        's': state,
        'v': version,
      };

  static RowFingerprint fromJson(Map<String, dynamic> json) => RowFingerprint(
        immutableHash: (json['h'] as String?) ?? '',
        state: (json['s'] as String?) ?? '',
        version: (json['v'] as num?)?.toInt() ?? 0,
      );
}

/// Mốc đối soát: trạng thái sổ nợ mà client đã kiểm tra và chấp nhận.
///
/// Chỉ được ghi đè khi dữ liệu khớp (hoặc khi người dùng chủ động chốt lại),
/// nhờ vậy mọi thay đổi ngoài luồng vẫn còn nguyên để phát hiện ở lần sau.
class SyncCheckpoint {
  final String userId;
  final DateTime syncedAt;

  /// `updated_at` lớn nhất tại thời điểm chốt — mốc để hỏi server
  /// "có gì đổi kể từ lúc này".
  final String? maxUpdatedAt;

  final num balance;
  final int rowCount;

  /// `ledger_hash` server trả về lần chốt gần nhất.
  final String? ledgerHash;

  final Map<String, RowFingerprint> rows;

  const SyncCheckpoint({
    required this.userId,
    required this.syncedAt,
    required this.balance,
    required this.rowCount,
    required this.rows,
    this.maxUpdatedAt,
    this.ledgerHash,
  });

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'syncedAt': syncedAt.toIso8601String(),
        'maxUpdatedAt': maxUpdatedAt,
        'balance': balance,
        'rowCount': rowCount,
        'ledgerHash': ledgerHash,
        'rows': rows.map((id, fp) => MapEntry(id, fp.toJson())),
      };

  String encode() => jsonEncode(toJson());

  static SyncCheckpoint? fromJson(String raw) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final rowsJson = json['rows'] as Map<String, dynamic>? ?? const {};
      return SyncCheckpoint(
        userId: (json['userId'] as String?) ?? '',
        syncedAt:
            DateTime.tryParse((json['syncedAt'] as String?) ?? '') ??
                DateTime.now(),
        maxUpdatedAt: json['maxUpdatedAt'] as String?,
        balance: (json['balance'] as num?) ?? 0,
        rowCount: (json['rowCount'] as num?)?.toInt() ?? 0,
        ledgerHash: json['ledgerHash'] as String?,
        rows: rowsJson.map(
          (id, value) => MapEntry(
            id,
            RowFingerprint.fromJson(value as Map<String, dynamic>),
          ),
        ),
      );
    } catch (_) {
      // Mốc hỏng thì coi như chưa có; app sẽ chốt lại mốc mới, không crash.
      return null;
    }
  }
}
