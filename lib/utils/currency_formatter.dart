import 'package:intl/intl.dart';

class CurrencyFormatter {
  CurrencyFormatter._();

  static final NumberFormat _formatter = NumberFormat.decimalPattern('vi_VN');

  /// Ví dụ: 1500000 -> "1.500.000 đ"
  static String format(num amount) {
    return '${_formatter.format(amount)} \u0111';
  }

  /// Ví dụ: 1500000 -> "+1.500.000 đ" hoặc "-1.500.000 đ"
  static String formatSigned(num amount, {required bool positive}) {
    final sign = positive ? '+' : '-';
    return '$sign${_formatter.format(amount.abs())} \u0111';
  }

  /// Chuyển chuỗi người dùng nhập (có thể có dấu chấm phân cách) thành số.
  static num? parse(String input) {
    final cleaned = input.replaceAll('.', '').replaceAll(',', '').trim();
    if (cleaned.isEmpty) return null;
    return num.tryParse(cleaned);
  }
}
