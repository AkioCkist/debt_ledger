import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/integrity_report.dart';
import '../theme/app_theme.dart';

/// Mục "Đối soát dữ liệu" trên màn hình chính.
///
/// Tóm tắt kết quả so khớp giữa dữ liệu đang thấy và mốc đã chốt lần trước,
/// để biết ngay có ai đó sửa database ngoài app hay không.
class IntegrityCard extends StatelessWidget {
  final IntegrityReport? report;
  final bool checking;
  final VoidCallback onTap;

  const IntegrityCard({
    super.key,
    required this.report,
    required this.checking,
    required this.onTap,
  });

  ({IconData icon, Color color, String headline, String detail}) _summary() {
    final report = this.report;
    if (report == null || checking) {
      return (
        icon: Icons.shield_outlined,
        color: AppColors.textSecondary,
        headline: 'Đang kiểm tra dữ liệu…',
        detail: 'Đang so khớp với mốc đối soát gần nhất.',
      );
    }

    final checkedAt = DateFormat('HH:mm d/M').format(report.checkedAt);
    if (report.criticalCount > 0) {
      return (
        icon: Icons.gpp_maybe_rounded,
        color: AppColors.negative,
        headline: '${report.criticalCount} bất thường nghiêm trọng',
        detail: 'Dữ liệu có dấu hiệu bị sửa ngoài app. Chạm để xem chi tiết.',
      );
    }
    if (report.warningCount > 0) {
      return (
        icon: Icons.gpp_maybe_outlined,
        color: AppColors.waiting,
        headline: '${report.warningCount} điểm cần lưu ý',
        detail: 'Không ảnh hưởng số dư. Kiểm tra lúc $checkedAt.',
      );
    }
    return (
      icon: Icons.verified_user_rounded,
      color: AppColors.positive,
      headline: 'Dữ liệu khớp',
      detail: report.hasBaseline
          ? 'Không phát hiện thay đổi ngoài luồng · $checkedAt'
          : 'Đã ghi mốc đối soát đầu tiên · $checkedAt',
    );
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary();

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
              child: checking
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : Icon(summary.icon, size: 20, color: summary.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Đối soát dữ liệu',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    summary.headline,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: summary.color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    summary.detail,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textFaint,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
