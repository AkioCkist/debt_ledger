/// Chuẩn hoá và đọc mã pairing ở phía client.
///
/// Mã do server sinh (xem RPC `create_pair_code`), ở đây chỉ kiểm tra hình
/// dạng trước khi gửi lên, để lỗi gõ nhầm hiện ra ngay chứ không phải chờ
/// một vòng mạng. Server vẫn kiểm tra lại toàn bộ.
class PairingCode {
  PairingCode._();

  /// Bảng chữ bỏ I, O, 0, 1 — trùng với bảng chữ trong RPC.
  static const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const length = 8;

  /// QR mang theo scheme của app để nếu người dùng quét bằng app khác thì
  /// vẫn thấy được nguồn, và để sau này nối deep link không phải đổi payload.
  static const uriScheme = 'sono';
  static const uriHost = 'pair';

  static final RegExp _pattern = RegExp('^[$alphabet]{$length}\$');

  /// Nhận mã người dùng gõ: bỏ khoảng trắng/gạch, đưa về chữ hoa.
  /// Trả về null nếu không đúng 8 ký tự thuộc bảng chữ.
  static String? normalize(String? raw) {
    if (raw == null) return null;
    final cleaned = raw.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
    if (!_pattern.hasMatch(cleaned)) return null;
    return cleaned;
  }

  static bool isValid(String? raw) => normalize(raw) != null;

  /// Nội dung nhúng trong QR.
  static String toQrPayload(String code) =>
      '$uriScheme://$uriHost?code=${code.toUpperCase()}';

  /// Đọc mã từ nội dung QR. Chấp nhận cả payload có scheme lẫn chuỗi mã trần
  /// (máy quét khác, hoặc QR do công cụ khác sinh).
  static String? fromQrPayload(String? raw) {
    final trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;

    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.scheme.toLowerCase() == uriScheme) {
      return normalize(uri.queryParameters['code']);
    }
    return normalize(trimmed);
  }

  /// Chia nhóm cho dễ đọc: `ABCD2345` -> `ABCD 2345`.
  static String formatForDisplay(String code) {
    final value = normalize(code) ?? code.toUpperCase();
    if (value.length != length) return value;
    return '${value.substring(0, 4)} ${value.substring(4)}';
  }
}
