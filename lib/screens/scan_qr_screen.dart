import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme/app_theme.dart';
import '../utils/pairing_code.dart';

/// Quét QR kết bạn. Pop về mã pairing (String) khi đọc được, null nếu huỷ.
class ScanQrScreen extends StatefulWidget {
  const ScanQrScreen({super.key});

  /// Camera không có trên desktop/web nên chỉ mở màn này khi hỗ trợ.
  static bool get isSupported {
    return !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
  }

  @override
  State<ScanQrScreen> createState() => _ScanQrScreenState();
}

class _ScanQrScreenState extends State<ScanQrScreen> {
  final _controller = MobileScannerController();

  /// Máy quét bắn liên tục; chỉ xử lý lần đọc được mã hợp lệ đầu tiên.
  bool _handled = false;
  String? _hint;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;

    for (final barcode in capture.barcodes) {
      final code = PairingCode.fromQrPayload(barcode.rawValue);
      if (code == null) continue;

      _handled = true;
      Navigator.of(context).pop(code);
      return;
    }

    if (mounted && _hint == null) {
      setState(() => _hint = 'QR này không phải mã kết bạn của Sổ Nợ.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quét mã QR')),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _CameraError(message: error.errorCode.name),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                _hint ??
                    'Đưa QR trong mục "Thêm bạn nợ" của người kia vào giữa khung hình.',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  final String message;

  const _CameraError({required this.message});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.no_photography_outlined,
                size: 40,
                color: AppColors.textFaint,
              ),
              const SizedBox(height: 14),
              const Text(
                'Không mở được camera',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Hãy kiểm tra quyền camera của app, hoặc quay lại và nhập '
                'mã bằng tay.\n($message)',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
