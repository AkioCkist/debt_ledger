import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/debt_transaction.dart';

class TransactionService {
  final SupabaseClient _client = Supabase.instance.client;

  /// Realtime stream toàn bộ giao dịch liên quan đến người dùng hiện tại.
  /// RLS đã giới hạn chỉ trả về dòng mà auth.uid() là người tạo hoặc người nhận,
  /// nên không cần lọc thêm ở phía client.
  Stream<List<DebtTransaction>> streamMyTransactions() {
    return streamMyTransactionRows().map(
      (rows) => rows.map((row) => DebtTransaction.fromMap(row)).toList(),
    );
  }

  /// Như [streamMyTransactions] nhưng trả về row thô, để phần đối soát
  /// còn kiểm tra được cả các field mà model bỏ qua (version, updated_at,
  /// giá trị lạ của status/type).
  Stream<List<Map<String, dynamic>>> streamMyTransactionRows() {
    return _client
        .from('transactions')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);
  }

  /// Toàn bộ giao dịch đọc một lần (dùng khi cần dữ liệu mới nhất để đối soát).
  Future<List<Map<String, dynamic>>> fetchTransactionRows() async {
    final rows = await _client
        .from('transactions')
        .select()
        .order('created_at', ascending: false);
    return rows.cast<Map<String, dynamic>>();
  }

  /// Các giao dịch đã thay đổi kể từ mốc thời gian cho trước, dựa trên
  /// `updated_at` do trigger phía database ghi.
  Future<List<Map<String, dynamic>>> fetchChangedSince(DateTime since) async {
    final rows = await _client
        .from('transactions')
        .select()
        .gt('updated_at', since.toUtc().toIso8601String())
        .order('updated_at', ascending: false);
    return rows.cast<Map<String, dynamic>>();
  }

  Future<void> createInvoice({
    required String createdBy,
    required String recipientId,
    required TxType type,
    required num amount,
    required String description,
  }) async {
    await _client.from('transactions').insert({
      'created_by': createdBy,
      'recipient_id': recipientId,
      'type': type.name,
      'amount': amount,
      'description': description.trim(),
    });
  }

  Future<void> respond({
    required String transactionId,
    required TxStatus status,
  }) async {
    assert(status == TxStatus.accepted || status == TxStatus.declined);
    await _client
        .from('transactions')
        .update({'status': status.name})
        .eq('id', transactionId);
  }
}
