/// توحيد أرقام الجوال للصيغة الدولية بدون + (مثل 201001234567) لأن واتساب ومزودي الرسائل يحتاجونها هكذا.
library;

String digitsOnly(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    // الأرقام العربية/الهندية ٠-٩ و الفارسية ۰-۹
    if (r >= 0x30 && r <= 0x39) {
      b.writeCharCode(r);
    } else if (r >= 0x660 && r <= 0x669) {
      b.writeCharCode(0x30 + r - 0x660);
    } else if (r >= 0x6F0 && r <= 0x6F9) {
      b.writeCharCode(0x30 + r - 0x6F0);
    }
  }
  return b.toString();
}

/// تحويل الأرقام العربية/الهندية (٠-٩) والفارسية (۰-۹) إلى أرقام عادية مع إبقاء باقي النص
String normalizeDigits(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    if (r >= 0x660 && r <= 0x669) {
      b.writeCharCode(0x30 + r - 0x660);
    } else if (r >= 0x6F0 && r <= 0x6F9) {
      b.writeCharCode(0x30 + r - 0x6F0);
    } else {
      b.writeCharCode(r);
    }
  }
  return b.toString();
}

/// عدد صحيح يكتبه المستخدم (يقبل الأرقام العربية). null إن لم يكن رقماً
int? parseIntInput(String? s) => s == null ? null : int.tryParse(normalizeDigits(s).trim());

/// 01001234567 مع رمز الدولة 20 ← 201001234567 . الأرقام التي تبدأ بـ + أو 00 تبقى كما هي.
String? normalizePhone(String? phone, String countryCode) {
  if (phone == null) return null;
  final raw = phone.trim();
  var digits = digitsOnly(raw);
  if (digits.isEmpty) return null;
  final cc = digitsOnly(countryCode);
  if (raw.startsWith('+')) return digits;
  if (digits.startsWith('00')) return digits.substring(2);
  if (digits.startsWith('0')) return cc + digits.substring(1);
  if (cc.isNotEmpty && digits.startsWith(cc) && digits.length > 10) return digits;
  return cc + digits;
}

bool looksLikePhone(String? s) => s != null && digitsOnly(s).length >= 7;
