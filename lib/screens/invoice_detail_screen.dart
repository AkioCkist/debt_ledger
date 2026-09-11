import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/debt_transaction.dart';
import '../services/transaction_service.dart';
import '../theme/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../widgets/status_badge.dart';

class InvoiceDetailScreen extends StatefulWidget {
  final DebtTransaction tx;
  final String myId;
  final String otherName;

  const InvoiceDetailScreen({
    super.key,
    required this.tx,
    required this.myId,
    required this.otherName,
  });

  @override
  State<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends State<InvoiceDetailScreen> {
  final _transactionService = TransactionService();
  bool _responding = false;
  late TxStatus _status;

  @override
  void initState() {
    super.initState();
    _status = widget.tx.status;
  }

  bool get _iAmRecipient => widget.tx.recipientId == widget.myId;
  bool get _iCreated => widget.tx.createdBy == widget.myId;

  Future<void> _respond(TxStatus newStatus) async {
    setState(() => _responding = true);
    try {
      await _transactionService.respond(
        transactionId: widget.tx.id,
        status: newStatus,
      );
      if (mounted) {
        setState(() => _status = newStatus);
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thực hiện được: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _responding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tx = widget.tx;
    final dateFormat = DateFormat('d MMMM yyyy, HH:mm', 'vi_VN');

    final typeLabel = tx.type == TxType.debt ? 'Ghi nợ' : 'Trả nợ';
    final actorName = _iCreated ? 'Bạn' : widget.otherName;
    final targetName = _iCreated ? widget.otherName : 'bạn';

    return Scaffold(
      appBar: AppBar(title: const Text('Chi tiết giao dịch')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: Column(
                children: [
                  Text(
                    CurrencyFormatter.format(tx.amount),
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  StatusBadge(status: _status),
                ],
              ),
            ),
            const SizedBox(height: 28),
            _DetailRow(label: 'Loại giao dịch', value: typeLabel),
            _DetailRow(
              label: 'Nội dung',
              value: tx.description.isNotEmpty ? tx.description : '(không có)',
            ),
            _DetailRow(label: 'Người tạo', value: '$actorName ghi cho $targetName'),
            _DetailRow(label: 'Thời gian tạo', value: dateFormat.format(tx.createdAt)),
            if (tx.respondedAt != null)
              _DetailRow(
                label: 'Thời gian phản hồi',
                value: dateFormat.format(tx.respondedAt!),
              ),
            const SizedBox(height: 12),

            if (_status == TxStatus.waiting && _iAmRecipient) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _responding
                          ? null
                          : () => _respond(TxStatus.declined),
                      child: const Text('Từ chối'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _responding
                          ? null
                          : () => _respond(TxStatus.accepted),
                      child: _responding
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Xác nhận'),
                    ),
                  ),
                ],
              ),
            ] else if (_status == TxStatus.waiting && !_iAmRecipient) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.waitingSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Đang chờ ${widget.otherName} xác nhận yêu cầu này.',
                  style: const TextStyle(
                    color: AppColors.waiting,
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
