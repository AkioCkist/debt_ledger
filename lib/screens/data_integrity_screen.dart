import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/integrity_report.dart';
import '../models/sync_checkpoint.dart';
import '../services/integrity_service.dart';
import '../theme/app_theme.dart';
import '../utils/currency_formatter.dart';

/// Màn hình đối soát: so khớp dữ liệu đang thấy với mốc đã chốt và với
/// kết quả server tự tính, để phát hiện ai đó sửa database ngoài luồng.
class DataIntegrityScreen extends StatefulWidget {
  final String myId;

  const DataIntegrityScreen({super.key, required this.myId});

  @override
  State<DataIntegrityScreen> createState() => _DataIntegrityScreenState();
}

enum _CheckState { pass, warn, fail, skipped }

class _DataIntegrityScreenState extends State<DataIntegrityScreen> {
  final _integrityService = IntegrityService();
  final _dateFormat = DateFormat('HH:mm:ss d/M/yyyy', 'vi_VN');

  IntegrityCheckResult? _result;
  SyncCheckpoint? _baseline;
  bool _loading = true;
  bool _resetting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final baseline = await _integrityService.loadCheckpoint(widget.myId);
      final result = await _integrityService.verifyNow(myId: widget.myId);
      if (!mounted) return;
      setState(() {
        _baseline = baseline;
        _result = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Không đối soát được: $e';
        _loading = false;
      });
    }
  }

  /// Chốt lại mốc theo dữ liệu hiện tại, sau khi người dùng đã xem bất thường.
  Future<void> _acceptCurrentState() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Đặt lại mốc đối soát?'),
        content: const Text(
          'Mốc mới sẽ lấy đúng dữ liệu đang thấy làm chuẩn. Các bất thường '
          'hiện tại sẽ không còn được cảnh báo nữa.\n\n'
          'Chỉ làm việc này khi bạn đã kiểm tra và chấp nhận dữ liệu hiện tại.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Huỷ'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Đặt lại mốc'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _resetting = true);
    try {
      final rows = await _integrityService.verifyNow(
        myId: widget.myId,
        forceAccept: true,
      );
      final baseline = await _integrityService.loadCheckpoint(widget.myId);
      if (!mounted) return;
      setState(() {
        _result = rows;
        _baseline = baseline;
        _resetting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã đặt lại mốc đối soát.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _resetting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không đặt lại được mốc: $e')),
      );
    }
  }

  /// Trạng thái của một phép so khớp, suy ra từ các phát hiện thực tế.
  _CheckState _stateFor(IntegrityReport report, Set<String> codes) {
    final related =
        report.findings.where((f) => codes.contains(f.code)).toList();
    if (related.any((f) => f.severity == IntegritySeverity.critical)) {
      return _CheckState.fail;
    }
    if (related.any((f) => f.severity == IntegritySeverity.warning)) {
      return _CheckState.warn;
    }
    if (codes.contains('balance_mismatch_server') &&
        report.serverBalance == null) {
      return _CheckState.skipped;
    }
    return _CheckState.pass;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Đối soát dữ liệu'),
        actions: [
          IconButton(
            tooltip: 'Kiểm tra lại',
            onPressed: _loading ? null : _run,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: _loading && _result == null
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _run,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    if (_error != null) _ErrorBox(message: _error!),
                    if (_result != null) ...[
                      _SummaryCard(
                        report: _result!.report,
                        baseline: _baseline,
                        dateFormat: _dateFormat,
                      ),
                      const SizedBox(height: 20),
                      const _SectionHeader(title: 'Các phép so khớp'),
                      const SizedBox(height: 8),
                      ..._buildChecks(_result!.report),
                      const SizedBox(height: 20),
                      const _SectionHeader(title: 'Chi tiết phát hiện'),
                      const SizedBox(height: 8),
                      ..._buildFindings(_result!.report),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: _resetting ? null : _acceptCurrentState,
                        icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                        label: const Text('Đặt lại mốc đối soát'),
                      ),
                      const SizedBox(height: 12),
                      const _ProtectionNote(),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  List<Widget> _buildChecks(IntegrityReport report) {
    final checks = <({String label, String description, Set<String> codes})>[
      (
        label: 'Số dư tính lại khớp server',
        description: 'Client và server tính độc lập trên cùng dữ liệu.',
        codes: {
          'balance_mismatch_server',
          'local_balance_drift',
        },
      ),
      (
        label: 'Số dòng khớp server',
        description: 'Không có giao dịch nào bị thiếu khi đọc về.',
        codes: {'server_row_count_mismatch'},
      ),
      (
        label: 'Số tiền / nội dung không bị sửa',
        description: 'Vân tay từng giao dịch trùng với mốc đối soát.',
        codes: {
          'row_payload_changed',
          'row_deleted_out_of_band',
          'row_version_rollback',
          'server_ledger_drift',
        },
      ),
      (
        label: 'Trạng thái chuyển hợp lệ',
        description: 'Chỉ waiting -> accepted/declined, và chỉ một lần.',
        codes: {
          'illegal_status_transition',
          'state_changed_without_version_bump',
          'unknown_status',
          'accepted_without_responded_at',
          'waiting_with_responded_at',
        },
      ),
      (
        label: 'Ràng buộc dữ liệu',
        description: 'Số tiền dương, không tự ghi nợ chính mình.',
        codes: {
          'invalid_amount',
          'non_positive_amount',
          'self_dealing',
          'unknown_type',
          'duplicate_row',
          'row_without_id',
        },
      ),
      (
        label: 'Theo dõi thay đổi bằng version/updated_at',
        description: 'Database đã bật cột version và updated_at.',
        codes: {'version_column_missing'},
      ),
    ];

    return checks.map((check) {
      final state = _stateFor(report, check.codes);
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _CheckTile(
          label: check.label,
          description: check.description,
          state: state,
        ),
      );
    }).toList();
  }

  List<Widget> _buildFindings(IntegrityReport report) {
    if (report.findings.isEmpty) {
      return [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.acceptedSoft,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Text(
            'Không có phát hiện nào. Dữ liệu đang khớp với mốc đối soát.',
            style: TextStyle(
              fontSize: 13.5,
              color: AppColors.accepted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ];
    }

    return report.findings
        .map(
          (finding) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _FindingTile(finding: finding),
          ),
        )
        .toList();
  }
}

class _SummaryCard extends StatelessWidget {
  final IntegrityReport report;
  final SyncCheckpoint? baseline;
  final DateFormat dateFormat;

  const _SummaryCard({
    required this.report,
    required this.baseline,
    required this.dateFormat,
  });

  @override
  Widget build(BuildContext context) {
    final Color color = report.criticalCount > 0
        ? AppColors.negative
        : (report.warningCount > 0 ? AppColors.waiting : AppColors.positive);
    final String headline = report.criticalCount > 0
        ? 'Phát hiện dấu hiệu sửa dữ liệu ngoài luồng'
        : (report.warningCount > 0
            ? 'Có điểm cần lưu ý, số dư vẫn khớp'
            : 'Dữ liệu khớp với mốc đối soát');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
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
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 14),
          _KeyValue(
            label: 'Số dư',
            value: CurrencyFormatter.format(report.clientBalance.abs()),
          ),
          _KeyValue(
            label: 'Server tính',
            value: report.serverBalance == null
                ? 'không gọi được'
                : CurrencyFormatter.format(report.serverBalance!.abs()),
          ),
          _KeyValue(label: 'Số giao dịch', value: '${report.rowCount}'),
          _KeyValue(
            label: 'Thay đổi hợp lệ',
            value: '${report.changedSinceBaseline} kể từ mốc',
          ),
          _KeyValue(
            label: 'Mốc đối soát',
            value: baseline == null
                ? 'vừa tạo lần này'
                : dateFormat.format(baseline!.syncedAt),
          ),
          _KeyValue(label: 'Kiểm tra lúc', value: dateFormat.format(report.checkedAt)),
          if (!report.databaseTracksVersions)
            const _KeyValue(
              label: 'Version',
              value: 'chưa bật (cần chạy migration)',
            ),
          if (report.note != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                report.note!,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textFaint,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _KeyValue extends StatelessWidget {
  final String label;
  final String value;

  const _KeyValue({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13.5,
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

class _CheckTile extends StatelessWidget {
  final String label;
  final String description;
  final _CheckState state;

  const _CheckTile({
    required this.label,
    required this.description,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    late final IconData icon;
    late final Color color;
    late final String suffix;

    switch (state) {
      case _CheckState.pass:
        icon = Icons.check_circle_rounded;
        color = AppColors.positive;
        suffix = 'Khớp';
        break;
      case _CheckState.warn:
        icon = Icons.error_outline_rounded;
        color = AppColors.waiting;
        suffix = 'Cần xem';
        break;
      case _CheckState.fail:
        icon = Icons.cancel_rounded;
        color = AppColors.negative;
        suffix = 'Không khớp';
        break;
      case _CheckState.skipped:
        icon = Icons.remove_circle_outline_rounded;
        color = AppColors.textFaint;
        suffix = 'Bỏ qua';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            suffix,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _FindingTile extends StatelessWidget {
  final IntegrityFinding finding;

  const _FindingTile({required this.finding});

  @override
  Widget build(BuildContext context) {
    late final Color color;
    late final Color soft;
    late final IconData icon;

    switch (finding.severity) {
      case IntegritySeverity.critical:
        color = AppColors.negative;
        soft = AppColors.declinedSoft;
        icon = Icons.report_gmailerrorred_rounded;
        break;
      case IntegritySeverity.warning:
        color = AppColors.waiting;
        soft = AppColors.waitingSoft;
        icon = Icons.warning_amber_rounded;
        break;
      case IntegritySeverity.info:
        color = AppColors.textSecondary;
        soft = AppColors.accentSoft;
        icon = Icons.info_outline_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: soft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  finding.title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  finding.message,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textPrimary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  finding.transactionId == null
                      ? finding.code
                      : '${finding.code} · ${finding.transactionId}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textFaint,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProtectionNote extends StatelessWidget {
  const _ProtectionNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Dữ liệu tiền nợ được bảo vệ thế nào',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '• Database khoá cứng số tiền, loại giao dịch, người tạo/người nhận '
            'và mô tả: không sửa được sau khi tạo, kể cả bằng SQL trực tiếp.\n'
            '• Tài khoản đăng nhập chỉ có quyền đổi đúng cột trạng thái, và chỉ '
            'một lần waiting -> accepted/declined.\n'
            '• Mỗi lần đổi, database tự tăng version và cập nhật updated_at.\n'
            '• App chỉ giữ mốc đối soát (vân tay dữ liệu) trên máy, không lưu '
            'khoá bí mật nào.',
            style: TextStyle(
              fontSize: 12.5,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 15.5,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;

  const _ErrorBox({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.declinedSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        message,
        style: const TextStyle(fontSize: 13, color: AppColors.negative),
      ),
    );
  }
}
