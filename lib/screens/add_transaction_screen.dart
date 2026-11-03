import 'package:flutter/material.dart';

import '../models/app_profile.dart';
import '../models/debt_transaction.dart';
import '../services/ledger_math.dart';
import '../services/transaction_service.dart';
import '../theme/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../utils/thousands_input_formatter.dart';
import '../widgets/common.dart';

class AddTransactionScreen extends StatefulWidget {
  final AppProfile me;

  /// Người nhận. Chỉ cần id + tên hiển thị: tên có thể là tên riêng mình đặt
  /// cho họ ở sảnh, không nhất thiết là tên trong hồ sơ.
  final String otherId;
  final String otherName;

  /// Số dư đã xác nhận, nhìn từ phía [me]: dương là người kia nợ mình,
  /// âm là mình nợ người kia.
  final num currentBalance;

  const AddTransactionScreen({
    super.key,
    required this.me,
    required this.otherId,
    required this.otherName,
    required this.currentBalance,
  });

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _transactionService = TransactionService();

  TxType _type = TxType.debt;
  bool _submitting = false;
  String? _submitError;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  num? get _amount => CurrencyFormatter.parse(_amountCtrl.text);

  String get _actionDescription => _type == TxType.debt
      ? '${widget.otherName} nợ bạn khoản tiền này.'
      : 'Bạn đã trả ${widget.otherName} khoản tiền này.';

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final amount = CurrencyFormatter.parse(_amountCtrl.text);
    if (amount == null || amount <= 0) return;

    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      await _transactionService.createInvoice(
        createdBy: widget.me.id,
        recipientId: widget.otherId,
        type: _type,
        amount: amount,
        description: _descCtrl.text,
      );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Đã gửi yêu cầu tới ${widget.otherName}, đang chờ xác nhận.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _submitError =
              'Không gửi được yêu cầu. Hãy kiểm tra kết nối và thử lại.';
        });
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  static const _quickAmounts = [50000, 100000, 200000, 500000];

  /// Cộng dồn vào số đang nhập: bấm "+100K" hai lần là 200.000.
  void _addAmount(int value) {
    final next = (_amount ?? 0) + value;
    _amountCtrl.value = ThousandsInputFormatter().formatEditUpdate(
      TextEditingValue.empty,
      TextEditingValue(text: next.toString()),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Thêm giao dịch'),
            Text(
              'Gửi cho ${widget.otherName}',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w400,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomActionBar(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_submitError != null) ...[
              Semantics(
                liveRegion: true,
                child: Text(
                  _submitError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.negative,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            const Text(
              'Số dư chỉ đổi sau khi người kia xác nhận',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? Semantics(
                      label: 'Đang gửi yêu cầu',
                      child: const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      ),
                    )
                  : Text(
                      _type == TxType.debt
                          ? 'Gửi yêu cầu ghi nợ'
                          : 'Gửi yêu cầu trả nợ',
                    ),
            ),
          ],
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _TypeSelector(
              value: _type,
              otherName: widget.otherName,
              onChanged: (v) => setState(() => _type = v),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  const Text(
                    'Số tiền',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  TextFormField(
                    controller: _amountCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [ThousandsInputFormatter()],
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                    decoration: const InputDecoration(
                      hintText: '0',
                      suffixText: 'đ',
                      suffixStyle: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 6),
                      errorStyle: TextStyle(height: 1.2),
                    ),
                    onChanged: (_) => setState(() {}),
                    validator: (value) {
                      final parsed = CurrencyFormatter.parse(value ?? '');
                      if (parsed == null || parsed <= 0) {
                        return 'Nhập số tiền hợp lệ';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final value in _quickAmounts)
                        ActionChip(
                          label: Text('+${value ~/ 1000}K'),
                          onPressed: () => _addAmount(value),
                          backgroundColor: AppColors.background,
                          side: const BorderSide(color: AppColors.border),
                          shape: const StadiumBorder(),
                          labelStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descCtrl,
              maxLines: 2,
              minLines: 1,
              maxLength: 140,
              decoration: InputDecoration(
                labelText: 'Mô tả *',
                hintText: _type == TxType.debt
                    ? 'Ví dụ: Ăn trưa ngày 12/9'
                    : 'Ví dụ: Chuyển khoản trả bớt nợ',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Vui lòng nhập mô tả ngắn gọn';
                }
                return null;
              },
            ),
            const SizedBox(height: 8),
            _BalancePreview(
              currentBalance: widget.currentBalance,
              actionAmount: (_amount ?? 0) > 0 ? _amount! : null,
              actionDescription: _actionDescription,
              otherName: widget.otherName,
            ),
          ],
        ),
      ),
    );
  }
}

/// Hai lựa chọn viết thành câu, để khỏi phải nhớ "ghi nợ" là chiều nào.
class _TypeSelector extends StatelessWidget {
  final TxType value;
  final String otherName;
  final ValueChanged<TxType> onChanged;

  const _TypeSelector({
    required this.value,
    required this.otherName,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEAE8E2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: _TypeOption(
              label: '$otherName nợ tôi',
              semanticsLabel: 'Ghi nợ: $otherName nợ bạn',
              selected: value == TxType.debt,
              onTap: () => onChanged(TxType.debt),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _TypeOption(
              label: 'Tôi trả $otherName',
              semanticsLabel: 'Trả nợ: bạn đã trả $otherName',
              selected: value == TxType.payment,
              onTap: () => onChanged(TxType.payment),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeOption extends StatelessWidget {
  final String label;
  final String semanticsLabel;
  final bool selected;
  final VoidCallback onTap;

  const _TypeOption({
    required this.label,
    required this.semanticsLabel,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: semanticsLabel,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 46,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _BalancePreview extends StatelessWidget {
  final num currentBalance;
  final num? actionAmount;
  final String actionDescription;
  final String otherName;

  const _BalancePreview({
    required this.currentBalance,
    required this.actionAmount,
    required this.actionDescription,
    required this.otherName,
  });

  @override
  Widget build(BuildContext context) {
    final amount = actionAmount;
    final newBalance = amount == null
        ? null
        : LedgerMath.projectBalanceAfterCreatedTransaction(
            currentBalance: currentBalance,
            amount: amount,
          );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: amount == null ? AppColors.muted : AppColors.acceptedSoft,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Số nợ sau khi được xác nhận',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            actionDescription,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.textSecondary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          if (amount == null)
            const Text(
              'Nhập số tiền để xem phép tính nợ mới của cả hai người.',
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
                height: 1.35,
              ),
            )
          else ...[
            _BalanceEquation(
              subjectName: 'Bạn',
              counterpartName: otherName,
              original: currentBalance,
              action: amount,
              result: newBalance!,
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(),
            ),
            _BalanceEquation(
              subjectName: otherName,
              counterpartName: 'bạn',
              original: -currentBalance,
              action: -amount,
              result: -newBalance,
            ),
            const SizedBox(height: 12),
            const Text(
              '+ là được người kia nợ · − là đang nợ người kia',
              style: TextStyle(
                fontSize: 11.5,
                color: AppColors.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BalanceEquation extends StatelessWidget {
  final String subjectName;
  final String counterpartName;
  final num original;
  final num action;
  final num result;

  const _BalanceEquation({
    required this.subjectName,
    required this.counterpartName,
    required this.original,
    required this.action,
    required this.result,
  });

  @override
  Widget build(BuildContext context) {
    final actionOperator = action >= 0 ? '+' : '−';
    final resultDescription = result == 0
        ? '$subjectName và $counterpartName không còn nợ nhau'
        : result > 0
            ? '$counterpartName nợ $subjectName ${CurrencyFormatter.format(result)}'
            : '$subjectName nợ $counterpartName ${CurrencyFormatter.format(result.abs())}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          subjectName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          '${_signed(original)} $actionOperator ${CurrencyFormatter.format(action.abs())} = ${_signed(result)}',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 3),
        Text(
          resultDescription,
          style: const TextStyle(
            fontSize: 12.5,
            color: AppColors.textSecondary,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  static String _signed(num value) {
    final sign = value >= 0 ? '+' : '−';
    return '$sign${CurrencyFormatter.format(value.abs())}';
  }
}
