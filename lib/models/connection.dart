import 'app_profile.dart';

enum ConnectionStatus {
  pending,
  accepted,
  declined;

  static ConnectionStatus fromString(String value) {
    return ConnectionStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ConnectionStatus.pending,
    );
  }
}

/// Một dòng trong bảng `connections`: quan hệ giữa mình và một người khác.
/// Mỗi cặp người chỉ có đúng một dòng suốt đời (unique index ở database),
/// nên `status` là trạng thái hiện tại của quan hệ đó.
class DebtConnection {
  final String id;
  final String requesterId;
  final String addresseeId;
  final ConnectionStatus status;
  final DateTime createdAt;
  final DateTime? respondedAt;

  const DebtConnection({
    required this.id,
    required this.requesterId,
    required this.addresseeId,
    required this.status,
    required this.createdAt,
    this.respondedAt,
  });

  factory DebtConnection.fromMap(Map<String, dynamic> map) {
    final respondedAt = map['responded_at'];
    return DebtConnection(
      id: map['id'] as String,
      requesterId: map['requester_id'] as String,
      addresseeId: map['addressee_id'] as String,
      status: ConnectionStatus.fromString(map['status'] as String),
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
      respondedAt: respondedAt is String
          ? DateTime.parse(respondedAt).toLocal()
          : null,
    );
  }

  bool get isPending => status == ConnectionStatus.pending;
  bool get isAccepted => status == ConnectionStatus.accepted;
  bool get isDeclined => status == ConnectionStatus.declined;

  bool involves(String uid) => requesterId == uid || addresseeId == uid;

  /// Id của người còn lại trong quan hệ này.
  String otherId(String myId) =>
      requesterId == myId ? addresseeId : requesterId;

  /// Mình là người gửi lời mời (đang chờ người kia trả lời).
  bool isOutgoingFor(String myId) => isPending && requesterId == myId;

  /// Mình là người nhận lời mời (cần đồng ý / từ chối).
  bool isIncomingFor(String myId) => isPending && addresseeId == myId;
}

/// Một ô trong danh bạ: hồ sơ người kia + tên riêng mình đặt cho họ.
class ContactEntry {
  final AppProfile profile;

  /// Tên riêng chỉ lưu phía mình (bảng `contact_aliases`). Null = dùng tên gốc.
  final String? alias;

  final DebtConnection connection;

  const ContactEntry({
    required this.profile,
    required this.connection,
    this.alias,
  });

  String get displayName {
    final value = alias?.trim();
    if (value != null && value.isNotEmpty) return value;
    return profile.displayName;
  }
}

/// Kết quả ghép `connections` + `profiles` + `contact_aliases` thành sảnh.
///
/// Tách thành hàm thuần để test được mà không cần Supabase.
class ContactBook {
  /// Đã pair (danh bạ), sắp theo tên hiển thị.
  final List<ContactEntry> contacts;

  /// Lời mời người khác gửi cho mình, đang chờ mình trả lời (mới nhất trước).
  final List<ContactEntry> incoming;

  /// Lời mời mình đã gửi, đang chờ người kia trả lời (mới nhất trước).
  final List<ContactEntry> outgoing;

  const ContactBook({
    required this.contacts,
    required this.incoming,
    required this.outgoing,
  });

  static const empty = ContactBook(
    contacts: [],
    incoming: [],
    outgoing: [],
  );

  bool get isEmpty => contacts.isEmpty && incoming.isEmpty && outgoing.isEmpty;

  static ContactBook from({
    required String myId,
    required List<DebtConnection> connections,
    required Map<String, AppProfile> profiles,
    Map<String, String> aliases = const {},
  }) {
    final contacts = <ContactEntry>[];
    final incoming = <ContactEntry>[];
    final outgoing = <ContactEntry>[];

    for (final connection in connections) {
      if (!connection.involves(myId)) continue;
      if (connection.isDeclined) continue;

      final otherId = connection.otherId(myId);
      final profile = profiles[otherId];
      // Không thấy hồ sơ (bị xoá, hoặc policy chưa cho đọc) thì bỏ qua ô đó
      // thay vì hiện một ô không tên.
      if (profile == null) continue;

      final entry = ContactEntry(
        profile: profile,
        alias: aliases[otherId],
        connection: connection,
      );

      if (connection.isAccepted) {
        contacts.add(entry);
      } else if (connection.isIncomingFor(myId)) {
        incoming.add(entry);
      } else if (connection.isOutgoingFor(myId)) {
        outgoing.add(entry);
      }
    }

    contacts.sort(
      (a, b) => a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          ),
    );
    incoming.sort((a, b) => b.connection.createdAt.compareTo(a.connection.createdAt));
    outgoing.sort((a, b) => b.connection.createdAt.compareTo(a.connection.createdAt));

    return ContactBook(
      contacts: contacts,
      incoming: incoming,
      outgoing: outgoing,
    );
  }
}
