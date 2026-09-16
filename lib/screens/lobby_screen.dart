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
      appBar: AppBar(
        title: const Text('Sảnh'),
        actions: [
          IconButton(
            tooltip: 'Đối soát dữ liệu',
            icon: const Icon(Icons.verified_user_outlined),
            onPressed: _openIntegrityScreen,
          ),
          IconButton(
            tooltip: 'Đăng xuất',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => _authService.signOut(),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAddContactSheet(context),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Thêm bạn nợ'),
      ),
      body: _buildBody(me),
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

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          _MeHeader(me: me),
          const SizedBox(height: 12),
          IntegrityCard(
            report: _integrity?.report,
            checking: _checking,
            onTap: _openIntegrityScreen,
          ),
          const SizedBox(height: 24),

          if (book.incoming.isNotEmpty) ...[
            const _SectionHeader(
              title: 'Lời mời kết bạn nợ',
              subtitle: 'Đồng ý thì hai bạn thấy nhau trong danh bạ',
            ),
            const SizedBox(height: 10),
            ...book.incoming.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _RequestTile(
                  entry: entry,
                  incoming: true,
                  onAccept: () => _respond(entry, true),
                  onDecline: () => _respond(entry, false),
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],

          if (book.outgoing.isNotEmpty) ...[
            const _SectionHeader(
              title: 'Đã gửi, chờ trả lời',
              subtitle: 'Người kia chưa phản hồi lời mời của bạn',
            ),
            const SizedBox(height: 10),
            ...book.outgoing.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _RequestTile(entry: entry, incoming: false),
              ),
            ),
            const SizedBox(height: 14),
          ],

          const _SectionHeader(
            title: 'Danh bạ',
            subtitle: 'Chạm vào một người để mở sổ nợ riêng',
          ),
          const SizedBox(height: 10),
          if (book.contacts.isEmpty)
            const _EmptyContacts()
          else
            ...book.contacts.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ContactTile(
                  entry: entry,
                  balance: _balanceWith(entry.profile.id),
                  pendingForMe: _pendingForMe(entry.profile.id),
                  onTap: () => _openContact(entry),
                  onEditAlias: () => _editAlias(entry),
                ),
              ),
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

class _MeHeader extends StatelessWidget {
  final AppProfile me;

  const _MeHeader({required this.me});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: AppColors.accentSoft,
          child: Text(
            me.initial,
            style: const TextStyle(
              color: AppColors.accent,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                me.displayName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                me.email,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ContactTile extends StatelessWidget {
  final ContactEntry entry;
  final num balance;
  final int pendingForMe;
  final VoidCallback onTap;
  final VoidCallback onEditAlias;

  const _ContactTile({
    required this.entry,
    required this.balance,
    required this.pendingForMe,
    required this.onTap,
    required this.onEditAlias,
  });

  @override
  Widget build(BuildContext context) {
    final name = entry.displayName;

    final String subtitle;
    if (pendingForMe > 0) {
      subtitle = '$pendingForMe yêu cầu đang chờ bạn xác nhận';
    } else if (balance == 0) {
      subtitle = 'Đã cân bằng';
    } else if (balance > 0) {
      subtitle = '$name đang nợ bạn ${CurrencyFormatter.format(balance)}';
    } else {
      subtitle = 'Bạn đang nợ $name ${CurrencyFormatter.format(balance.abs())}';
    }

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.accentSoft,
                child: Text(
                  entry.profile.initial,
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
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
                        color: pendingForMe > 0
                            ? AppColors.waiting
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Sửa tên riêng',
                icon: const Icon(
                  Icons.edit_outlined,
                  size: 18,
                  color: AppColors.textFaint,
                ),
                onPressed: onEditAlias,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RequestTile extends StatelessWidget {
  final ContactEntry entry;
  final bool incoming;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;

  const _RequestTile({
    required this.entry,
    required this.incoming,
    this.onAccept,
    this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: incoming ? AppColors.accent : AppColors.border,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.accentSoft,
                child: Text(
                  entry.profile.initial,
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.profile.displayName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      incoming
                          ? 'Muốn kết nối với bạn'
                          : 'Đang chờ họ đồng ý',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (incoming) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onDecline,
                    child: const Text('Từ chối'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onAccept,
                    child: const Text('Đồng ý'),
                  ),
                ),
              ],
            ),
          ],
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

class _EmptyContacts extends StatelessWidget {
  const _EmptyContacts();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
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
            style: TextStyle(fontSize: 13, color: AppColors.textFaint),
          ),
        ],
      ),
    );
  }
}
