import 'dart:async';

import 'package:flutter/material.dart';

import '../models/app_profile.dart';
import '../models/debt_transaction.dart';
import '../models/ledger_snapshot.dart';
import '../services/auth_service.dart';
import '../services/integrity_service.dart';
import '../services/ledger_math.dart';
import '../services/profile_service.dart';
import '../services/transaction_service.dart';
import '../theme/app_theme.dart';
import '../widgets/balance_card.dart';
import '../widgets/integrity_card.dart';
import '../widgets/transaction_tile.dart';
import 'add_transaction_screen.dart';
import 'data_integrity_screen.dart';
import 'history_screen.dart';
import 'invoice_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _profileService = ProfileService();
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
          transactionService: TransactionService(),
          authService: _authService,
        );
      },
    );
  }
}

class _HomeBody extends StatefulWidget {
  final AppProfile me;
  final AppProfile other;
  final TransactionService transactionService;
  final AuthService authService;

  const _HomeBody({
    required this.me,
    required this.other,
    required this.transactionService,
    required this.authService,
  });

  @override
  State<_HomeBody> createState() => _HomeBodyState();
}

class _HomeBodyState extends State<_HomeBody> {
  final _integrityService = IntegrityService();

  StreamSubscription<List<Map<String, dynamic>>>? _subscription;
  List<Map<String, dynamic>> _rows = const [];
  List<DebtTransaction> _transactions = const [];
  IntegrityCheckResult? _integrity;
  bool _loading = true;
  bool _checking = false;
  bool _checkQueued = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _subscription = widget.transactionService.streamMyTransactionRows().listen(
      (rows) {
        if (!mounted) return;
        setState(() {
          _rows = rows;
          _transactions = rows.map(DebtTransaction.fromMap).toList();
          _loading = false;
          _error = null;
        });
        // Đối soát chạy sau frame để không setState trong lúc build.
        _scheduleIntegrityCheck();
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

  void _scheduleIntegrityCheck() {
    if (_checkQueued) return;
    _checkQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkQueued = false;
      unawaited(_checkIntegrity());
    });
  }

  /// Đối soát dữ liệu đang thấy với mốc đã chốt.
  ///
  /// Không gọi mạng: chỉ so với mốc trên máy, nên chạy được cả khi offline.
  /// [server] chỉ truyền vào khi vừa lấy dữ liệu và snapshot cùng một lượt,
  /// để tránh báo lệch giả do realtime chen vào giữa hai lần gọi.
  Future<void> _checkIntegrity({LedgerSnapshot? server, String? note}) async {
    if (_checking) return;
    if (!mounted) return;
    setState(() => _checking = true);
    try {
      final result = await _integrityService.checkRows(
        rows: _rows,
        myId: widget.me.id,
        server: server,
        note: note,
      );
      if (!mounted) return;
      setState(() {
        _integrity = result;
        _checking = false;
      });
    } catch (e) {
      // Đối soát lỗi không được làm hỏng màn hình chính.
      if (!mounted) return;
      setState(() => _checking = false);
    }
  }

  /// Kéo để làm mới: lấy lại dữ liệu + số dư do server tính rồi đối soát.
  Future<void> _refresh() async {
    try {
      final rows = await widget.transactionService.fetchTransactionRows();
      LedgerSnapshot? server;
      String? note;
      try {
        server = await _integrityService.fetchServerSnapshot();
      } catch (_) {
        note = 'Chưa gọi được đối soát phía server.';
      }
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _transactions = rows.map(DebtTransaction.fromMap).toList();
      });
      await _checkIntegrity(server: server, note: note);
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
        builder: (_) => DataIntegrityScreen(myId: widget.me.id),
      ),
    );
    // Màn hình đối soát có thể đã chốt lại mốc; kiểm tra lại cho khớp.
    if (mounted) await _checkIntegrity();
  }

  @override
  Widget build(BuildContext context) {
    final me = widget.me;
    final other = widget.other;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sổ Nợ'),
        actions: [
          IconButton(
            tooltip: 'Đối soát dữ liệu',
            icon: const Icon(Icons.verified_user_outlined),
            onPressed: _openIntegrityScreen,
          ),
          IconButton(
            tooltip: 'Đăng xuất',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => widget.authService.signOut(),
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
      body: _buildBody(me, other),
    );
  }

  Widget _buildBody(AppProfile me, AppProfile other) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          style: const TextStyle(color: AppColors.negative),
        ),
      );
    }

    final txs = _transactions;
    final balance = LedgerMath.computeBalance(txs, me.id);

    final pendingForMe =
        txs.where((t) => t.isWaiting && t.recipientId == me.id).toList();
    final pendingFromMe =
        txs.where((t) => t.isWaiting && t.createdBy == me.id).toList();
    final recent = txs.where((t) => !t.isWaiting).take(6).toList();

    void openDetail(DebtTransaction tx) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => InvoiceDetailScreen(
            tx: tx,
            myId: me.id,
            otherName: other.displayName,
          ),
        ),
      );
    }

    Widget tileOf(DebtTransaction tx) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TransactionTile(
            tx: tx,
            myId: me.id,
            otherName: other.displayName,
            onTap: () => openDetail(tx),
          ),
        );

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          BalanceCard(balance: balance, otherName: other.displayName),
          const SizedBox(height: 12),
          IntegrityCard(
            report: _integrity?.report,
            checking: _checking,
            onTap: _openIntegrityScreen,
          ),
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
              title: 'Đã gửi, chờ ${other.displayName} xác nhận',
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
                      me: me,
                      other: other,
                      transactionService: widget.transactionService,
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
