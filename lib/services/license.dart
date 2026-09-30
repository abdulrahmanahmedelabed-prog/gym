/// الترخيص: مجاني للأساسيات، وباقتا Plus و Pro بمفتاح تفعيل.
///
/// - أول تشغيل: تجربة كل مزايا Pro مجاناً [Vendor.trialDays] يوماً، ثم يعود التطبيق للنسخة المجانية (لا يُقفل ولا تضيع بيانات).
/// - مفتاح التفعيل موقّع رقمياً (RSA-SHA256) ومرتبط برمز هذا الجهاز؛ التطبيق يحمل المفتاح العام فقط فلا يمكن تزوير مفاتيح.
/// - الصيغة: NG1.<بيانات base64url>.<توقيع base64url>
///   البيانات: device, tier (plus/pro), gym, expires (فارغ = دائم), issued, id
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sembast/sembast.dart';

import '../core/dates.dart';
import '../core/i18n.dart';
import '../core/license_pubkey.dart';
import '../core/vendor.dart';

enum Tier { free, plus, pro }

Tier tierFrom(Object? v) => Tier.values.firstWhere((t) => t.name == v, orElse: () => Tier.free);

String tierName(Tier t) => switch (t) {
      Tier.free => tr('مجاني'),
      Tier.plus => 'Plus',
      Tier.pro => 'Pro',
    };

/// المزايا المدفوعة والباقة التي تفتحها
enum Feature {
  // Plus
  autoReminders,
  campaigns,
  installments,
  offers,
  walletQr,
  pdfPrint,
  shop,
  fullReports,
  leads,
  measurements,
  importExport,
  staff,
  zatca,
  cloudSync,
  accounting,
  // Pro
  autoSend,
  paymentGateways,
  autoRenew,
  classes,
  personalTraining,
  kiosk,
  auditLog,
  ownerSummary,
  multiDevice,
}

const featureTier = <Feature, Tier>{
  Feature.autoReminders: Tier.plus,
  Feature.campaigns: Tier.plus,
  Feature.installments: Tier.plus,
  Feature.offers: Tier.plus,
  Feature.walletQr: Tier.plus,
  Feature.pdfPrint: Tier.plus,
  Feature.shop: Tier.plus,
  Feature.fullReports: Tier.plus,
  Feature.leads: Tier.plus,
  Feature.measurements: Tier.plus,
  Feature.importExport: Tier.plus,
  Feature.staff: Tier.plus,
  Feature.zatca: Tier.plus,
  Feature.cloudSync: Tier.plus,
  Feature.accounting: Tier.plus,
  Feature.autoSend: Tier.pro,
  Feature.paymentGateways: Tier.pro,
  Feature.autoRenew: Tier.pro,
  Feature.classes: Tier.pro,
  Feature.personalTraining: Tier.pro,
  Feature.kiosk: Tier.pro,
  Feature.auditLog: Tier.pro,
  Feature.ownerSummary: Tier.pro,
  Feature.multiDevice: Tier.pro,
};

String featureName(Feature f) => switch (f) {
      Feature.autoReminders => tr('التذكيرات التلقائية اليومية و«إرسال الكل»'),
      Feature.campaigns => tr('الرسائل الجماعية'),
      Feature.installments => tr('التقسيط وتذكير الأقساط'),
      Feature.offers => tr('العروض والكوبونات'),
      Feature.walletQr => tr('الدفع بالمحافظ ورمز QR الموحد والمطابقة'),
      Feature.pdfPrint => tr('فواتير PDF والطباعة الحرارية'),
      Feature.shop => tr('المتجر والمخزون'),
      Feature.fullReports => tr('التقارير الكاملة والمصروفات'),
      Feature.leads => tr('العملاء المحتملون'),
      Feature.measurements => tr('قياسات الجسم'),
      Feature.importExport => tr('الاستيراد والتصدير Excel'),
      Feature.staff => tr('الموظفون والصلاحيات (حتى 5)'),
      Feature.zatca => tr('رمز QR للفاتورة الضريبية'),
      Feature.autoSend => tr('إرسال آلي كامل (واتساب API، SMS من الشريحة)'),
      Feature.paymentGateways => tr('بوابات الدفع الإلكتروني'),
      Feature.autoRenew => tr('التجديد شبه التلقائي'),
      Feature.classes => tr('الحصص والحجوزات'),
      Feature.personalTraining => tr('التدريب الشخصي وعمولات المدربين'),
      Feature.kiosk => tr('شاشة الدخول الذاتي'),
      Feature.auditLog => tr('سجل العمليات وموظفون بلا حد'),
      Feature.ownerSummary => tr('الملخص اليومي للمالك'),
      Feature.cloudSync => tr('المزامنة والنسخ السحابي (جهازان)'),
      Feature.accounting => tr('المحاسبة والتدقيق المالي الآلي وإغلاق الصندوق'),
      Feature.multiDevice => tr('مزامنة حتى {n} أجهزة', {'n': proSyncDevices}),
    };

const proStaffLimit = 1000;
const plusSyncDevices = 2;
const proSyncDevices = 10;
const plusStaffLimit = 5;

class LicenseException implements Exception {
  final String message;
  final Feature? feature;
  LicenseException(this.message, [this.feature]);
  @override
  String toString() => message;
}

enum LicenseState { trial, licensed, free, expired }

class LicenseStatus {
  final Tier tier; // الباقة الفعلية الآن
  final LicenseState state;
  final Tier? keyTier; // باقة المفتاح (حتى لو انتهى)
  final DateTime? expires;
  final int? daysLeft;
  final String? gym;
  final String? keyError;

  LicenseStatus({required this.tier, required this.state, this.keyTier, this.expires, this.daysLeft, this.gym, this.keyError});

  String get label => switch (state) {
        LicenseState.trial => tr('تجربة Pro — متبقٍ {n} يوم', {'n': daysLeft}),
        LicenseState.licensed => expires == null
            ? tr('{t} — دائمة', {'t': tierName(tier)})
            : tr('{t} — حتى {d}', {'t': tierName(tier), 'd': dayKey(expires!)}),
        LicenseState.expired => tr('انتهى اشتراك {t} — تعمل الآن المزايا المجانية', {'t': tierName(keyTier ?? Tier.plus)}),
        LicenseState.free => tr('النسخة المجانية'),
      };
}

// -----------------------------------------------------------------------------
// التحقق من التوقيع (RSA PKCS#1 v1.5 + SHA-256) بدون مكتبات خارجية
// -----------------------------------------------------------------------------

final _sha256Prefix = [0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20];

BigInt _toBig(List<int> bytes) {
  var r = BigInt.zero;
  for (final b in bytes) {
    r = (r << 8) | BigInt.from(b);
  }
  return r;
}

BigInt _encodedDigest(List<int> payload, int k) {
  final t = [..._sha256Prefix, ...sha256.convert(payload).bytes];
  final em = <int>[0x00, 0x01, ...List.filled(k - t.length - 3, 0xff), 0x00, ...t];
  return _toBig(em);
}

bool verifyRsaSha256(List<int> payload, List<int> signature, BigInt n, BigInt e) {
  final k = (n.bitLength + 7) >> 3;
  if (signature.length != k) return false;
  final s = _toBig(signature);
  if (s >= n) return false;
  return s.modPow(e, n) == _encodedDigest(payload, k);
}

Uint8List b64d(String s) => base64Url.decode(s + '=' * ((4 - s.length % 4) % 4));

/// يتحقق من مفتاح ويرجع بياناته أو يرمي LicenseException
Map<String, Object?> parseLicenseKey(String key, {BigInt? n, BigInt? e}) {
  final nn = n ?? licensePublicN, ee = e ?? licensePublicE;
  key = key.replaceAll(RegExp(r'\s'), '');
  final parts = key.split('.');
  if (parts.length != 3 || parts[0] != 'NG1') throw LicenseException(tr('صيغة مفتاح التفعيل غير صحيحة. انسخه كاملاً كما وصلك'));
  late Uint8List payload, sig;
  try {
    payload = b64d(parts[1]);
    sig = b64d(parts[2]);
  } catch (_) {
    throw LicenseException(tr('مفتاح التفعيل تالف'));
  }
  if (!verifyRsaSha256(payload, sig, nn, ee)) throw LicenseException(tr('مفتاح التفعيل غير صالح'));
  final data = jsonDecode(utf8.decode(payload));
  if (data is! Map) throw LicenseException(tr('مفتاح التفعيل تالف'));
  return Map<String, Object?>.from(data);
}

String normalizeDevice(String? code) {
  final c = (code ?? '').toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  final out = <String>[];
  for (var i = 0; i < c.length; i += 4) {
    out.add(c.substring(i, min(i + 4, c.length)));
  }
  return out.join('-');
}

// -----------------------------------------------------------------------------
// حالة الترخيص على هذا الجهاز (تُحفظ خارج بيانات النادي: لا تنتقل مع النسخ الاحتياطي)
// -----------------------------------------------------------------------------

class LicenseManager {
  static final _store = StoreRef<String, Object?>('device');

  final Database? db;
  final DateTime Function() clock;
  String deviceCode = '';
  DateTime installDate;
  DateTime lastSeen;
  String? key;

  /// للاختبارات: مفتاح عام بديل، أو باقة ثابتة
  BigInt? testN, testE;
  Tier? debugTier;

  LicenseManager(this.db, this.clock)
      : installDate = dateOnly(clock()),
        lastSeen = dateOnly(clock());

  static String _newDeviceCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    final s = List.generate(12, (_) => chars[r.nextInt(chars.length)]).join();
    return normalizeDevice(s);
  }

  Future<void> load() async {
    final m = db == null ? null : await _store.record('install').get(db!) as Map?;
    if (m == null) {
      deviceCode = _newDeviceCode();
      installDate = dateOnly(clock());
      lastSeen = installDate;
      await _save();
    } else {
      deviceCode = '${m['device'] ?? _newDeviceCode()}';
      installDate = tryParseDay(m['installDate'] as String?) ?? dateOnly(clock());
      lastSeen = tryParseDay(m['lastSeen'] as String?) ?? installDate;
      key = m['key'] as String?;
    }
  }

  Future<void> _save() async {
    if (db == null) return;
    await _store.record('install').put(db!, {
      'device': deviceCode,
      'installDate': dayKey(installDate),
      'lastSeen': dayKey(lastSeen),
      'key': ?key,
    });
  }

  /// أحدث تاريخ رآه التطبيق (إرجاع ساعة الجهاز للوراء لا يمدد التجربة أو الاشتراك)
  DateTime get effectiveToday {
    final t = dateOnly(clock());
    if (t.isAfter(lastSeen)) {
      lastSeen = t;
      _save();
      return t;
    }
    return lastSeen;
  }

  LicenseStatus status() {
    if (debugTier != null) return LicenseStatus(tier: debugTier!, state: LicenseState.licensed, keyTier: debugTier);
    final today = effectiveToday;
    String? keyError;
    if (key != null) {
      try {
        final data = parseLicenseKey(key!, n: testN, e: testE);
        if (normalizeDevice(data['device'] as String?) != normalizeDevice(deviceCode)) {
          throw LicenseException(tr('مفتاح التفعيل لجهاز آخر'));
        }
        final t = tierFrom(data['tier']);
        final exp = tryParseDay(data['expires'] as String?);
        if (exp != null && today.isAfter(exp)) {
          return LicenseStatus(tier: _trialOrFree(today).$1, state: LicenseState.expired, keyTier: t, expires: exp, gym: data['gym'] as String?);
        }
        return LicenseStatus(
          tier: t,
          state: LicenseState.licensed,
          keyTier: t,
          expires: exp,
          daysLeft: exp == null ? null : daysBetween(today, exp),
          gym: data['gym'] as String?,
        );
      } on LicenseException catch (e) {
        keyError = e.message;
      }
    }
    final (tier, left) = _trialOrFree(today);
    return LicenseStatus(
      tier: tier,
      state: tier == Tier.pro ? LicenseState.trial : LicenseState.free,
      daysLeft: left,
      keyError: keyError,
    );
  }

  (Tier, int) _trialOrFree(DateTime today) {
    final left = Vendor.trialDays - daysBetween(installDate, today);
    return left > 0 ? (Tier.pro, left) : (Tier.free, 0);
  }

  Tier get tier => status().tier;

  bool has(Feature f) => tier.index >= featureTier[f]!.index;

  int get staffLimit => switch (tier) { Tier.free => 1, Tier.plus => plusStaffLimit, Tier.pro => proStaffLimit };

  /// عدد الأجهزة المسموح بمزامنتها معاً
  int get syncDeviceLimit => switch (tier) { Tier.free => 0, Tier.plus => plusSyncDevices, Tier.pro => proSyncDevices };

  int get memberLimit => tier == Tier.free ? Vendor.freeMemberLimit : 1 << 30;

  void require(Feature f) {
    if (!has(f)) {
      throw LicenseException(
          tr('«{f}» متاحة في نسخة {t}. رقِّ النسخة من الإعدادات › الترخيص', {'f': featureName(f), 't': tierName(featureTier[f]!)}), f);
    }
  }

  Future<LicenseStatus> activate(String k) async {
    final data = parseLicenseKey(k, n: testN, e: testE);
    if (normalizeDevice(data['device'] as String?) != normalizeDevice(deviceCode)) {
      throw LicenseException(tr('هذا المفتاح لجهاز آخر ({d}). رمز هذا الجهاز: {m}', {'d': data['device'], 'm': deviceCode}));
    }
    final exp = tryParseDay(data['expires'] as String?);
    if (exp != null && effectiveToday.isAfter(exp)) {
      throw LicenseException(tr('هذا المفتاح منتهي منذ {d}', {'d': dayKey(exp)}));
    }
    key = k.replaceAll(RegExp(r'\s'), '');
    await _save();
    return status();
  }

  Future<void> removeKey() async {
    key = null;
    await _save();
  }
}
