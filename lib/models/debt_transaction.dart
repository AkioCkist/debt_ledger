enum TxType {
  debt, // ghi nợ: người nhận đang nợ người tạo khoản tiền này
  payment; // trả nợ: người tạo trả tiền cho người nhận để giảm nợ

  static TxType fromString(String value) {
    return TxType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => TxType.debt,
    );
  }
}

enum TxStatus {
  waiting,
  accepted,
  declined;

  static TxStatus fromString(String value) {
    return TxStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => TxStatus.waiting,
    );
  }
}

class DebtTransaction {
  final String id;
  final String createdBy;
  final String recipientId;
  final TxType type;
  final num amount;
  final String description;
  final TxStatus status;
  final DateTime createdAt;
  final DateTime? respondedAt;

  /// Lần thay đổi gần nhất, do trigger phía database ghi.
  /// Rơi về [createdAt] nếu database chưa chạy migration.
  final DateTime updatedAt;

  /// Số lần bản ghi bị UPDATE, do trigger phía database ghi.
  /// Bằng 1 với dòng mới tạo; bằng 0 nghĩa là database chưa chạy migration.
  final int version;

  const DebtTransaction({
    required this.id,
    required this.createdBy,
    required this.recipientId,
    required this.type,
    required this.amount,
    required this.description,
    required this.status,
    required this.createdAt,
    this.respondedAt,
    DateTime? updatedAt,
    this.version = 0,
  }) : updatedAt = updatedAt ?? createdAt;

  factory DebtTransaction.fromMap(Map<String, dynamic> map) {
    final createdAt = DateTime.parse(map['created_at'] as String).toLocal();
    final respondedAt = map['responded_at'];
    final updatedAt = map['updated_at'];

    return DebtTransaction(
      id: map['id'] as String,
      createdBy: map['created_by'] as String,
      recipientId: map['recipient_id'] as String,
      type: TxType.fromString(map['type'] as String),
      amount: (map['amount'] as num),
      description: (map['description'] as String?) ?? '',
      status: TxStatus.fromString(map['status'] as String),
      createdAt: createdAt,
      respondedAt:
          respondedAt != null ? DateTime.parse(respondedAt as String).toLocal() : null,
      updatedAt:
          updatedAt != null ? DateTime.parse(updatedAt as String).toLocal() : createdAt,
      version: (map['version'] as num?)?.toInt() ?? 0,
    );
  }

  bool get isWaiting => status == TxStatus.waiting;
  bool get isAccepted => status == TxStatus.accepted;
  bool get isDeclined => status == TxStatus.declined;
}
