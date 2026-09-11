import 'package:flutter/material.dart';

import '../models/app_profile.dart';
import '../models/debt_transaction.dart';
import '../services/transaction_service.dart';
import '../theme/app_theme.dart';
import '../widgets/transaction_tile.dart';
import 'invoice_detail_screen.dart';

enum _Filter { all, waiting, accepted, declined }

class HistoryScreen extends StatefulWidget {
  final AppProfile me;
  final AppProfile other;
  final TransactionService transactionService;

  const HistoryScreen({
    super.key,
    required this.me,
    required this.other,
    required this.transactionService,
  });

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  _Filter _filter = _Filter.all;

  List<DebtTransaction> _apply(List<DebtTransaction> txs) {
    switch (_filter) {
      case _Filter.all:
        return txs;
      case _Filter.waiting:
        return txs.where((t) => t.isWaiting).toList();
      case _Filter.accepted:
        return txs.where((t) => t.isAccepted).toList();
      case _Filter.declined:
        return txs.where((t) => t.isDeclined).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lịch sử giao dịch')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _FilterChip(
                      label: 'Tất cả',
                      selected: _filter == _Filter.all,
                      onTap: () => setState(() => _filter = _Filter.all),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Chờ xác nhận',
                      selected: _filter == _Filter.waiting,
                      onTap: () => setState(() => _filter = _Filter.waiting),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Đã xác nhận',
                      selected: _filter == _Filter.accepted,
                      onTap: () => setState(() => _filter = _Filter.accepted),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Đã từ chối',
                      selected: _filter == _Filter.declined,
                      onTap: () => setState(() => _filter = _Filter.declined),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder<List<DebtTransaction>>(
                stream: widget.transactionService.streamMyTransactions(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final txs = _apply(snapshot.data ?? []);
                  if (txs.isEmpty) {
                    return const Center(
                      child: Text(
                        'Không có giao dịch nào.',
                        style: TextStyle(color: AppColors.textFaint),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: txs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final tx = txs[index];
                      return TransactionTile(
                        tx: tx,
                        myId: widget.me.id,
                        otherName: widget.other.displayName,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => InvoiceDetailScreen(
                              tx: tx,
                              myId: widget.me.id,
                              otherName: widget.other.displayName,
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
