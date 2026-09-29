import 'en_strings.dart';

/// الترجمة: النص العربي هو المفتاح، والترجمة الإنجليزية في en_strings.dart.
/// أي نص بلا ترجمة يظهر بالعربية بدل أن يختفي.
class I18n {
  static String lang = 'ar';
  static bool get isAr => lang == 'ar';
}

String tr(String ar, [Map<String, Object?>? args]) {
  var s = I18n.lang == 'ar' ? ar : (enStrings[ar] ?? ar);
  if (args != null) {
    args.forEach((k, v) => s = s.replaceAll('{$k}', '${v ?? ''}'));
  }
  return s;
}
