import 'package:gym/reminders.dart';
import 'package:test/test.dart';

void main() {
  test('adds the country code to local numbers', () {
    expect(normalizePhone('0599 123 456'), '970599123456');
    expect(normalizePhone('0501234567', countryCode: '966'), '966501234567');
  });

  test('keeps international numbers', () {
    expect(normalizePhone('+20 100 123 4567'), '201001234567');
    expect(normalizePhone('00962791234567'), '962791234567');
    expect(normalizePhone('970599123456'), '970599123456');
  });

  test('returns null without digits', () {
    expect(normalizePhone(null), isNull);
    expect(normalizePhone('  '), isNull);
  });
}
