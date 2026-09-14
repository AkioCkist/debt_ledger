import 'package:debt_ledger/models/integrity_report.dart';
import 'package:debt_ledger/models/ledger_snapshot.dart';
import 'package:debt_ledger/models/sync_checkpoint.dart';
import 'package:debt_ledger/services/integrity_service.dart';
import 'package:debt_ledger/services/ledger_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const me = '11111111-1111-1111-1111-111111111111';
const other = '22222222-2222-2222-2222-222222222222';

Map<String, dynamic> row({
  required String id,
  String createdBy = me,
  String recipientId = other,
  String type = 'debt',
  Object amount = 100000,
  String description = 'an trua',
  String status = 'accepted',
  String createdAt = '2026-09-01T10:00:00.000000+00:00',
  String? respondedAt = '2026-09-01T11:00:00.000000+00:00',
  String updatedAt = '2026-09-01T11:00:00.000000+00:00',
  Object? version = 2,
}) {
  return <String, dynamic>{
    'id': id,
    'created_by': createdBy,
    'recipient_id': recipientId,
    'type': type,
    'amount': amount,
    'description': description,
    'status': status,
    'created_at': createdAt,
    'responded_at': respondedAt,
    'updated_at': updatedAt,
    if (version != null) 'version': version,
  };
}

/// Chạy một lượt đối soát rồi trả về mốc mới, để test nối tiếp nhiều lượt.
SyncCheckpoint baselineOf(
  IntegrityService service,
  List<Map<String, dynamic>> rows, {
  SyncCheckpoint? previous,
  LedgerSnapshot? server,
}) {
  return service
      .evaluate(rows: rows, myId: me, baseline: previous, server: server)
      .nextCheckpoint;
}

Set<String> codesOf(IntegrityReport report) =>
    report.findings.map((f) => f.code).toSet();

List<IntegrityFinding> criticalsOf(IntegrityReport report) =>
    report.criticals.toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = IntegrityService();

  group('LedgerMath', () {
    test('cộng amount khi mình là người tạo, trừ khi mình là người nhận', () {
      final rows = [
        row(id: 'a', createdBy: me, recipientId: other, amount: 500000),
        row(id: 'b', createdBy: other, recipientId: me, amount: 200000),
      ];
      expect(LedgerMath.computeRawBalance(rows, me), 300000);
      expect(LedgerMath.computeRawBalance(rows, other), -300000);
    });

    test('bỏ qua giao dịch chưa accepted và amount không phải số', () {
      final rows = [
        row(id: 'a', amount: 500000),
        row(id: 'b', status: 'waiting', respondedAt: null, amount: 900000),
        row(id: 'c', amount: 'khong-phai-so'),
      ];
      expect(LedgerMath.computeRawBalance(rows, me), 500000);
    });

    test('vân tay đổi khi số tiền đổi, không phụ thuộc kiểu int/double', () {
      final asInt = row(id: 'a', amount: 1000000);
      final asDouble = row(id: 'a', amount: 1000000.0);
      final changed = row(id: 'a', amount: 2000000);

      expect(
        LedgerMath.immutableFingerprint(asInt),
        LedgerMath.immutableFingerprint(asDouble),
      );
      expect(
        LedgerMath.immutableFingerprint(asInt),
        isNot(LedgerMath.immutableFingerprint(changed)),
      );
    });

    test('vân tay không đổi khi chỉ trạng thái đổi (đổi hợp lệ)', () {
      final waiting = row(id: 'a', status: 'waiting', respondedAt: null);
      final accepted = row(id: 'a', status: 'accepted');
      expect(
        LedgerMath.immutableFingerprint(waiting),
        LedgerMath.immutableFingerprint(accepted),
      );
      expect(
        LedgerMath.stateSignature(waiting),
        isNot(LedgerMath.stateSignature(accepted)),
      );
    });
  });

  group('lượt kiểm tra đầu tiên', () {
    test('chỉ ghi mốc, không báo bất thường', () {
      final result = service.evaluate(
        rows: [row(id: 'a'), row(id: 'b')],
        myId: me,
      );
      expect(result.report.isTrusted, isTrue);
      expect(result.report.hasBaseline, isFalse);
      expect(codesOf(result.report), contains('baseline_created'));
      expect(result.nextCheckpoint.rowCount, 2);
      expect(result.nextCheckpoint.balance, 200000);
    });
  });

  group('không có gì thay đổi', () {
    test('dữ liệu y nguyên thì không có phát hiện nào', () {
      final rows = [row(id: 'a'), row(id: 'b')];
      final baseline = baselineOf(service, rows);
      final result = service.evaluate(
        rows: rows,
        myId: me,
        baseline: baseline,
      );
      expect(result.report.findings, isEmpty);
      expect(result.report.changedSinceBaseline, 0);
      expect(result.report.isTrusted, isTrue);
    });
  });

  group('phát hiện sửa ngoài luồng', () {
    test('số tiền bị sửa thì báo động', () {
      final baseline = baselineOf(service, [row(id: 'a', amount: 100000)]);
      final result = service.evaluate(
        rows: [row(id: 'a', amount: 999000)],
        myId: me,
        baseline: baseline,
      );
      expect(codesOf(result.report), contains('row_payload_changed'));
      expect(result.report.isTrusted, isFalse);
      expect(result.report.criticalCount, 1);
    });

    test('sửa mô tả hoặc loại giao dịch cũng bị phát hiện', () {
      final baseline = baselineOf(service, [row(id: 'a')]);
      final result = service.evaluate(
        rows: [row(id: 'a', type: 'payment', description: 'sua trom')],
        myId: me,
        baseline: baseline,
      );
      expect(codesOf(result.report), contains('row_payload_changed'));
    });

    test('version bị lùi thì báo động', () {
      final baseline = baselineOf(service, [row(id: 'a', version: 4)]);
      final result = service.evaluate(
        rows: [row(id: 'a', version: 3)],
        myId: me,
        baseline: baseline,
      );
      expect(codesOf(result.report), contains('row_version_rollback'));
    });

    test('giao dịch biến mất khỏi database thì báo động', () {
      final baseline = baselineOf(service, [row(id: 'a'), row(id: 'b')]);
      final result = service.evaluate(
        rows: [row(id: 'a')],
        myId: me,
        baseline: baseline,
      );
      expect(codesOf(result.report), contains('row_deleted_out_of_band'));
    });

    test('đổi trạng thái mà version không tăng thì báo động', () {
      final baseline = baselineOf(
        service,
        [row(id: 'a', status: 'accepted', version: 2)],
      );
      final result = service.evaluate(
        rows: [row(id: 'a', status: 'declined', version: 2)],
        myId: me,
        baseline: baseline,
      );
      expect(
        codesOf(result.report),
        contains('state_changed_without_version_bump'),
      );
    });

    test('chuyển trạng thái ngược accepted -> declined thì báo động', () {
      final baseline = baselineOf(
        service,
        [row(id: 'a', status: 'accepted', version: 2)],
      );
      final result = service.evaluate(
        rows: [row(id: 'a', status: 'declined', version: 3)],
        myId: me,
        baseline: baseline,
      );
      expect(codesOf(result.report), contains('illegal_status_transition'));
    });
  });

  group('thay đổi hợp lệ', () {
    test('xác nhận invoice waiting -> accepted là bình thường', () {
      final baseline = baselineOf(
        service,
        [row(id: 'a', status: 'waiting', respondedAt: null, version: 1)],
      );
      final result = service.evaluate(
        rows: [row(id: 'a', status: 'accepted', version: 2)],
        myId: me,
        baseline: baseline,
      );
      expect(criticalsOf(result.report), isEmpty);
      expect(result.report.changedSinceBaseline, 1);
      expect(result.report.isTrusted, isTrue);
    });

    test('có giao dịch mới là bình thường', () {
      final baseline = baselineOf(service, [row(id: 'a')]);
      final result = service.evaluate(
        rows: [row(id: 'a'), row(id: 'b', version: 1)],
        myId: me,
        baseline: baseline,
      );
      expect(criticalsOf(result.report), isEmpty);
      expect(result.report.changedSinceBaseline, 1);
    });
  });

  group('đối chiếu với số dư server tính', () {
    LedgerSnapshot serverSnapshot({required int total, required num balance}) {
      return LedgerSnapshot(
        totalCount: total,
        acceptedCount: total,
        pendingCount: 0,
        declinedCount: 0,
        maxVersion: 2,
        netBalance: balance,
        ledgerHash: 'hash-a',
      );
    }

    test('lệch số dư thì báo động', () {
      final rows = [row(id: 'a', amount: 100000)];
      final result = service.evaluate(
        rows: rows,
        myId: me,
        server: serverSnapshot(total: 1, balance: 123456),
      );
      expect(codesOf(result.report), contains('balance_mismatch_server'));
    });

    test('server thấy nhiều dòng hơn thì báo động', () {
      final result = service.evaluate(
        rows: [row(id: 'a', amount: 100000)],
        myId: me,
        server: serverSnapshot(total: 5, balance: 100000),
      );
      expect(codesOf(result.report), contains('server_row_count_mismatch'));
    });

    test('snapshot cũ hơn dữ liệu chỉ là thông tin, không báo động', () {
      final result = service.evaluate(
        rows: [row(id: 'a', amount: 100000), row(id: 'b', amount: 5000)],
        myId: me,
        server: serverSnapshot(total: 1, balance: 100000),
      );
      expect(criticalsOf(result.report), isEmpty);
      expect(codesOf(result.report), contains('server_snapshot_stale'));
    });

    test('dấu vân tay sổ nợ đổi mà không dòng nào giải thích thì báo động', () {
      final rows = [row(id: 'a', amount: 100000)];
      final first = service.evaluate(
        rows: rows,
        myId: me,
        server: serverSnapshot(total: 1, balance: 100000),
      );
      expect(first.nextCheckpoint.ledgerHash, 'hash-a');

      final second = service.evaluate(
        rows: rows,
        myId: me,
        baseline: first.nextCheckpoint,
        server: const LedgerSnapshot(
          totalCount: 1,
          acceptedCount: 1,
          pendingCount: 0,
          declinedCount: 0,
          maxVersion: 2,
          netBalance: 100000,
          ledgerHash: 'hash-b',
        ),
      );
      expect(codesOf(second.report), contains('server_ledger_drift'));
    });
  });

  group('dữ liệu hỏng', () {
    test('số tiền không dương', () {
      final result = service.evaluate(rows: [row(id: 'a', amount: 0)], myId: me);
      expect(codesOf(result.report), contains('non_positive_amount'));
    });

    test('tự ghi nợ cho chính mình', () {
      final result = service.evaluate(
        rows: [row(id: 'a', createdBy: me, recipientId: me)],
        myId: me,
      );
      expect(codesOf(result.report), contains('self_dealing'));
    });

    test('trạng thái lạ không làm crash và bị báo động', () {
      final result = service.evaluate(
        rows: [row(id: 'a', status: 'something-else')],
        myId: me,
      );
      expect(codesOf(result.report), contains('unknown_status'));
    });

    test('thiếu cột version thì chỉ cảnh báo, vẫn đối soát được', () {
      final rows = [row(id: 'a', version: null)];
      final baseline = baselineOf(service, rows);
      final result = service.evaluate(
        rows: rows,
        myId: me,
        baseline: baseline,
      );
      expect(codesOf(result.report), contains('version_column_missing'));
      expect(criticalsOf(result.report), isEmpty);
      expect(result.report.databaseTracksVersions, isFalse);
    });

    test('số dư lệch mốc dù không dòng nào đổi', () {
      final rows = [row(id: 'a', amount: 100000)];
      final baseline = baselineOf(service, rows);
      final tampered = SyncCheckpoint(
        userId: baseline.userId,
        syncedAt: baseline.syncedAt,
        balance: 999999,
        rowCount: baseline.rowCount,
        rows: baseline.rows,
        ledgerHash: baseline.ledgerHash,
      );
      final result = service.evaluate(
        rows: rows,
        myId: me,
        baseline: tampered,
      );
      expect(codesOf(result.report), contains('local_balance_drift'));
    });
  });

  group('mốc đối soát lưu trên máy', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('checkRows tự chốt mốc khi dữ liệu sạch, và báo động khi mốc bị lệch', () async {
      final rows = [row(id: 'a', amount: 100000)];

      final first = await service.checkRows(rows: rows, myId: me);
      expect(first.report.hasBaseline, isFalse);

      final clean = await service.checkRows(rows: rows, myId: me);
      expect(clean.report.hasBaseline, isTrue);
      expect(clean.report.findings, isEmpty);

      // Sửa số tiền ngoài luồng: mốc cũ vẫn còn nên phải bị phát hiện...
      final tampered = await service.checkRows(
        rows: [row(id: 'a', amount: 1)],
        myId: me,
      );
      expect(codesOf(tampered.report), contains('row_payload_changed'));

      // ...và mốc hỏng không được ghi đè, lần sau vẫn còn cảnh báo.
      final again = await service.checkRows(
        rows: [row(id: 'a', amount: 1)],
        myId: me,
      );
      expect(codesOf(again.report), contains('row_payload_changed'));

      // Người dùng xem rồi chốt lại: mốc mới lấy dữ liệu hiện tại làm chuẩn.
      final accepted = await service.acceptCurrentState(
        rows: [row(id: 'a', amount: 1)],
        myId: me,
      );
      expect(accepted.report.findings, isEmpty);

      final after = await service.checkRows(
        rows: [row(id: 'a', amount: 1)],
        myId: me,
      );
      expect(after.report.findings, isEmpty);
      expect(after.report.changedSinceBaseline, 0);
    });

    test('lỗi đọc mốc không làm crash', () async {
      SharedPreferences.setMockInitialValues({
        'debt_ledger.integrity.checkpoint.$me': '{{{ khong phai json',
      });
      final result = await service.checkRows(
        rows: [row(id: 'a')],
        myId: me,
      );
      expect(result.report.hasBaseline, isFalse);
      expect(codesOf(result.report), contains('baseline_created'));
    });

    test('mã hoá rồi đọc lại giữ nguyên dữ liệu', () {
      final checkpoint = SyncCheckpoint(
        userId: me,
        syncedAt: DateTime.parse('2026-09-14T09:30:00.000'),
        maxUpdatedAt: '2026-09-14T09:00:00.000000+00:00',
        balance: 123456,
        rowCount: 1,
        ledgerHash: 'abc',
        rows: {
          'a': const RowFingerprint(
            immutableHash: 'h1',
            state: 'accepted|2026-09-14T09:00:00.000000+00:00',
            version: 3,
          ),
        },
      );

      final restored = SyncCheckpoint.fromJson(checkpoint.encode())!;
      expect(restored.userId, me);
      expect(restored.balance, 123456);
      expect(restored.ledgerHash, 'abc');
      expect(restored.rows['a']!.version, 3);
      expect(restored.rows['a']!.immutableHash, 'h1');
    });

    test('chuỗi hỏng thì trả về null thay vì crash', () {
      expect(SyncCheckpoint.fromJson('khong-phai-json'), isNull);
    });
  });
}
