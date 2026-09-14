/// Kết quả RPC `ledger_snapshot()`: server tự tính lại sổ nợ để client đối chiếu.
///
/// RPC chạy với SECURITY INVOKER nên vẫn chịu RLS — chỉ thấy đúng các dòng
/// mà người dùng hiện tại được phép đọc.
class LedgerSnapshot {
  final int totalCount;
  final int acceptedCount;
  final int pendingCount;
  final int declinedCount;
  final int maxVersion;
  final String? maxUpdatedAt;

  /// Số dư ròng do server tính, cùng công thức với client.
  final num netBalance;

  /// SHA-256 của toàn bộ giao dịch đã `accepted` (theo thứ tự created_at, id).
  final String ledgerHash;

  const LedgerSnapshot({
    required this.totalCount,
    required this.acceptedCount,
    required this.pendingCount,
    required this.declinedCount,
    required this.maxVersion,
    required this.netBalance,
    required this.ledgerHash,
    this.maxUpdatedAt,
  });

  factory LedgerSnapshot.fromMap(Map<String, dynamic> map) {
    int intOf(String key) => (map[key] as num?)?.toInt() ?? 0;
    return LedgerSnapshot(
      totalCount: intOf('total_count'),
      acceptedCount: intOf('accepted_count'),
      pendingCount: intOf('pending_count'),
      declinedCount: intOf('declined_count'),
      maxVersion: intOf('max_version'),
      maxUpdatedAt: map['max_updated_at'] as String?,
      netBalance: (map['net_balance'] as num?) ?? 0,
      ledgerHash: (map['ledger_hash'] as String?) ?? '',
    );
  }
}
