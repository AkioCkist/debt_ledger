import 'package:flutter/material.dart';

import '../models/debt_transaction.dart';
import '../theme/app_theme.dart';

class StatusBadge extends StatelessWidget {
  final TxStatus status;

  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    late final Color fg;
    late final Color bg;
    late final String label;

    switch (status) {
      case TxStatus.waiting:
        fg = AppColors.waiting;
        bg = AppColors.waitingSoft;
        label = 'Chờ xác nhận';
        break;
      case TxStatus.accepted:
        fg = AppColors.accepted;
        bg = AppColors.acceptedSoft;
        label = 'Đã xác nhận';
        break;
      case TxStatus.declined:
        fg = AppColors.declined;
        bg = AppColors.declinedSoft;
        label = 'Đã từ chối';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
