import 'package:intl/intl.dart';

import 'phone.dart';

/// العملة وعدد الخانات العشرية تُضبط من الإعدادات عند التشغيل.
class Money {
  static String symbol = 'ج.م';
  static String code = 'EGP';
  static int decimals = 2;

  /// الخانات العشرية الرسمية للعملات (لبوابات الدفع التي تطلب المبلغ بأصغر وحدة)
  static const _minorUnits = {
    'KWD': 3, 'BHD': 3, 'OMR': 3, 'JOD': 3, 'TND': 3, 'LYD': 3, 'IQD': 0,
    'JPY': 0, 'KRW': 0,
  };

  static int minorUnitsOf(String currency) => _minorUnits[currency.toUpperCase()] ?? 2;

  static void configure({required String code, required String symbol}) {
    Money.code = code.toUpperCase();
    Money.symbol = symbol;
    decimals = minorUnitsOf(code) == 3 ? 3 : 2;
  }
}

double roundMoney(num v, [int? decimals]) {
  final d = decimals ?? Money.decimals;
  final f = d == 3 ? 1000 : (d == 0 ? 1 : 100);
  return (v * f).roundToDouble() / f;
}

/// 1,250 ج.م  أو 1,250.50 ج.م (الكسور تظهر فقط عند وجودها)
String fmtMoney(num v, {bool symbol = true}) {
  final r = roundMoney(v);
  final whole = r == r.truncateToDouble();
  final pattern = whole ? '#,##0' : (Money.decimals == 3 ? '#,##0.000' : '#,##0.00');
  final s = NumberFormat(pattern, 'en').format(r);
  return symbol ? '$s ${Money.symbol}' : s;
}

String fmtNum(num v) => NumberFormat('#,##0.##', 'en').format(v);

/// قراءة رقم أدخله المستخدم (يقبل الأرقام العربية والفاصلة العربية)
double? parseAmount(String? s) {
  if (s == null) return null;
  var t = normalizeDigits(s.trim());
  t = t.replaceAll('٫', '.').replaceAll('،', '').replaceAll(',', '');
  if (t.isEmpty) return null;
  return double.tryParse(t);
}
