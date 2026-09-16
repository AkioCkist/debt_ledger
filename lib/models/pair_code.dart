/// Mã pairing do server sinh (RPC `create_pair_code`).
///
/// Client không bao giờ tự sinh mã: mã là credential, phải ngẫu nhiên bảo mật
/// và chỉ tồn tại trong thời gian ngắn.
class PairCode {
  final String code;
  final DateTime expiresAt;

  const PairCode({required this.code, required this.expiresAt});

  factory PairCode.fromMap(Map<String, dynamic> map) {
    return PairCode(
      code: (map['code'] as String).toUpperCase(),
      expiresAt: DateTime.parse(map['expires_at'] as String).toLocal(),
    );
  }

  bool isExpiredAt(DateTime now) => !expiresAt.isAfter(now);

  Duration remainingAt(DateTime now) {
    final left = expiresAt.difference(now);
    return left.isNegative ? Duration.zero : left;
  }
}
