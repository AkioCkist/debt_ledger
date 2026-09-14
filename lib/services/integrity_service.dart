import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/integrity_report.dart';
import '../models/ledger_snapshot.dart';
import '../models/sync_checkpoint.dart';
import 'integrity_store.dart';
import 'ledger_math.dart';

/// Kết quả một lần đối soát: báo cáo cho người dùng + mốc đối soát mới.
class IntegrityCheckResult {
  final IntegrityReport report;

  /// Mốc mới, chỉ nên lưu khi [IntegrityReport.isTrusted] (hoặc khi người
  /// dùng chủ động chốt lại). Mốc cũ được giữ nguyên khi có bất thường
  /// nghiêm trọng, để lần sau vẫn phát hiện được.
  final SyncCheckpoint nextCheckpoint;

  const IntegrityCheckResult({
    required this.report,
    required this.nextCheckpoint,
  });
}

/// Đối soát dữ liệu sổ nợ.
///
/// Cách tiếp cận: coi `transactions` là source of truth, tính lại số dư từ
/// chính các dòng đọc được, rồi so với (a) mốc đối soát đã lưu trên máy và
/// (b) kết quả server tính qua RPC `ledger_snapshot()`.
///
/// Không giữ secret nào trong client. Việc chặn sửa `amount`/`type`... nằm ở
/// database (trigger + column privilege); ở đây chỉ phát hiện sai lệch.
class IntegrityService {
  /// Truy cập muộn để phần logic thuần ([evaluate]) test được mà không cần
  /// khởi tạo Supabase.
  SupabaseClient get _client => Supabase.instance.client;

  final IntegrityStore _store = IntegrityStore.instance;

  /// Ví dụ dữ liệu cũ: dòng đã accepted nhưng thiếu `responded_at`.
  static const Duration _clockSkewTolerance = Duration(minutes: 15);

  static const _knownTypes = {'debt', 'payment'};
  static const _knownStatuses = {'waiting', 'accepted', 'declined'};

  /// Chạy đối soát với dữ liệu vừa lấy từ server (dùng cho màn hình chính,
  /// nơi đã có sẵn dữ liệu realtime, không cần gọi mạng thêm).
  Future<IntegrityCheckResult> checkRows({
    required List<Map<String, dynamic>> rows,
    required String myId,
    LedgerSnapshot? server,
    String? note,
    bool persist = true,
  }) async {
    final baseline = await _store.read(myId);
    final result = evaluate(
      rows: rows,
      myId: myId,
      baseline: baseline,
      server: server,
      note: note,
    );
    if (persist && result.report.isTrusted) {
      await _store.write(result.nextCheckpoint);
    }
    return result;
  }

  /// Đối soát độc lập: tự lấy dữ liệu mới nhất từ server + gọi RPC.
  ///
  /// [forceAccept] dùng khi người dùng đã xem bất thường và chủ động chốt
  /// lại mốc: khi đó mốc luôn được ghi đè.
  Future<IntegrityCheckResult> verifyNow({
    required String myId,
    bool forceAccept = false,
  }) async {
    final rows = await _client
        .from('transactions')
        .select()
        .order('created_at', ascending: false);

    String? note;
    LedgerSnapshot? server;
    try {
      server = await fetchServerSnapshot();
    } catch (e) {
      // RPC lỗi (chưa chạy migration, mất mạng...) không được làm hỏng đối soát.
      note = 'Không gọi được đối soát phía server: $e';
    }

    final mapped = rows.cast<Map<String, dynamic>>();
    if (forceAccept) {
      return acceptCurrentState(rows: mapped, myId: myId, server: server);
    }
    return checkRows(rows: mapped, myId: myId, server: server, note: note);
  }

  Future<LedgerSnapshot?> fetchServerSnapshot() async {
    final response = await _client.rpc('ledger_snapshot');
    if (response is Map) {
      return LedgerSnapshot.fromMap(response.cast<String, dynamic>());
    }
    return null;
  }

  Future<SyncCheckpoint?> loadCheckpoint(String myId) => _store.read(myId);

  Future<void> resetCheckpoint(String myId) => _store.clear(myId);

  /// Chốt lại mốc từ dữ liệu hiện tại — dùng khi người dùng đã xem và
  /// chấp nhận các bất thường.
  ///
  /// Sau khi ghi mốc, đối soát lại một lượt để báo cáo trả về phản ánh đúng
  /// trạng thái vừa chốt (không còn cảnh báo "khác mốc"), trong khi các vấn đề
  /// vốn thuộc về dữ liệu (số tiền ≤ 0, tự ghi nợ chính mình...) vẫn hiện.
  Future<IntegrityCheckResult> acceptCurrentState({
    required List<Map<String, dynamic>> rows,
    required String myId,
    LedgerSnapshot? server,
  }) async {
    final baseline = await _store.read(myId);
    final first = evaluate(
      rows: rows,
      myId: myId,
      baseline: baseline,
      server: server,
    );
    await _store.write(first.nextCheckpoint);

    return IntegrityCheckResult(
      report: evaluate(
        rows: rows,
        myId: myId,
        baseline: first.nextCheckpoint,
        server: server,
      ).report,
      nextCheckpoint: first.nextCheckpoint,
    );
  }

  /// So khớp thuần logic, không chạm mạng — tách riêng để test được.
  IntegrityCheckResult evaluate({
    required List<Map<String, dynamic>> rows,
    required String myId,
    SyncCheckpoint? baseline,
    LedgerSnapshot? server,
    String? note,
  }) {
    final criticals = <IntegrityFinding>[];
    final warnings = <IntegrityFinding>[];
    final infos = <IntegrityFinding>[];

    void critical(String code, String title, String message, [String? id]) =>
        criticals.add(IntegrityFinding(
          severity: IntegritySeverity.critical,
          code: code,
          title: title,
          message: message,
          transactionId: id,
        ));
    void warn(String code, String title, String message, [String? id]) =>
        warnings.add(IntegrityFinding(
          severity: IntegritySeverity.warning,
          code: code,
          title: title,
          message: message,
          transactionId: id,
        ));
    void info(String code, String title, String message, [String? id]) =>
        infos.add(IntegrityFinding(
          severity: IntegritySeverity.info,
          code: code,
          title: title,
          message: message,
          transactionId: id,
        ));

    // ---------- 1. Kiểm tra từng dòng ----------
    final byId = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final id = LedgerMath.rowId(row);
      if (id == null) {
        critical('row_without_id', 'Dòng dữ liệu hỏng',
            'Có một giao dịch không có id hợp lệ nên không thể đối soát.');
        continue;
      }
      if (byId.containsKey(id)) {
        warn('duplicate_row', 'Giao dịch bị lặp',
            'Giao dịch $id xuất hiện nhiều lần trong dữ liệu trả về.', id);
      }
      byId[id] = row;

      final amount = row['amount'];
      if (amount is! num) {
        critical('invalid_amount', 'Số tiền không hợp lệ',
            'Giao dịch $id có số tiền không đọc được.', id);
      } else if (amount <= 0) {
        critical('non_positive_amount', 'Số tiền không dương',
            'Giao dịch $id có số tiền $amount, nhỏ hơn hoặc bằng 0.', id);
      }

      final status = row['status'];
      if (status is! String || !_knownStatuses.contains(status)) {
        critical('unknown_status', 'Trạng thái lạ',
            'Giao dịch $id có trạng thái "$status" nằm ngoài '
            'waiting/accepted/declined.', id);
      }

      final type = row['type'];
      if (type is! String || !_knownTypes.contains(type)) {
        warn('unknown_type', 'Loại giao dịch lạ',
            'Giao dịch $id có loại "$type" nằm ngoài debt/payment.', id);
      }

      if (row['created_by'] == row['recipient_id'] &&
          row['created_by'] != null) {
        critical('self_dealing', 'Giao dịch tự ghi cho chính mình',
            'Giao dịch $id có người tạo trùng người nhận.', id);
      }

      final respondedAt = row['responded_at'];
      if (status == 'accepted' && respondedAt == null) {
        warn('accepted_without_responded_at', 'Thiếu thời gian phản hồi',
            'Giao dịch $id đã accepted nhưng không có responded_at.', id);
      }
      if (status == 'waiting' && respondedAt != null) {
        warn('waiting_with_responded_at', 'Trạng thái không nhất quán',
            'Giao dịch $id còn waiting nhưng đã có responded_at.', id);
      }

      final createdAtRaw = row['created_at'];
      final createdAt =
          createdAtRaw is String ? DateTime.tryParse(createdAtRaw) : null;
      if (createdAt != null &&
          createdAt.isAfter(
              DateTime.now().toUtc().add(_clockSkewTolerance))) {
        info('created_at_in_future', 'Thời gian tạo ở tương lai',
            'Giao dịch $id có created_at $createdAtRaw, muộn hơn hiện tại.', id);
      }
    }

    // ---------- 2. So với mốc đối soát đã lưu ----------
    final databaseTracksVersions = rows.isEmpty
        ? true
        : rows.any(LedgerMath.hasVersionColumn);

    var changedSinceBaseline = 0;
    if (baseline == null) {
      info('baseline_created', 'Đã tạo mốc đối soát',
          'Lần kiểm tra đầu tiên: đã ghi lại trạng thái hiện tại làm mốc. '
          'Từ lần sau, mọi thay đổi ngoài luồng sẽ được phát hiện.');
    } else {
      if (!databaseTracksVersions) {
        warn('version_column_missing', 'Database chưa theo dõi phiên bản',
            'Chưa thấy cột version/updated_at. Hãy chạy migration '
            'ledger_integrity để phát hiện được cả các sửa đổi lặt vặt.');
      }

      for (final id in baseline.rows.keys) {
        if (!byId.containsKey(id)) {
          critical('row_deleted_out_of_band', 'Giao dịch bị xoá ngoài luồng',
              'Giao dịch $id có trong mốc đối soát nhưng đã biến mất khỏi '
              'database. Sổ nợ đang thiếu một dòng.', id);
        }
      }

      for (final entry in byId.entries) {
        final id = entry.key;
        final row = entry.value;
        final previous = baseline.rows[id];
        final fingerprint = LedgerMath.immutableFingerprint(row);
        final state = LedgerMath.stateSignature(row);
        final version = LedgerMath.versionOf(row);

        if (previous == null) {
          changedSinceBaseline++;
          continue;
        }

        if (previous.immutableHash != fingerprint) {
          changedSinceBaseline++;
          critical(
            'row_payload_changed',
            'Số tiền / nội dung bị sửa',
            'Giao dịch $id đã bị thay đổi ngoài app (số tiền, loại, người '
            'tạo/nhận, mô tả hoặc thời gian tạo). Database đã khoá các field '
            'này, nên đây là dấu hiệu dữ liệu bị can thiệp trực tiếp.',
            id,
          );
        } else if (databaseTracksVersions &&
            previous.version > 0 &&
            version < previous.version) {
          changedSinceBaseline++;
          critical('row_version_rollback', 'Phiên bản bị lùi',
              'Giao dịch $id có version $version, nhỏ hơn version '
              '${previous.version} đã ghi nhận.', id);
        } else if (previous.state != state) {
          final previousStatus = LedgerMath.statusOf(previous.state);
          final newStatus = LedgerMath.statusOf(state);
          final bumped = version > previous.version || !databaseTracksVersions;
          final legalTransition = previousStatus == 'waiting' &&
              (newStatus == 'accepted' || newStatus == 'declined');

          if (!bumped) {
            changedSinceBaseline++;
            critical(
              'state_changed_without_version_bump',
              'Trạng thái bị sửa không qua app',
              'Giao dịch $id đổi trạng thái "$previousStatus" -> "$newStatus" '
              'nhưng version không tăng. Thay đổi hợp lệ luôn làm version '
              'tăng, nên đây là dấu hiệu sửa trực tiếp trong database.',
              id,
            );
          } else if (!legalTransition) {
            changedSinceBaseline++;
            critical(
              'illegal_status_transition',
              'Chuyển trạng thái không hợp lệ',
              'Giao dịch $id chuyển "$previousStatus" -> "$newStatus". '
              'Chỉ cho phép waiting -> accepted/declined và chỉ một lần.',
              id,
            );
          } else {
            changedSinceBaseline++;
          }
        } else if (databaseTracksVersions &&
            previous.version > 0 &&
            version > previous.version) {
          // version tăng nhưng nội dung và trạng thái không đổi: vô hại.
          changedSinceBaseline++;
        }
      }
    }

    // ---------- 3. Đối chiếu số dư ----------
    final clientBalance = LedgerMath.computeRawBalance(rows, myId);

    if (server != null && server.totalCount != rows.length) {
      if (server.totalCount > rows.length) {
        critical(
          'server_row_count_mismatch',
          'Thiếu giao dịch so với server',
          'Server thấy ${server.totalCount} giao dịch, app chỉ đọc được '
          '${rows.length}. Có dòng bị thiếu hoặc không đọc được.',
        );
      } else {
        // Snapshot cũ hơn dữ liệu (giao dịch mới vừa được tạo xen vào giữa
        // hai lần gọi). Không phải bất thường, chỉ là lệch thời điểm.
        info(
          'server_snapshot_stale',
          'Snapshot server cũ hơn dữ liệu',
          'Server thấy ${server.totalCount} giao dịch, app đọc được '
          '${rows.length}. Bỏ qua phép đối chiếu số dư lần này.',
        );
      }
    }

    // Chỉ đối chiếu số dư / vân tay khi hai bên chắc chắn nhìn cùng một tập dòng.
    if (server != null && server.totalCount == rows.length) {
      if (server.netBalance != clientBalance) {
        critical(
          'balance_mismatch_server',
          'Số dư lệch so với server',
          'App tính $clientBalance, server tính ${server.netBalance}. '
          'Hai bên đọc cùng một tập dòng nên lệch nghĩa là có gì đó '
          'không nhất quán.',
        );
      }
      final baselineHash = baseline?.ledgerHash;
      if (baselineHash != null &&
          server.ledgerHash.isNotEmpty &&
          baselineHash != server.ledgerHash &&
          changedSinceBaseline == 0) {
        critical(
          'server_ledger_drift',
          'Sổ nợ đã accepted thay đổi',
          'Dấu vân tay sổ nợ trên server khác lần chốt mốc, nhưng không dòng '
          'nào giải thích được thay đổi đó.',
        );
      }
    }

    if (baseline != null &&
        changedSinceBaseline == 0 &&
        baseline.balance != clientBalance) {
      critical(
        'local_balance_drift',
        'Số dư lệch so với mốc đối soát',
        'Không có dòng nào thay đổi nhưng số dư tính lại là $clientBalance, '
        'khác mốc đã lưu ${baseline.balance}.',
      );
    }

    if (changedSinceBaseline > 0) {
      info('changes_since_baseline', 'Có thay đổi hợp lệ',
          '$changedSinceBaseline giao dịch đã thay đổi kể từ mốc đối soát '
          'gần nhất (tạo mới hoặc được xác nhận).');
    }

    final nextCheckpoint = SyncCheckpoint(
      userId: myId,
      syncedAt: DateTime.now(),
      maxUpdatedAt: server?.maxUpdatedAt ?? LedgerMath.maxUpdatedAt(rows),
      balance: clientBalance,
      rowCount: rows.length,
      ledgerHash: server?.ledgerHash ?? baseline?.ledgerHash,
      rows: {
        for (final entry in byId.entries)
          entry.key: RowFingerprint(
            immutableHash: LedgerMath.immutableFingerprint(entry.value),
            state: LedgerMath.stateSignature(entry.value),
            version: LedgerMath.versionOf(entry.value),
          ),
      },
    );

    return IntegrityCheckResult(
      report: IntegrityReport(
        checkedAt: DateTime.now(),
        hasBaseline: baseline != null,
        databaseTracksVersions: databaseTracksVersions,
        findings: [...criticals, ...warnings, ...infos],
        rowCount: rows.length,
        clientBalance: clientBalance,
        serverBalance: server?.netBalance,
        ledgerHash: server?.ledgerHash,
        changedSinceBaseline: changedSinceBaseline,
        note: note,
      ),
      nextCheckpoint: nextCheckpoint,
    );
  }
}
