import 'package:debt_ledger/utils/auth_redirect.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthRedirect.forPlatform', () {
    test('web trả về đúng origin đang chạy', () {
      expect(
        AuthRedirect.forPlatform(
          isWeb: true,
          baseUri: Uri.parse('http://localhost:3000/#/login'),
        ),
        'http://localhost:3000',
      );
      expect(
        AuthRedirect.forPlatform(
          isWeb: true,
          baseUri: Uri.parse('https://so-no.example/app?x=1'),
        ),
        'https://so-no.example',
      );
    });

    test('mobile trả về scheme riêng của app', () {
      // Uri.base trên mobile là file:// của bundle nên phải bỏ qua nó.
      expect(
        AuthRedirect.forPlatform(
          isWeb: false,
          baseUri: Uri.parse('file:///data/app/base.apk'),
        ),
        'sono://auth-confirm',
      );
    });

    test('origin rỗng (desktop chạy file://) rơi về đích mobile', () {
      expect(
        AuthRedirect.forPlatform(
          isWeb: true,
          baseUri: Uri.parse('file:///C:/build/web/index.html'),
        ),
        'sono://auth-confirm',
      );
    });

    test('scheme khớp với QR kết bạn và đích không kèm query', () {
      expect(AuthRedirect.scheme, 'sono');
      expect(AuthRedirect.mobileTarget, 'sono://auth-confirm');
      // Đích phải sạch: Supabase tự gắn ?code=... vào, thêm sẵn sẽ hỏng.
      expect(AuthRedirect.mobileTarget.contains('?'), isFalse);
      expect(Uri.parse(AuthRedirect.mobileTarget).scheme, AuthRedirect.scheme);
    });
  });
}
