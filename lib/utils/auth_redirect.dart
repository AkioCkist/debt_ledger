import 'package:flutter/foundation.dart';

/// Đích quay về sau khi người dùng bấm link xác nhận email.
///
/// Link trong mail do Supabase sinh: `.../auth/v1/verify?token=...&redirect_to=...`.
/// `redirect_to` phải nằm trong danh sách cho phép ở **Authentication > URL
/// Configuration** của project, nếu không Supabase thay bằng **Site URL**.
class AuthRedirect {
  const AuthRedirect._();

  /// Scheme riêng của app. Dùng chung với QR kết bạn (`sono://pair?code=...`)
  /// nên chỉ cần khai báo scheme một lần ở `AndroidManifest.xml` và `Info.plist`.
  static const String scheme = 'sono';

  /// Đích trên Android/iOS: mở thẳng app. `supabase_flutter` tự bắt deep link
  /// (`detectSessionInUri` mặc định bật) rồi đổi `?code=...` thành phiên.
  static const String mobileTarget = '$scheme://auth-confirm';

  /// Đích trên web: quay lại đúng origin đang chạy.
  ///
  /// Trả về origin trần, không kèm đường dẫn: Supabase tự gắn `?code=...` vào,
  /// và `supabase_flutter` đọc tham số đó từ `Uri.base` khi web khởi động.
  ///
  /// [baseUri] là `Uri.base`; trên web chính là URL của trang. Nếu không phải
  /// http/https (desktop chạy `file://`) thì rơi về [mobileTarget] — desktop
  /// không phải nền tảng được hỗ trợ. Phải kiểm tra scheme trước khi đọc
  /// `origin`: `Uri.origin` ném `StateError` với mọi scheme khác http/https.
  static String forPlatform({required bool isWeb, required Uri baseUri}) {
    if (!isWeb) return mobileTarget;
    final scheme = baseUri.scheme;
    if (scheme != 'http' && scheme != 'https') return mobileTarget;
    return baseUri.origin;
  }

  /// Đích theo nền tảng đang chạy thật.
  static String get current =>
      forPlatform(isWeb: kIsWeb, baseUri: Uri.base);
}
