import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/currency_formatter.dart';

class BalanceCard extends StatelessWidget {
  /// balance > 0: người kia đang nợ mình
  /// balance < 0: mình đang nợ người kia
  /// balance == 0: đã cân bằng
  final num balance;
  final String otherName;

  /// Số giao dịch đã xác nhận, hiện dưới số dư. Null thì không hiện.
  final int? transactionCount;

  const BalanceCard({
    super.key,
    required this.balance,
    required this.otherName,
    this.transactionCount,
  });

  @override
  Widget build(BuildContext context) {
    final isSettled = balance == 0;
    final isPositive = balance > 0;

    final Color amountColor = isSettled
        ? AppColors.textPrimary
        : (isPositive ? AppColors.positive : AppColors.negative);

    final String headline = isSettled
        ? 'Đã cân bằng'
        : (isPositive ? '$otherName đang nợ bạn' : 'Bạn đang nợ $otherName');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Text(
            headline,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              CurrencyFormatter.format(balance.abs()),
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.8,
                color: amountColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (transactionCount != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.muted,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$transactionCount giao dịch đã xác nhận',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
