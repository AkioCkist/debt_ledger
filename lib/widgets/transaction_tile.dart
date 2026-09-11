import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/debt_transaction.dart';
import '../theme/app_theme.dart';
import '../utils/currency_formatter.dart';
import 'status_badge.dart';

class TransactionTile extends StatelessWidget {
  final DebtTransaction tx;
  final String myId;
  final String otherName;
  final VoidCallback? onTap;

  const TransactionTile({
    super.key,
    required this.tx,
    required this.myId,
    required this.otherName,
    this.onTap,
  });

  bool get _iCreated => tx.createdBy == myId;

  String get _label {
    final actor = _iCreated ? 'Bạn' : otherName;
    final target = _iCreated ? otherName : 'bạn';
    if (tx.type == TxType.debt) {
      return '$actor ghi nợ cho $target';
    }
    return '$actor trả nợ cho $target';
  }

  IconData get _icon {
    if (tx.type == TxType.debt) {
      return _iCreated ? Icons.arrow_outward_rounded : Icons.arrow_downward_rounded;
    }
    return _iCreated ? Icons.check_circle_outline_rounded : Icons.undo_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('d MMM, HH:mm', 'vi_VN').format(tx.createdAt);

    Color amountColor = AppColors.textFaint;
    if (tx.isAccepted) {
      amountColor = _iCreated ? AppColors.positive : AppColors.negative;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.accentSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_icon, size: 20, color: AppColors.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tx.description.isNotEmpty ? tx.description : _label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$_label \u00b7 $dateLabel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  CurrencyFormatter.formatSigned(tx.amount, positive: _iCreated),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: amountColor,
                  ),
                ),
                const SizedBox(height: 6),
                StatusBadge(status: tx.status),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
