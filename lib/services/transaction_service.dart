import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/debt_transaction.dart';

class TransactionService {
  final SupabaseClient _client = Supabase.instance.client;

  /// Realtime stream toàn bộ giao dịch liên quan đến người dùng hiện tại.
  /// RLS đã giới hạn chỉ trả về dòng mà auth.uid() là người tạo hoặc người nhận,
  /// nên không cần lọc thêm ở phía client.
  Stream<List<DebtTransaction>> streamMyTransactions() {
    return _client
        .from('transactions')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map(
          (rows) => rows.map((row) => DebtTransaction.fromMap(row)).toList(),
        );
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
