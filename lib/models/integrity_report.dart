/// Mức độ nghiêm trọng của một phát hiện khi đối soát dữ liệu.
enum IntegritySeverity {
  /// Thông tin bình thường (có giao dịch mới, chưa có mốc đối soát...).
  info,

  /// Bất thường nhẹ / dữ liệu cũ chưa chuẩn, không ảnh hưởng số dư.
  warning,

  /// Dấu hiệu dữ liệu bị sửa/xoá ngoài luồng hoặc sai lệch số dư.
  critical,
}

class IntegrityFinding {
  final IntegritySeverity severity;

  /// Mã ổn định, dùng cho test và tra cứu.
  final String code;

  final String title;
  final String message;
  final String? transactionId;

  const IntegrityFinding({
    required this.severity,
    required this.code,
    required this.title,
    required this.message,
    this.transactionId,
  });

  @override
  String toString() => '[$code] $title: $message';
}

class IntegrityReport {
  final DateTime checkedAt;

  /// Lần đầu chạy: chưa có mốc đối soát nên chưa thể kết luận gì.
  final bool hasBaseline;

  /// Database đã chạy migration (có cột `version`) hay chưa.
  final bool databaseTracksVersions;

  final List<IntegrityFinding> findings;
  final int rowCount;

  /// Số dư client tính từ chính các dòng nó đọc được.
  final num clientBalance;

  /// Số dư server tính qua RPC; null nếu không gọi được RPC.
  final num? serverBalance;

  final String? ledgerHash;

  /// Số dòng thay đổi hợp lệ (mới tạo / được xác nhận) so với mốc.
  final int changedSinceBaseline;

  /// Ghi chú khi phải suy giảm chức năng (ví dụ không gọi được RPC).
  final String? note;

  const IntegrityReport({
    required this.checkedAt,
    required this.hasBaseline,
    required this.databaseTracksVersions,
    required this.findings,
    required this.rowCount,
    required this.clientBalance,
    required this.changedSinceBaseline,
    this.serverBalance,
    this.ledgerHash,
    this.note,
  });

  Iterable<IntegrityFinding> get criticals =>
      findings.where((f) => f.severity == IntegritySeverity.critical);

  Iterable<IntegrityFinding> get warnings =>
      findings.where((f) => f.severity == IntegritySeverity.warning);

  Iterable<IntegrityFinding> get infos =>
      findings.where((f) => f.severity == IntegritySeverity.info);

  int get criticalCount => criticals.length;
  int get warningCount => warnings.length;

  /// Có gì đó bất thường cần người dùng biết.
  bool get hasProblems => criticalCount > 0 || warningCount > 0;

  /// Không có phát hiện nghiêm trọng: an toàn để chốt mốc đối soát mới.
  bool get isTrusted => criticalCount == 0;
}
