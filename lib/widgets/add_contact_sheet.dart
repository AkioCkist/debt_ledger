import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/pair_code.dart';
import '../screens/scan_qr_screen.dart';
import '../services/connection_service.dart';
import '../theme/app_theme.dart';
import '../utils/pairing_code.dart';
import '../utils/pairing_error.dart';

Future<void> showAddContactSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const AddContactSheet(),
  );
}

/// Popup "Thêm bạn nợ": mã + QR của mình ở trên, ô nhập mã của người kia ở dưới.
class AddContactSheet extends StatefulWidget {
  const AddContactSheet({super.key});

  @override
  State<AddContactSheet> createState() => _AddContactSheetState();
}

class _AddContactSheetState extends State<AddContactSheet> {
  final _connectionService = ConnectionService();
  final _codeCtrl = TextEditingController();

  PairCode? _pairCode;
  bool _creating = false;
  bool _redeeming = false;
  String? _codeError;
  String? _redeemError;
  Timer? _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _createCode();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _createCode() async {
    setState(() {
      _creating = true;
      _codeError = null;
    });
    try {
      final code = await _connectionService.createPairCode();
      if (!mounted) return;
      setState(() {
        _pairCode = code;
        _now = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _codeError = pairingErrorMessage(e));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _redeem([String? scanned]) async {
    final code = PairingCode.normalize(scanned ?? _codeCtrl.text);
    if (code == null) {
      setState(() {
        _redeemError = 'Mã gồm ${PairingCode.length} ký tự, chỉ dùng chữ và số.';
      });
      return;
    }

    setState(() {
      _redeeming = true;
      _redeemError = null;
    });
    try {
      await _connectionService.redeemPairCode(code);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã gửi lời mời. Chờ người kia đồng ý nhé.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _redeemError = pairingErrorMessage(e));
    } finally {
      if (mounted) setState(() => _redeeming = false);
    }
  }

  Future<void> _scan() async {
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ScanQrScreen()),
    );
    if (!mounted || scanned == null) return;
    _codeCtrl.text = PairingCode.formatForDisplay(scanned);
    await _redeem(scanned);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Thêm bạn nợ',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Đưa mã này cho người kia, hoặc nhập mã của họ ở dưới. '
              'Mã chỉ dùng được một lần.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 18),
            _buildMyCode(),
            const SizedBox(height: 24),
            const Divider(height: 1),
            const SizedBox(height: 18),
            _buildRedeem(),
          ],
        ),
      ),
    );
  }

  Widget _buildMyCode() {
    final pairCode = _pairCode;
    final expired = pairCode == null || pairCode.isExpiredAt(_now);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Text(
            'Mã của bạn',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          if (_codeError != null)
            Text(
              _codeError!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.negative, fontSize: 13),
            )
          else if (_creating && pairCode == null)
            const SizedBox(
              height: 180,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (expired)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Text(
                'Mã đã hết hạn.',
                style: TextStyle(color: AppColors.textFaint, fontSize: 14),
              ),
            )
          else ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: PairingCode.toQrPayload(pairCode.code),
                size: 170,
                padding: EdgeInsets.zero,
              ),
            ),
            const SizedBox(height: 14),
            SelectableText(
              PairingCode.formatForDisplay(pairCode.code),
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                letterSpacing: 3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Còn ${_formatRemaining(pairCode.remainingAt(_now))}',
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textFaint,
              ),
            ),
          ],
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: _creating ? null : _createCode,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(expired ? 'Tạo mã mới' : 'Tạo mã khác'),
          ),
        ],
      ),
    );
  }

  Widget _buildRedeem() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Nhập mã của người kia',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _codeCtrl,
          textCapitalization: TextCapitalization.characters,
          maxLength: PairingCode.length + 1,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: 3,
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9 ]')),
          ],
          decoration: const InputDecoration(
            hintText: 'ABCD 2345',
            counterText: '',
          ),
          onSubmitted: (_) => _redeem(),
        ),
        if (_redeemError != null) ...[
          const SizedBox(height: 10),
          Text(
            _redeemError!,
            style: const TextStyle(color: AppColors.negative, fontSize: 13),
          ),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: _redeeming ? null : () => _redeem(),
                child: _redeeming
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Kết nối'),
              ),
            ),
            if (ScanQrScreen.isSupported) ...[
              const SizedBox(width: 10),
              SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: _redeeming ? null : _scan,
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                  label: const Text('Quét QR'),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  String _formatRemaining(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
