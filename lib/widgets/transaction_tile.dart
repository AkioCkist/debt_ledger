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

  /// Đặt trong một [GroupedCard]: bỏ viền và bo góc riêng của từng dòng.
  final bool grouped;

  const TransactionTile({
    super.key,
    required this.tx,
    required this.myId,
    required this.otherName,
    this.onTap,
    this.grouped = false,
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

    final ({Color bg, Color fg}) iconColors = switch (tx.status) {
      TxStatus.waiting => (bg: AppColors.waitingSoft, fg: AppColors.waiting),
      TxStatus.declined => (bg: AppColors.declinedSoft, fg: AppColors.declined),
      TxStatus.accepted => (bg: AppColors.accentSoft, fg: AppColors.accent),
    };
    final strike = tx.isDeclined ? TextDecoration.lineThrough : null;

    final content = Padding(
      padding: EdgeInsets.all(grouped ? 14 : 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: iconColors.bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              tx.isDeclined ? Icons.close_rounded : _icon,
              size: 19,
              color: iconColors.fg,
            ),
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
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: tx.isDeclined
                        ? AppColors.textSecondary
                        : AppColors.textPrimary,
                    decoration: strike,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$_label · $dateLabel',
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
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: amountColor,
                  decoration: strike,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 6),
              StatusBadge(status: tx.status),
            ],
          ),
        ],
      ),
    );

    if (grouped) {
      return InkWell(onTap: onTap, child: content);
    }

    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}
