import 'dart:async';

import 'package:flutter/material.dart';

import '../models/app_profile.dart';
import '../models/connection.dart';
import '../services/auth_service.dart';
import '../services/connection_service.dart';
import '../services/contact_alias_service.dart';
import '../services/integrity_service.dart';
import '../services/ledger_math.dart';
import '../services/profile_service.dart';
import '../services/transaction_service.dart';
import '../theme/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../widgets/add_contact_sheet.dart';
import '../widgets/common.dart';
import '../widgets/integrity_card.dart';
import 'contact_ledger_screen.dart';
import 'data_integrity_screen.dart';

/// Sảnh: màn hình đầu tiên sau khi đăng nhập.
///
/// Gồm lời mời đang chờ, danh bạ bạn nợ (mở ra sổ nợ riêng của từng người) và
/// thẻ đối soát — thẻ này giữ phạm vi TOÀN BỘ giao dịch, đúng bằng phạm vi
/// RPC `ledger_snapshot()` phía server tính, nên không đụng gì tới logic đối soát.
class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  final _authService = AuthService();
  final _profileService = ProfileService();
  final _connectionService = ConnectionService();
  final _aliasService = ContactAliasService();
  final _transactionService = TransactionService();
  final _integrityService = IntegrityService();

  StreamSubscription<List<DebtConnection>>? _connectionSub;
  StreamSubscription<List<Map<String, dynamic>>>? _transactionSub;

  AppProfile? _me;
  List<DebtConnection> _connections = const [];
  Map<String, AppProfile> _profiles = const {};
  Map<String, String> _aliases = const {};
  List<Map<String, dynamic>> _rows = const [];
  IntegrityCheckResult? _integrity;

  bool _loading = true;
  bool _checking = false;
  bool _checkQueued = false;
  String? _error;

  String get _myId => _me!.id;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _connectionSub?.cancel();
    _transactionSub?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final uid = _authService.currentUser!.id;
      final me = await _profileService.fetchMyProfile(uid);
      final aliases = await _aliasService.fetchAliases();
      if (!mounted) return;
      setState(() {
        _me = me;
        _aliases = aliases;
      });
      _listen();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Không tải được sảnh: $e';
      });
    }
  }

  void _listen() {
    _connectionSub = _connectionService.streamMyConnections().listen(
      (connections) {
        if (!mounted) return;
        setState(() {
          _connections = connections;
          _loading = false;
        });
        unawaited(_loadMissingProfiles(connections));
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'Không tải được danh bạ: $error';
        });
      },
    );

    _transactionSub = _transactionService.streamMyTransactionRows().listen(
      (rows) {
        if (!mounted) return;
        setState(() {
          _rows = rows;
          _loading = false;
          _error = null;
        });
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

  /// Chỉ tải hồ sơ của người chưa có trong bộ nhớ — realtime bắn lại nhiều lần.
  Future<void> _loadMissingProfiles(List<DebtConnection> connections) async {
    final ids = connections
        .where((c) => c.involves(_myId) && !c.isDeclined)
        .map((c) => c.otherId(_myId))
        .where((id) => !_profiles.containsKey(id))
        .toSet();

    if (ids.isEmpty) return;
    try {
      final fetched = await _profileService.fetchProfilesByIds(ids);
      if (!mounted) return;
      setState(() => _profiles = {..._profiles, ...fetched});
    } catch (_) {
      // Đọc hồ sơ lỗi không được làm hỏng sảnh; ô thiếu tên sẽ bị bỏ qua.
    }
  }

  void _scheduleIntegrityCheck() {
    if (_checkQueued) return;
    _checkQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkQueued = false;
      unawaited(_checkIntegrity());
    });
  }

  /// Đối soát với dữ liệu đang thấy + mốc đã chốt trên máy (không gọi mạng).
  Future<void> _checkIntegrity() async {
    if (_checking || _me == null) return;
    setState(() => _checking = true);
    try {
      final result = await _integrityService.checkRows(
        rows: _rows,
        myId: _myId,
      );
      if (!mounted) return;
      setState(() {
        _integrity = result;
        _checking = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _checking = false);
    }
  }

  Future<void> _refresh() async {
    try {
      final rows = await _transactionService.fetchTransactionRows();
      if (!mounted) return;
      setState(() => _rows = rows);
      await _checkIntegrity();
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
    if (mounted) await _checkIntegrity();
  }

  Future<void> _respond(ContactEntry entry, bool accept) async {
    try {
      await _connectionService.respond(
        connectionId: entry.connection.id,
        accept: accept,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accept
                ? 'Đã thêm ${entry.displayName} vào danh bạ.'
                : 'Đã từ chối lời mời.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không thực hiện được: $e')),
      );
    }
  }

  Future<void> _editAlias(ContactEntry entry) async {
    final controller = TextEditingController(text: entry.alias ?? '');
    final saved = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Tên riêng cho ${entry.profile.displayName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 60,
              decoration: const InputDecoration(
                hintText: 'Ví dụ: Anh Nam',
                counterText: '',
              ),
              onSubmitted: (value) =>
                  Navigator.of(dialogContext).pop(value.trim()),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tên này chỉ mình bạn thấy.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textFaint),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Huỷ'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (saved == null || !mounted) return;

    try {
      final contactId = entry.profile.id;
      final aliases = {..._aliases};
      if (saved.isEmpty) {
        await _aliasService.clearAlias(contactId);
        aliases.remove(contactId);
      } else {
        await _aliasService.upsertAlias(contactId: contactId, alias: saved);
        aliases[contactId] = saved;
      }
      if (!mounted) return;
      setState(() => _aliases = aliases);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không lưu được tên riêng: $e')),
      );
    }
  }

  Future<void> _openContact(ContactEntry entry) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ContactLedgerScreen(me: _me!, contact: entry),
      ),
    );
  }

  /// Màu chấm nhỏ trên nút đối soát; null khi chưa có kết quả.
  Color? get _integrityDot {
    final report = _integrity?.report;
    if (report == null || _checking) return null;
    if (report.criticalCount > 0) return AppColors.negative;
    if (report.warningCount > 0) return AppColors.waiting;
    return AppColors.positive;
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;

    if (me == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sảnh')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _error != null
                ? Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.negative),
                  )
                : const CircularProgressIndicator(),
          ),
        ),
      );
    }

    return Scaffold(
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _LobbyHeader(
              me: me,
              integrityDot: _integrityDot,
              onIntegrity: _openIntegrityScreen,
              onSignOut: () => _authService.signOut(),
            ),
            Expanded(child: _buildBody(me)),
          ],
        ),
      ),
      bottomNavigationBar: BottomActionBar(
        child: ElevatedButton.icon(
          onPressed: () => showAddContactSheet(context),
          icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
          label: const Text('Thêm bạn nợ'),
        ),
      ),
    );
  }

  Widget _buildBody(AppProfile me) {
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

    final book = ContactBook.from(
      myId: me.id,
      connections: _connections,
      profiles: _profiles,
      aliases: _aliases,
    );

    final balances = {
      for (final entry in book.contacts)
        entry.profile.id: _balanceWith(entry.profile.id),
    };
    num owedToMe = 0;
    num iOwe = 0;
    for (final balance in balances.values) {
      if (balance > 0) {
        owedToMe += balance;
      } else {
        iOwe -= balance;
      }
    }

    final waitingOnMe = [
      for (final entry in book.contacts)
        if (_pendingForMe(entry.profile.id) > 0) entry,
    ];
    final waitingCount = waitingOnMe.fold<int>(
      0,
      (sum, entry) => sum + _pendingForMe(entry.profile.id),
    );

    final report = _integrity?.report;
    final integrityNeedsAttention = report != null &&
        !_checking &&
        (report.criticalCount > 0 || report.warningCount > 0);

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          _SummaryCard(owedToMe: owedToMe, iOwe: iOwe),
          if (integrityNeedsAttention) ...[
            const SizedBox(height: 12),
            IntegrityCard(
              report: report,
              checking: _checking,
              onTap: _openIntegrityScreen,
            ),
          ],
          if (waitingCount > 0) ...[
            const SizedBox(height: 12),
            _WaitingBanner(
              count: waitingCount,
              names: waitingOnMe.map((e) => e.displayName).toList(),
              onTap: () => _openContact(waitingOnMe.first),
            ),
          ],
          const SizedBox(height: 24),

          if (book.incoming.isNotEmpty) ...[
            const SectionLabel('Lời mời mới'),
            GroupedCard(
              children: [
                for (final entry in book.incoming)
                  _RequestRow(
                    entry: entry,
                    incoming: true,
                    onAccept: () => _respond(entry, true),
                    onDecline: () => _respond(entry, false),
                  ),
              ],
            ),
            const SizedBox(height: 24),
          ],

          if (book.outgoing.isNotEmpty) ...[
            const SectionLabel('Đã gửi, chờ trả lời'),
            GroupedCard(
              children: [
                for (final entry in book.outgoing)
                  _RequestRow(entry: entry, incoming: false),
              ],
            ),
            const SizedBox(height: 24),
          ],

          SectionLabel(
            book.contacts.isEmpty
                ? 'Danh bạ'
                : 'Danh bạ · ${book.contacts.length}',
            trailing: book.contacts.isEmpty
                ? null
                : const Text(
                    'Giữ để đổi tên',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
          ),
          if (book.contacts.isEmpty)
            const _EmptyContacts()
          else
            GroupedCard(
              children: [
                for (final entry in book.contacts)
                  _ContactRow(
                    entry: entry,
                    balance: balances[entry.profile.id] ?? 0,
                    pendingForMe: _pendingForMe(entry.profile.id),
                    onTap: () => _openContact(entry),
                    onEditAlias: () => _editAlias(entry),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  num _balanceWith(String otherId) {
    final rows = _rows
        .where((row) => LedgerMath.rawBetween(row, _myId, otherId))
        .toList();
    return LedgerMath.computeRawBalance(rows, _myId);
  }

  int _pendingForMe(String otherId) {
    return _rows.where((row) {
      return LedgerMath.rawBetween(row, _myId, otherId) &&
          row['status'] == 'waiting' &&
          row['recipient_id'] == _myId;
    }).length;
  }
}

class _LobbyHeader extends StatelessWidget {
  final AppProfile me;
  final Color? integrityDot;
  final VoidCallback onIntegrity;
  final VoidCallback onSignOut;

  const _LobbyHeader({
    required this.me,
    required this.integrityDot,
    required this.onIntegrity,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
      child: Row(
        children: [
          InitialAvatar(initial: me.initial, seed: me.id),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Xin chào',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  me.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
          _CircleIconButton(
            tooltip: 'Đối soát dữ liệu',
            icon: Icons.verified_user_outlined,
            color: AppColors.accent,
            dot: integrityDot,
            onPressed: onIntegrity,
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            tooltip: 'Tài khoản',
            position: PopupMenuPosition.under,
            onSelected: (value) {
              if (value == 'logout') onSignOut();
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                enabled: false,
                child: Text(
                  me.email,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout_rounded, size: 20),
                    SizedBox(width: 12),
                    Text('Đăng xuất'),
                  ],
                ),
              ),
            ],
            child: const _CircleIconButton(
              icon: Icons.more_horiz_rounded,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Nút tròn viền mảnh 44px. Không có [onPressed] thì chỉ vẽ (dùng làm
/// child của PopupMenuButton, nút đó tự lo phần bấm).
class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String? tooltip;
  final Color? dot;
  final VoidCallback? onPressed;

  const _CircleIconButton({
    required this.icon,
    required this.color,
    this.tooltip,
    this.dot,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final circle = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.surface,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.border),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(icon, size: 20, color: color),
          if (dot != null)
            Positioned(
              top: 9,
              right: 9,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: dot,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.surface, width: 2),
                ),
              ),
            ),
        ],
      ),
    );

    if (onPressed == null) return circle;
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: circle,
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final num owedToMe;
  final num iOwe;

  const _SummaryCard({required this.owedToMe, required this.iOwe});

  @override
  Widget build(BuildContext context) {
    final net = owedToMe - iOwe;
    final String caption;
    if (net > 0) {
      caption = 'Mọi người đang nợ bạn nhiều hơn bạn nợ họ';
    } else if (net < 0) {
      caption = 'Bạn đang nợ nhiều hơn được nợ';
    } else {
      caption = 'Không ai nợ ai';
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.hero,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Số dư ròng của bạn',
            style: TextStyle(fontSize: 13, color: Color(0xCCFFFFFF)),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              net == 0
                  ? CurrencyFormatter.format(0)
                  : CurrencyFormatter.formatSigned(net, positive: net > 0),
              style: const TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.8,
                color: Colors.white,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            caption,
            style: const TextStyle(fontSize: 13, color: Color(0xCCFFFFFF)),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _SummaryTile(label: 'Được nợ', amount: owedToMe),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SummaryTile(label: 'Đang nợ', amount: iOwe),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final String label;
  final num amount;

  const _SummaryTile({required this.label, required this.amount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0x1AFFFFFF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Color(0xCCFFFFFF)),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              CurrencyFormatter.format(amount),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WaitingBanner extends StatelessWidget {
  final int count;
  final List<String> names;
  final VoidCallback onTap;

  const _WaitingBanner({
    required this.count,
    required this.names,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final from = names.length <= 2
        ? names.join(' và ')
        : '${names.take(2).join(', ')} và ${names.length - 2} người khác';

    return Material(
      color: AppColors.waitingSoft,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.waitingBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: Color(0xFFF3E3BF),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.schedule_rounded,
                  size: 19,
                  color: AppColors.waiting,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$count yêu cầu chờ bạn xác nhận',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Từ $from',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF6B5A35),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.waiting,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final ContactEntry entry;
  final num balance;
  final int pendingForMe;
  final VoidCallback onTap;
  final VoidCallback onEditAlias;

  const _ContactRow({
    required this.entry,
    required this.balance,
    required this.pendingForMe,
    required this.onTap,
    required this.onEditAlias,
  });

  @override
  Widget build(BuildContext context) {
    final String subtitle;
    final Color subtitleColor;
    if (pendingForMe > 0) {
      subtitle = '$pendingForMe yêu cầu chờ bạn';
      subtitleColor = AppColors.waiting;
    } else if (balance == 0) {
      subtitle = 'Đã cân bằng';
      subtitleColor = AppColors.textSecondary;
    } else {
      subtitle = balance > 0 ? 'Đang nợ bạn' : 'Bạn đang nợ';
      subtitleColor = AppColors.textSecondary;
    }

    return Semantics(
      onLongPressHint: 'Đổi tên riêng',
      child: InkWell(
        onTap: onTap,
        onLongPress: onEditAlias,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              InitialAvatar(
                initial: entry.profile.initial,
                seed: entry.profile.id,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: subtitleColor,
                        fontWeight: pendingForMe > 0
                            ? FontWeight.w500
                            : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (balance == 0)
                const Text(
                  '0 đ',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                )
              else
                Text(
                  CurrencyFormatter.formatSigned(balance, positive: balance > 0),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: balance > 0 ? AppColors.positive : AppColors.negative,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RequestRow extends StatelessWidget {
  final ContactEntry entry;
  final bool incoming;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;

  const _RequestRow({
    required this.entry,
    required this.incoming,
    this.onAccept,
    this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Row(
        children: [
          InitialAvatar(
            initial: entry.profile.initial,
            seed: entry.profile.id,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.profile.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  incoming ? 'Muốn kết nối với bạn' : 'Đang chờ họ đồng ý',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (incoming) ...[
            IconButton(
              tooltip: 'Từ chối',
              onPressed: onDecline,
              style: IconButton.styleFrom(
                side: const BorderSide(color: AppColors.border),
                fixedSize: const Size(44, 44),
              ),
              icon: const Icon(
                Icons.close_rounded,
                size: 20,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 6),
            ElevatedButton(
              onPressed: onAccept,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: const Text('Đồng ý'),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyContacts extends StatelessWidget {
  const _EmptyContacts();

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
      child: const Column(
        children: [
          Icon(
            Icons.group_add_outlined,
            size: 32,
            color: AppColors.textFaint,
          ),
          SizedBox(height: 12),
          Text(
            'Chưa có ai trong danh bạ.',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Nhấn "Thêm bạn nợ" để lấy mã của bạn, hoặc nhập mã của người kia.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
