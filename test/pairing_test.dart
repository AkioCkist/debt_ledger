import 'package:debt_ledger/models/app_profile.dart';
import 'package:debt_ledger/models/connection.dart';
import 'package:debt_ledger/services/ledger_math.dart';
import 'package:debt_ledger/utils/pairing_code.dart';
import 'package:debt_ledger/utils/pairing_error.dart';
import 'package:flutter_test/flutter_test.dart';

const _me = 'me-0000';
const _an = 'an-1111';
const _binh = 'binh-2222';
const _chi = 'chi-3333';

AppProfile profile(String id, String name) =>
    AppProfile(id: id, displayName: name, email: '$name@example.com');

DebtConnection connection({
  required String id,
  required String requester,
  required String addressee,
  ConnectionStatus status = ConnectionStatus.pending,
  DateTime? createdAt,
}) {
  return DebtConnection(
    id: id,
    requesterId: requester,
    addresseeId: addressee,
    status: status,
    createdAt: createdAt ?? DateTime(2026, 9, 16, 10),
  );
}

Map<String, dynamic> row({
  required String id,
  required String createdBy,
  required String recipientId,
  required num amount,
  String status = 'accepted',
}) {
  return {
    'id': id,
    'created_by': createdBy,
    'recipient_id': recipientId,
    'type': 'debt',
    'amount': amount,
    'status': status,
  };
}

void main() {
  group('PairingCode.normalize', () {
    test('đưa về chữ hoa và bỏ khoảng trắng, gạch', () {
      expect(PairingCode.normalize('abcd2345'), 'ABCD2345');
      expect(PairingCode.normalize(' ABCD 2345 '), 'ABCD2345');
      expect(PairingCode.normalize('ABCD-2345'), 'ABCD2345');
    });

    test('loại ký tự ngoài bảng chữ (I, O, 0, 1)', () {
      // Bảng chữ bỏ I/O/0/1 để đọc - gõ không nhầm.
      expect(PairingCode.normalize('ABCD23O5'), isNull);
      expect(PairingCode.normalize('ABCD23I5'), isNull);
      expect(PairingCode.normalize('ABCD2305'), isNull);
      expect(PairingCode.normalize('ABCD2315'), isNull);
    });

    test('sai độ dài thì không hợp lệ', () {
      expect(PairingCode.normalize('ABCD234'), isNull);
      expect(PairingCode.normalize('ABCD23456'), isNull);
      expect(PairingCode.normalize(''), isNull);
      expect(PairingCode.normalize(null), isNull);
    });
  });

  group('PairingCode và QR', () {
    test('payload QR đi và về đúng mã', () {
      final payload = PairingCode.toQrPayload('abcd2345');
      expect(payload, 'sono://pair?code=ABCD2345');
      expect(PairingCode.fromQrPayload(payload), 'ABCD2345');
    });

    test('chấp nhận cả chuỗi mã trần', () {
      expect(PairingCode.fromQrPayload('ABCD 2345'), 'ABCD2345');
    });

    test('payload rác trả về null', () {
      expect(PairingCode.fromQrPayload('https://example.com/abc'), isNull);
      expect(PairingCode.fromQrPayload('hẹn gặp ở quán'), isNull);
      expect(PairingCode.fromQrPayload(''), isNull);
      expect(PairingCode.fromQrPayload(null), isNull);
    });

    test('chia nhóm cho dễ đọc', () {
      expect(PairingCode.formatForDisplay('abcd2345'), 'ABCD 2345');
    });
  });

  group('pairingErrorMessage', () {
    test('dịch đúng các mã lỗi của RPC', () {
      expect(
        pairingErrorMessage('PostgrestException(message: PAIR_CODE_INVALID)'),
        contains('hết hạn'),
      );
      expect(
        pairingErrorMessage('PostgrestException(message: PAIR_CODE_SELF)'),
        contains('chính bạn'),
      );
      expect(
        pairingErrorMessage('PostgrestException(message: ALREADY_CONNECTED)'),
        contains('đã là bạn nợ'),
      );
      expect(
        pairingErrorMessage('PostgrestException(message: PAIR_REQUEST_EXISTS)'),
        contains('lời mời'),
      );
    });

    test('lỗi lạ vẫn có thông báo', () {
      expect(pairingErrorMessage('SocketException'), isNotEmpty);
      expect(pairingErrorMessage(null), isNotEmpty);
    });
  });

  group('ContactBook.from', () {
    test('tách đúng danh bạ / lời mời đến / lời mời đã gửi', () {
      final book = ContactBook.from(
        myId: _me,
        connections: [
          connection(
            id: 'c1',
            requester: _me,
            addressee: _an,
            status: ConnectionStatus.accepted,
          ),
          connection(id: 'c2', requester: _binh, addressee: _me),
          connection(id: 'c3', requester: _me, addressee: _chi),
        ],
        profiles: {
          _an: profile(_an, 'An'),
          _binh: profile(_binh, 'Bình'),
          _chi: profile(_chi, 'Chi'),
        },
      );

      expect(book.contacts.map((c) => c.profile.id), [_an]);
      expect(book.incoming.map((c) => c.profile.id), [_binh]);
      expect(book.outgoing.map((c) => c.profile.id), [_chi]);
      expect(book.isEmpty, isFalse);
    });

    test('bỏ qua lời mời đã từ chối và hồ sơ không đọc được', () {
      final book = ContactBook.from(
        myId: _me,
        connections: [
          connection(
            id: 'c1',
            requester: _me,
            addressee: _an,
            status: ConnectionStatus.declined,
          ),
          connection(
            id: 'c2',
            requester: _binh,
            addressee: _me,
            status: ConnectionStatus.accepted,
          ),
        ],
        // Bình không có trong bản đồ hồ sơ (bị xoá, hoặc chưa tải kịp).
        profiles: {_an: profile(_an, 'An')},
      );

      expect(book.contacts, isEmpty);
      expect(book.incoming, isEmpty);
      expect(book.outgoing, isEmpty);
    });

    test('tên riêng chỉ áp cho phía mình đặt', () {
      final connectionAn = connection(
        id: 'c1',
        requester: _me,
        addressee: _an,
        status: ConnectionStatus.accepted,
      );
      final profiles = {_an: profile(_an, 'An Nguyễn')};

      final mine = ContactBook.from(
        myId: _me,
        connections: [connectionAn],
        profiles: profiles,
        aliases: {_an: 'Anh An'},
      );
      expect(mine.contacts.single.displayName, 'Anh An');

      // Phía An không có alias nào cho mình nên vẫn dùng tên hồ sơ.
      final theirs = ContactBook.from(
        myId: _an,
        connections: [connectionAn],
        profiles: {_me: profile(_me, 'Tôi')},
        aliases: const {},
      );
      expect(theirs.contacts.single.displayName, 'Tôi');
    });

    test('danh bạ sắp theo tên hiển thị, không phân biệt hoa thường', () {
      final book = ContactBook.from(
        myId: _me,
        connections: [
          connection(
            id: 'c1',
            requester: _me,
            addressee: _binh,
            status: ConnectionStatus.accepted,
          ),
          connection(
            id: 'c2',
            requester: _me,
            addressee: _an,
            status: ConnectionStatus.accepted,
          ),
        ],
        profiles: {
          _an: profile(_an, 'an'),
          _binh: profile(_binh, 'Bình'),
        },
      );

      expect(book.contacts.map((c) => c.displayName), ['an', 'Bình']);
    });
  });

  group('tách sổ nợ theo từng bạn nợ', () {
    final rows = [
      row(id: 't1', createdBy: _me, recipientId: _an, amount: 100),
      row(id: 't2', createdBy: _an, recipientId: _me, amount: 40),
      row(id: 't3', createdBy: _me, recipientId: _binh, amount: 500),
      row(id: 't4', createdBy: _me, recipientId: _an, amount: 999, status: 'waiting'),
    ];

    test('chỉ lấy giao dịch giữa đúng hai người', () {
      final withAn = rows.where((r) => LedgerMath.rawBetween(r, _me, _an));
      expect(withAn.map((r) => r['id']), ['t1', 't2', 't4']);

      final withBinh = rows.where((r) => LedgerMath.rawBetween(r, _me, _binh));
      expect(withBinh.map((r) => r['id']), ['t3']);
    });

    test('số dư tính riêng từng người, bỏ qua giao dịch chưa accepted', () {
      final withAn = rows
          .where((r) => LedgerMath.rawBetween(r, _me, _an))
          .toList();
      // 100 (An nợ mình) - 40 (mình trả An) = 60; t4 còn waiting nên không tính.
      expect(LedgerMath.computeRawBalance(withAn, _me), 60);

      final withBinh = rows
          .where((r) => LedgerMath.rawBetween(r, _me, _binh))
          .toList();
      expect(LedgerMath.computeRawBalance(withBinh, _me), 500);
    });
  });
}
