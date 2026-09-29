/// أساس النماذج: كل سجل له معرّف نصي ويتحول إلى Map للتخزين.
library;

abstract class Entity {
  String get id;
  Map<String, Object?> toMap();
}

double asDouble(Object? v, [double def = 0]) {
  if (v == null) return def;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? def;
}

int asInt(Object? v, [int def = 0]) {
  if (v == null) return def;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? def;
}

int? asIntOrNull(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

double? asDoubleOrNull(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

bool asBool(Object? v, [bool def = false]) {
  if (v == null) return def;
  if (v is bool) return v;
  if (v is num) return v != 0;
  return v.toString() == 'true' || v.toString() == '1';
}

String asStr(Object? v, [String def = '']) => v == null ? def : v.toString();

String? asStrOrNull(Object? v) {
  if (v == null) return null;
  final s = v.toString();
  return s.isEmpty ? null : s;
}

DateTime? asTime(Object? v) => v == null ? null : DateTime.tryParse(v.toString());

List<String> asStrList(Object? v) => v is List ? v.map((e) => e.toString()).toList() : <String>[];

List<int> asIntList(Object? v) => v is List ? v.map((e) => asInt(e)).toList() : <int>[];

List<Map<String, Object?>> asMapList(Object? v) =>
    v is List ? v.whereType<Map>().map((e) => Map<String, Object?>.from(e)).toList() : [];

/// يحذف القيم الفارغة لتصغير حجم التخزين والنسخ الاحتياطي
Map<String, Object?> compact(Map<String, Object?> m) {
  m.removeWhere((k, v) => v == null || (v is String && v.isEmpty));
  return m;
}
