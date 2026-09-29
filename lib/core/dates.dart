/// أدوات التواريخ: الاشتراكات تُحسب بالأيام (تاريخ بدون وقت)، و«تاريخ الانتهاء» هو آخر يوم مسموح فيه بالدخول.
library;

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// 2026-09-29
String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${_pad2(d.month)}-${_pad2(d.day)}';

DateTime parseDay(String s) {
  final p = s.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2].substring(0, 2)));
}

DateTime? tryParseDay(String? s) {
  if (s == null || s.isEmpty) return null;
  try {
    return parseDay(s);
  } catch (_) {
    return null;
  }
}

String _pad2(int v) => v.toString().padLeft(2, '0');

String hhmm(int minutes) => '${_pad2(minutes ~/ 60)}:${_pad2(minutes % 60)}';

int minutesOfDay(DateTime d) => d.hour * 60 + d.minute;

String timeKey(DateTime d) => '${dayKey(d)} ${_pad2(d.hour)}:${_pad2(d.minute)}';

/// عدد الأيام من a إلى b (بالتقويم، بدون أثر التوقيت الصيفي)
int daysBetween(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

/// إضافة أشهر مع ضبط نهاية الشهر: 31 يناير + شهر = 28/29 فبراير. يرجع أيضاً إن حصل الضبط.
(DateTime, bool) addMonthsClamped(DateTime d, int months) {
  final total = d.month - 1 + months;
  final y = d.year + (total / 12).floor();
  final m = total % 12 + 1;
  final last = DateTime(y, m + 1, 0).day;
  if (d.day > last) return (DateTime(y, m, last), true);
  return (DateTime(y, m, d.day), false);
}

enum DurationUnit { day, week, month, year }

DurationUnit durationUnitFrom(String? s) =>
    DurationUnit.values.firstWhere((u) => u.name == s, orElse: () => DurationUnit.month);

/// آخر يوم في اشتراك يبدأ في [start] ومدته [value] [unit]:
/// شهر من 29 سبتمبر ينتهي 28 أكتوبر، وشهر من 31 يناير ينتهي آخر فبراير.
DateTime periodEnd(DateTime start, int value, DurationUnit unit) {
  start = dateOnly(start);
  if (value <= 0) return start;
  switch (unit) {
    case DurationUnit.day:
      return addDays(start, value - 1);
    case DurationUnit.week:
      return addDays(start, value * 7 - 1);
    case DurationUnit.month:
    case DurationUnit.year:
      final months = unit == DurationUnit.year ? value * 12 : value;
      final (d, clamped) = addMonthsClamped(start, months);
      return clamped ? d : addDays(d, -1);
  }
}

/// أسماء أيام الأسبوع حسب DateTime.weekday (1 = الاثنين ... 7 = الأحد)
const weekdayNamesAr = {
  1: 'الاثنين',
  2: 'الثلاثاء',
  3: 'الأربعاء',
  4: 'الخميس',
  5: 'الجمعة',
  6: 'السبت',
  7: 'الأحد',
};
const weekdayNamesEn = {1: 'Mon', 2: 'Tue', 3: 'Wed', 4: 'Thu', 5: 'Fri', 6: 'Sat', 7: 'Sun'};

/// ترتيب أيام الأسبوع كما يراه المستخدم العربي (يبدأ بالسبت)
const weekOrder = [6, 7, 1, 2, 3, 4, 5];

/// مدى زمني يُعرض بترتيب صحيح داخل النص العربي، مثل 06:00–14:00
String hhmmRange(int from, int to) => '\u2066${hhmm(from)}\u2013${hhmm(to)}\u2069';
