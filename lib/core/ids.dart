import 'dart:math';

final _rand = Random.secure();
const _alphabet = '0123456789abcdefghijklmnopqrstuvwxyz';

/// معرّف فريد نصي (وقت + عشوائي) — يصلح للمزامنة بين أكثر من جهاز لاحقاً دون تعارض
String newId() {
  final t = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final r = List.generate(6, (_) => _alphabet[_rand.nextInt(_alphabet.length)]).join();
  return '$t$r';
}

/// رمز بطاقة العضو (QR): حروف وأرقام يصعب تخمينها، بدون الأحرف المتشابهة
String newCardToken() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  return List.generate(8, (_) => chars[_rand.nextInt(chars.length)]).join();
}
