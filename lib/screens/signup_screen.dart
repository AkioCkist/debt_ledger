import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/auth_redirect.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _authService = AuthService();

  bool _loading = false;
  bool _obscure = true;
  String? _error;

  /// Email đã đăng ký xong, đang chờ xác nhận.
  String? _pendingEmail;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  /// Tên hiển thị hiện cho người khác thấy khi pair, nên cắt khoảng trắng,
  /// giới hạn độ dài và bỏ ký tự điều khiển.
  String _cleanName(String raw) {
    return raw
        .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '')
        .trim();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    final email = _emailCtrl.text.trim();
    try {
      final response = await _authService.signUp(
        email: email,
        password: _passwordCtrl.text,
        displayName: _cleanName(_nameCtrl.text),
        emailRedirectTo: AuthRedirect.current,
      );

      if (!mounted) return;
      if (response.session != null) {
        // Project chưa bật xác nhận email: đã có phiên, AuthGate tự mở sảnh.
        Navigator.of(context).pop();
        return;
      }
      setState(() => _pendingEmail = email);
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Đã có lỗi xảy ra. Vui lòng thử lại.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tạo tài khoản')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
            child: _pendingEmail != null
                ? _buildPendingConfirmation(_pendingEmail!)
                : _buildForm(),
          ),
        ),
      ),
    );
  }

  Widget _buildPendingConfirmation(String email) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.accentSoft,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.mark_email_unread_outlined,
            color: AppColors.accent,
            size: 26,
          ),
        ),
        const SizedBox(height: 22),
        const Text(
          'Kiểm tra email',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          'Đã gửi link xác nhận tới $email.\n\n'
          'Bấm link trong mail rồi quay lại app và đăng nhập. '
          'Nếu chưa thấy mail, hãy xem cả thư mục spam.',
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.textSecondary,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Về trang đăng nhập'),
          ),
        ),
      ],
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tạo tài khoản',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Sau khi tạo, bạn vào sảnh để kết nối với bạn nợ.',
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 26),
          TextFormField(
            controller: _nameCtrl,
            textInputAction: TextInputAction.next,
            maxLength: 60,
            decoration: const InputDecoration(
              labelText: 'Tên hiển thị',
              hintText: 'Ví dụ: Nam',
              counterText: '',
            ),
            validator: (value) {
              final name = _cleanName(value ?? '');
              if (name.isEmpty) return 'Vui lòng nhập tên hiển thị';
              if (name.length > 60) return 'Tên tối đa 60 ký tự';
              return null;
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Email',
              hintText: 'ban@example.com',
            ),
            validator: (value) {
              final email = (value ?? '').trim();
              if (email.isEmpty) return 'Vui lòng nhập email';
              if (!email.contains('@') || !email.contains('.')) {
                return 'Email không hợp lệ';
              }
              return null;
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _passwordCtrl,
            obscureText: _obscure,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Mật khẩu',
              helperText: 'Ít nhất 6 ký tự',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: AppColors.textFaint,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Vui lòng nhập mật khẩu';
              }
              if (value.length < 6) return 'Mật khẩu ít nhất 6 ký tự';
              return null;
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _confirmCtrl,
            obscureText: _obscure,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submit(),
            decoration: const InputDecoration(labelText: 'Nhập lại mật khẩu'),
            validator: (value) {
              if (value != _passwordCtrl.text) {
                return 'Mật khẩu nhập lại không khớp';
              }
              return null;
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(
              _error!,
              style: const TextStyle(
                color: AppColors.negative,
                fontSize: 13.5,
              ),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Tạo tài khoản'),
            ),
          ),
        ],
      ),
    );
  }
}
