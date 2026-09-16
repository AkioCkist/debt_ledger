import 'dart:async';

import 'package:flutter/material.dart';

import '../models/app_profile.dart';
import '../models/connection.dart';
import '../models/debt_transaction.dart';
import '../services/ledger_math.dart';
import '../services/transaction_service.dart';
import '../theme/app_theme.dart';
import '../widgets/balance_card.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_otherName),
        actions: [
          IconButton(
            tooltip: 'Đối soát toàn sổ',
            icon: const Icon(Icons.verified_user_outlined),
            onPressed: _openIntegrityScreen,
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AddTransactionScreen(
                me: widget.me,
                otherId: _otherId,
                otherName: _otherName,
              ),
            ),
          );
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('Thêm giao dịch'),
      ),
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

    void openDetail(DebtTransaction tx) {
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

    Widget tileOf(DebtTransaction tx) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TransactionTile(
            tx: tx,
            myId: _myId,
            otherName: _otherName,
            onTap: () => openDetail(tx),
          ),
        );

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          BalanceCard(balance: balance, otherName: _otherName),
          const SizedBox(height: 24),

          if (pendingForMe.isNotEmpty) ...[
            _SectionHeader(
              title: 'Cần bạn xác nhận',
              subtitle: '${pendingForMe.length} yêu cầu đang chờ',
            ),
            const SizedBox(height: 10),
            ...pendingForMe.map(tileOf),
            const SizedBox(height: 14),
          ],

          if (pendingFromMe.isNotEmpty) ...[
            _SectionHeader(
              title: 'Đã gửi, chờ $_otherName xác nhận',
              subtitle: '${pendingFromMe.length} yêu cầu',
            ),
            const SizedBox(height: 10),
            ...pendingFromMe.map(tileOf),
            const SizedBox(height: 14),
          ],

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const _SectionHeader(title: 'Lịch sử gần đây'),
              TextButton(
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
            ],
          ),
          const SizedBox(height: 4),
          if (recent.isEmpty)
            const _EmptyState()
          else
            ...recent.map(tileOf),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  const _SectionHeader({required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2, top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                subtitle!,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
        ],
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
      padding: const EdgeInsets.symmetric(vertical: 32),
      alignment: Alignment.center,
      child: const Text(
        'Chưa có giao dịch nào.\nNhấn "Thêm giao dịch" để bắt đầu.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textFaint, fontSize: 13.5),
      ),
    );
  }
}
