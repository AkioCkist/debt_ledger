import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/currency_formatter.dart';

class BalanceCard extends StatelessWidget {
  /// balance > 0: người kia đang nợ mình
  /// balance < 0: mình đang nợ người kia
  /// balance == 0: đã cân bằng
  final num balance;
  final String otherName;

  const BalanceCard({
    super.key,
    required this.balance,
    required this.otherName,
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
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            headline,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            CurrencyFormatter.format(balance.abs()),
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: amountColor,
            ),
          ),
        ],
      ),
    );
  }
}
