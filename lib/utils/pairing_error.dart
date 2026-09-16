/// Dịch lỗi từ RPC pairing sang câu tiếng Việt cho người dùng.
///
/// Server ném lỗi bằng `raise exception '<MÃ>' using errcode = ...` nên chỉ cần
/// so khớp mã lỗi trong chuỗi, không phụ thuộc loại exception của Supabase
/// (nhờ vậy hàm này test được mà không cần khởi tạo client).
String pairingErrorMessage(Object? error) {
  if (error == null) return 'Đã có lỗi xảy ra. Vui lòng thử lại.';

  final raw = error.toString();

  String? match(List<String> codes) {
    for (final code in codes) {
      if (raw.contains(code)) return code;
    }
    return null;
  }

  switch (match(const [
    'PAIR_CODE_INVALID',
    'PAIR_CODE_SELF',
    'ALREADY_CONNECTED',
    'PAIR_REQUEST_EXISTS',
    'NOT_AUTHENTICATED',
    'PAIR_CODE_GENERATION_FAILED',
    'FORBIDDEN',
  ])) {
    case 'PAIR_CODE_INVALID':
      return 'Mã không đúng hoặc đã hết hạn. Hãy xin mã mới.';
    case 'PAIR_CODE_SELF':
      return 'Đây là mã của chính bạn. Hãy nhập mã của người kia.';
    case 'ALREADY_CONNECTED':
      return 'Hai bạn đã là bạn nợ của nhau rồi.';
    case 'PAIR_REQUEST_EXISTS':
      return 'Đang có một lời mời chờ trả lời giữa hai bạn.';
    case 'NOT_AUTHENTICATED':
      return 'Phiên đăng nhập đã hết hạn. Hãy đăng nhập lại.';
    case 'PAIR_CODE_GENERATION_FAILED':
      return 'Chưa tạo được mã. Vui lòng thử lại.';
    case 'FORBIDDEN':
      return 'Bạn không có quyền thực hiện thao tác này.';
  }

  return 'Không thực hiện được: $error';
}
