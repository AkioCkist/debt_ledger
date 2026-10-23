import 'package:flutter/material.dart';

import '../models/app_profile.dart';
import '../models/debt_transaction.dart';
import '../services/ledger_math.dart';
import '../services/transaction_service.dart';
import '../theme/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../utils/thousands_input_formatter.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Thêm giao dịch')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Text(
                'Gửi cho ${widget.otherName}',
                style: const TextStyle(
                  fontSize: 13.5,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Chọn đúng ý nghĩa của giao dịch. Số dư chỉ đổi sau khi người kia xác nhận.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              _TypeSelector(
                value: _type,
                otherName: widget.otherName,
                onChanged: (v) => setState(() => _type = v),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [ThousandsInputFormatter()],
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
                decoration: const InputDecoration(
                  labelText: 'Số tiền (VND) *',
                  hintText: '0',
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
              const SizedBox(height: 14),
              TextFormField(
                controller: _descCtrl,
                maxLines: 3,
                maxLength: 140,
                decoration: InputDecoration(
                  labelText: 'Mô tả *',
                  hintText: _type == TxType.debt
                      ? 'Ví dụ: Ăn trưa ngày 12/9'
                      : 'Ví dụ: Chuyển khoản trả bớt nợ',
                  alignLabelWithHint: true,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Vui lòng nhập mô tả ngắn gọn';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              _BalancePreview(
                currentBalance: widget.currentBalance,
                actionAmount: (_amount ?? 0) > 0 ? _amount! : null,
                actionDescription: _actionDescription,
                otherName: widget.otherName,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      size: 18,
                      color: AppColors.accent,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _type == TxType.debt
                            ? '${widget.otherName} sẽ xác nhận rằng họ nợ bạn khoản này.'
                            : '${widget.otherName} sẽ xác nhận rằng bạn đã trả họ khoản này.',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textPrimary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (_submitError != null) ...[
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _submitError!,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.negative,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              ElevatedButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const Semantics(
                        label: 'Đang gửi yêu cầu',
                        child: SizedBox(
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
      ),
    );
  }
}

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
    return Row(
      children: [
        Expanded(
          child: _TypeOption(
            label: 'Ghi nợ',
            description: '$otherName nợ bạn',
            icon: Icons.arrow_outward_rounded,
            selected: value == TxType.debt,
            onTap: () => onChanged(TxType.debt),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _TypeOption(
            label: 'Trả nợ',
            description: 'Bạn đã trả $otherName',
            icon: Icons.check_circle_outline_rounded,
            selected: value == TxType.payment,
            onTap: () => onChanged(TxType.payment),
          ),
        ),
      ],
    );
  }
}

class _TypeOption extends StatelessWidget {
  final String label;
  final String description;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _TypeOption({
    required this.label,
    required this.description,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: '$label: $description',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          decoration: BoxDecoration(
            color: selected ? AppColors.accent : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.border,
            ),
          ),
          child: Column(
            children: [
              Icon(
                selected ? Icons.check_circle_rounded : icon,
                size: 20,
                color: selected ? Colors.white : AppColors.textSecondary,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.25,
                  color: selected
                      ? Colors.white.withValues(alpha: 0.85)
                      : AppColors.textSecondary,
                ),
              ),
            ],
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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
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
