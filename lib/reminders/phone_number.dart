/// Normalizes a phone number to international digits-only form
/// (`0599123456` -> `970599123456`), the format WhatsApp and SMS gateways expect.
///
/// Numbers starting with `+` or `00` are kept as they are. Returns null when
/// there are no digits.
String? normalizePhone(String? phone, {String countryCode = '970'}) {
  if (phone == null) return null;
  final raw = phone.trim();
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return null;
  if (raw.startsWith('+')) return digits;
  if (digits.startsWith('00')) return digits.substring(2);
  final cc = countryCode.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('0')) return cc + digits.substring(1);
  if (cc.isNotEmpty && digits.startsWith(cc) && digits.length > 10)
    return digits;
  return cc + digits;
}
