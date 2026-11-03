import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/app_profile.dart';
import '../models/connection.dart';
import '../models/debt_transaction.dart';
import '../services/ledger_math.dart';
import '../services/transaction_service.dart';
import '../theme/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../widgets/balance_card.dart';
import '../widgets/common.dart';
import '../widgets/transaction_tile.dart';
import 'add_transaction_screen.dart';
import 'data_integrity_screen.dart';
import 'history_screen.dart';
import 'invoice_detail_screen.dart';

/// Sổ nợ của MỘT bạn nợ.
///
/// Dữ liệu vẫn stream toàn bộ giao dịch mình được thấy (RLS lọc), nhưng mọi
/// phép tính và danh sách ở đây chỉ dùng giao dịch giữa mình và người này.
class ContactLedgerScreen extends StatefulWidget {
  final AppProfile me;
  final ContactEntry contact;

  const ContactLedgerScreen({
    super.key,
    required this.me,
    required this.contact,
  });

  @override
  State<ContactLedgerScreen> createState() => _ContactLedgerScreenState();
}

class _ContactLedgerScreenState extends State<ContactLedgerScreen> {
  final _transactionService = TransactionService();

  StreamSubscription<List<Map<String, dynamic>>>? _subscription;
  List<DebtTransaction> _transactions = const [];
  bool _loading = true;
  String? _error;
  final Set<String> _respondingIds = {};

  String get _myId => widget.me.id;
  String get _otherId => widget.contact.profile.id;
  String get _otherName => widget.contact.displayName;

  @override
  void initState() {
    super.initState();
    _subscription = _transactionService.streamMyTransactionRows().listen(
      (rows) {
        if (!mounted) return;
        setState(() {
          _transactions = rows
              .where((row) => LedgerMath.rawBetween(row, _myId, _otherId))
              .map(DebtTransaction.fromMap)
              .toList();
          _loading = false;
          _error = null;
        });
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'Không tải được dữ liệu: $error';
        });
      },
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final rows = await _transactionService.fetchTransactionRows();
      if (!mounted) return;
      setState(() {
        _transactions = rows
            .where((row) => LedgerMath.rawBetween(row, _myId, _otherId))
            .map(DebtTransaction.fromMap)
            .toList();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không làm mới được: $e')),
      );
    }
  }

  Future<void> _openIntegrityScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DataIntegrityScreen(myId: _myId),
      ),
    );
  }

  Future<void> _openAddTransactionScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddTransactionScreen(
          me: widget.me,
          otherId: _otherId,
          otherName: _otherName,
          currentBalance: LedgerMath.computeBalance(_transactions, _myId),
        ),
      ),
    );
  }

  Future<void> _respond(DebtTransaction tx, TxStatus status) async {
    setState(() => _respondingIds.add(tx.id));
    try {
      await _transactionService.respond(transactionId: tx.id, status: status);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không thực hiện được: $e')),
      );
    } finally {
      if (mounted) setState(() => _respondingIds.remove(tx.id));
    }
  }

  void _openDetail(DebtTransaction tx) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InvoiceDetailScreen(
          tx: tx,
          myId: _myId,
          otherName: _otherName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ready = !_loading && _error == null;
    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            InitialAvatar(
              initial: widget.contact.profile.initial,
              seed: _otherId,
              size: 36,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _otherName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Đối soát toàn sổ',
            icon: const Icon(Icons.verified_user_outlined),
            onPressed: _openIntegrityScreen,
          ),
          const SizedBox(width: 4),
        ],
      ),
      bottomNavigationBar: ready
          ? BottomActionBar(
              child: ElevatedButton.icon(
                onPressed: _openAddTransactionScreen,
                icon: const Icon(Icons.add_rounded, size: 22),
                label: const Text('Thêm giao dịch'),
              ),
            )
          : null,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.negative),
          ),
        ),
      );
    }

    final txs = _transactions;
    final balance = LedgerMath.computeBalance(txs, _myId);

    final pendingForMe =
        txs.where((t) => t.isWaiting && t.recipientId == _myId).toList();
    final pendingFromMe =
        txs.where((t) => t.isWaiting && t.createdBy == _myId).toList();
    final recent = txs.where((t) => !t.isWaiting).take(6).toList();

    Widget rowOf(DebtTransaction tx) => TransactionTile(
          tx: tx,
          myId: _myId,
          otherName: _otherName,
          grouped: true,
          onTap: () => _openDetail(tx),
        );

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          BalanceCard(
            balance: balance,
            otherName: _otherName,
            transactionCount: txs.where((t) => t.isAccepted).length,
          ),
          const SizedBox(height: 24),
          if (pendingForMe.isNotEmpty) ...[
            SectionLabel('Chờ bạn xác nhận · ${pendingForMe.length}'),
            for (final tx in pendingForMe) ...[
              _PendingCard(
                tx: tx,
                otherName: _otherName,
                currentBalance: balance,
                responding: _respondingIds.contains(tx.id),
                onTap: () => _openDetail(tx),
                onAccept: () => _respond(tx, TxStatus.accepted),
                onDecline: () => _respond(tx, TxStatus.declined),
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 14),
          ],
          if (pendingFromMe.isNotEmpty) ...[
            SectionLabel('Đã gửi, chờ $_otherName xác nhận'),
            GroupedCard(children: pendingFromMe.map(rowOf).toList()),
            const SizedBox(height: 24),
          ],
          SectionLabel(
            'Lịch sử gần đây',
            trailing: TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => HistoryScreen(
                    me: widget.me,
                    otherName: _otherName,
                    transactions: txs,
                  ),
                ),
              ),
              child: const Text('Xem tất cả'),
            ),
          ),
          if (recent.isEmpty)
            const _EmptyState()
          else
            GroupedCard(children: recent.map(rowOf).toList()),
        ],
      ),
    );
  }
}

/// Yêu cầu người kia gửi, đang chờ mình. Cho xác nhận / từ chối ngay tại
/// sổ, kèm phép tính số dư nếu xác nhận.
class _PendingCard extends StatelessWidget {
  final DebtTransaction tx;
  final String otherName;
  final num currentBalance;
  final bool responding;
  final VoidCallback onTap;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _PendingCard({
    required this.tx,
    required this.otherName,
    required this.currentBalance,
    required this.responding,
    required this.onTap,
    required this.onAccept,
    required this.onDecline,
  });

  static String _signed(num value) {
    final sign = value >= 0 ? '+' : '−';
    return '$sign${CurrencyFormatter.format(value.abs())}';
  }

  @override
  Widget build(BuildContext context) {
    // Người kia tạo, mình là người nhận: xác nhận thì số dư phía mình trừ đi.
    final after = currentBalance - tx.amount;
    final isDebt = tx.type == TxType.debt;
    final title = isDebt
        ? '$otherName ghi nợ cho bạn'
        : '$otherName trả nợ cho bạn';
    final time = DateFormat('HH:mm d/M', 'vi_VN').format(tx.createdAt);

    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.waitingBorder, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isDebt
                          ? const Color(0xFFF3E5E0)
                          : AppColors.acceptedSoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isDebt
                          ? Icons.arrow_downward_rounded
                          : Icons.undo_rounded,
                      size: 18,
                      color: isDebt ? AppColors.negative : AppColors.positive,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          tx.description.isNotEmpty
                              ? '${tx.description} · $time'
                              : time,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    CurrencyFormatter.format(tx.amount),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Sau xác nhận: ${_signed(currentBalance)} − '
                  '${CurrencyFormatter.format(tx.amount)} = ${_signed(after)}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: responding ? null : onDecline,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 46),
                      ),
                      child: const Text('Từ chối'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: responding ? null : onAccept,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 46),
                      ),
                      child: const Text('Xác nhận'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: const Text(
        'Chưa có giao dịch nào.\nNhấn "Thêm giao dịch" để bắt đầu.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textSecondary, fontSize: 13.5),
      ),
    );
  }
}
