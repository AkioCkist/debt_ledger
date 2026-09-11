import 'package:flutter/material.dart';

import '../models/app_profile.dart';
import '../models/debt_transaction.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';
import '../services/transaction_service.dart';
import '../theme/app_theme.dart';
import '../widgets/balance_card.dart';
import '../widgets/transaction_tile.dart';
import 'add_transaction_screen.dart';
import 'history_screen.dart';
import 'invoice_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _profileService = ProfileService();
  final _transactionService = TransactionService();
  final _authService = AuthService();

  late Future<({AppProfile me, AppProfile other})> _profilesFuture;

  @override
  void initState() {
    super.initState();
    _profilesFuture = _loadProfiles();
  }

  Future<({AppProfile me, AppProfile other})> _loadProfiles() async {
    final uid = _authService.currentUser!.id;
    final me = await _profileService.fetchMyProfile(uid);
    final other = await _profileService.fetchOtherProfile(uid);
    return (me: me, other: other);
  }

  num _computeBalance(List<DebtTransaction> txs, String myId) {
    num balance = 0;
    for (final tx in txs) {
      if (!tx.isAccepted) continue;
      balance += tx.createdBy == myId ? tx.amount : -tx.amount;
    }
    return balance;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _profilesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.negative),
                ),
              ),
            ),
          );
        }

        final me = snapshot.data!.me;
        final other = snapshot.data!.other;

        return _HomeBody(
          me: me,
          other: other,
          transactionService: _transactionService,
          authService: _authService,
          computeBalance: _computeBalance,
        );
      },
    );
  }
}

class _HomeBody extends StatelessWidget {
  final AppProfile me;
  final AppProfile other;
  final TransactionService transactionService;
  final AuthService authService;
  final num Function(List<DebtTransaction>, String) computeBalance;

  const _HomeBody({
    required this.me,
    required this.other,
    required this.transactionService,
    required this.authService,
    required this.computeBalance,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sổ Nợ'),
        actions: [
          IconButton(
            tooltip: 'Đăng xuất',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => authService.signOut(),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AddTransactionScreen(me: me, other: other),
            ),
          );
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('Thêm giao dịch'),
      ),
      body: StreamBuilder<List<DebtTransaction>>(
        stream: transactionService.streamMyTransactions(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Không tải được dữ liệu: ${snapshot.error}',
                style: const TextStyle(color: AppColors.negative),
              ),
            );
          }

          final txs = snapshot.data ?? [];
          final balance = computeBalance(txs, me.id);

          final pendingForMe = txs
              .where((t) => t.isWaiting && t.recipientId == me.id)
              .toList();
          final pendingFromMe = txs
              .where((t) => t.isWaiting && t.createdBy == me.id)
              .toList();
          final recent = txs.where((t) => !t.isWaiting).take(6).toList();

          return RefreshIndicator(
            onRefresh: () async {},
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              children: [
                BalanceCard(balance: balance, otherName: other.displayName),
                const SizedBox(height: 24),

                if (pendingForMe.isNotEmpty) ...[
                  _SectionHeader(
                    title: 'Cần bạn xác nhận',
                    subtitle: '${pendingForMe.length} yêu cầu đang chờ',
                  ),
                  const SizedBox(height: 10),
                  ...pendingForMe.map(
                    (tx) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TransactionTile(
                        tx: tx,
                        myId: me.id,
                        otherName: other.displayName,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => InvoiceDetailScreen(
                              tx: tx,
                              myId: me.id,
                              otherName: other.displayName,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                if (pendingFromMe.isNotEmpty) ...[
                  _SectionHeader(
                    title: 'Đã gửi, chờ ${other.displayName} xác nhận',
                    subtitle: '${pendingFromMe.length} yêu cầu',
                  ),
                  const SizedBox(height: 10),
                  ...pendingFromMe.map(
                    (tx) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TransactionTile(
                        tx: tx,
                        myId: me.id,
                        otherName: other.displayName,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => InvoiceDetailScreen(
                              tx: tx,
                              myId: me.id,
                              otherName: other.displayName,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
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
                            me: me,
                            other: other,
                            transactionService: transactionService,
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
                  ...recent.map(
                    (tx) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TransactionTile(
                        tx: tx,
                        myId: me.id,
                        otherName: other.displayName,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => InvoiceDetailScreen(
                              tx: tx,
                              myId: me.id,
                              otherName: other.displayName,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
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
