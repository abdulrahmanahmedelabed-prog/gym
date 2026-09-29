import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/i18n.dart';
import '../core/money.dart';
import '../core/phone.dart';
import '../data/gym_data.dart';
import '../models/billing.dart';
import '../models/member.dart';
import 'billing.dart';
import 'license.dart';
import 'membership.dart';

class PayGatewayException implements Exception {
  final String message;
  PayGatewayException(this.message);
  @override
  String toString() => message;
}

/// بوابة دفع تُنشئ رابطاً يفتحه العضو ويدفع بالبطاقة/مدى/Apple Pay...
/// (لا توجد خوادم وسيطة: التطبيق يتصل بالبوابة مباشرة ويتحقق من حالة الدفع بنفسه)
abstract class PayGateway {
  String get name;
  bool get canVerify;
  Future<PaymentLink> create({required Invoice invoice, required double amount, Member? member});
  Future<bool> isPaid(PaymentLink link);
}

/// المبلغ بأصغر وحدة للعملة (قرش/هللة/فلس)
int minorAmount(double amount, String currency) {
  final units = Money.minorUnitsOf(currency);
  var v = (amount * _pow10(units)).round();
  return v;
}

int _pow10(int n) {
  var r = 1;
  for (var i = 0; i < n; i++) {
    r *= 10;
  }
  return r;
}

String _err(http.Response r) {
  try {
    final j = jsonDecode(r.body);
    final msg = j is Map ? (j['error'] is Map ? j['error']['message'] : (j['message'] ?? j['errors'])) : null;
    if (msg != null) return 'HTTP ${r.statusCode}: $msg';
  } catch (_) {}
  final b = r.body.length > 300 ? r.body.substring(0, 300) : r.body;
  return 'HTTP ${r.statusCode}: $b';
}

/// Stripe Checkout (عالمي، يدعم الإمارات وغيرها)
class StripeGateway implements PayGateway {
  final http.Client client;
  final String secretKey;
  final String currency;
  final String returnUrl;
  StripeGateway(this.client, {required this.secretKey, required this.currency, required this.returnUrl});

  @override
  String get name => 'stripe';
  @override
  bool get canVerify => true;

  Map<String, String> get _auth => {'Authorization': 'Bearer $secretKey'};

  @override
  Future<PaymentLink> create({required Invoice invoice, required double amount, Member? member}) async {
    var minor = minorAmount(amount, currency);
    if (Money.minorUnitsOf(currency) == 3) minor = (minor / 10).round() * 10; // Stripe يشترط آخر خانة صفر
    final r = await client.post(Uri.parse('https://api.stripe.com/v1/checkout/sessions'), headers: _auth, body: {
      'mode': 'payment',
      'line_items[0][price_data][currency]': currency.toLowerCase(),
      'line_items[0][price_data][product_data][name]': '${tr('فاتورة')} ${invoice.number}',
      'line_items[0][price_data][unit_amount]': '$minor',
      'line_items[0][quantity]': '1',
      'success_url': returnUrl,
      'client_reference_id': invoice.number,
      'metadata[invoice]': invoice.number,
    });
    if (r.statusCode >= 300) throw PayGatewayException(_err(r));
    final j = jsonDecode(r.body) as Map;
    return PaymentLink(
        provider: name, externalId: '${j['id']}', url: '${j['url']}', amount: amount, createdAt: DateTime.now());
  }

  @override
  Future<bool> isPaid(PaymentLink link) async {
    final r = await client.get(Uri.parse('https://api.stripe.com/v1/checkout/sessions/${link.externalId}'), headers: _auth);
    if (r.statusCode >= 300) throw PayGatewayException(_err(r));
    return (jsonDecode(r.body) as Map)['payment_status'] == 'paid';
  }
}

/// ميسّر Moyasar (السعودية: مدى، فيزا، Apple Pay، STC Pay)
class MoyasarGateway implements PayGateway {
  final http.Client client;
  final String secretKey;
  final String currency;
  final String returnUrl;
  MoyasarGateway(this.client, {required this.secretKey, required this.currency, required this.returnUrl});

  @override
  String get name => 'moyasar';
  @override
  bool get canVerify => true;

  Map<String, String> get _auth => {'Authorization': 'Basic ${base64Encode(utf8.encode('$secretKey:'))}'};

  @override
  Future<PaymentLink> create({required Invoice invoice, required double amount, Member? member}) async {
    final r = await client.post(Uri.parse('https://api.moyasar.com/v1/invoices'), headers: _auth, body: {
      'amount': '${minorAmount(amount, currency)}',
      'currency': currency.toUpperCase(),
      'description': '${tr('فاتورة')} ${invoice.number}${member == null ? '' : ' — ${member.name}'}',
      if (returnUrl.isNotEmpty) 'success_url': returnUrl,
    });
    if (r.statusCode >= 300) throw PayGatewayException(_err(r));
    final j = jsonDecode(r.body) as Map;
    return PaymentLink(
        provider: name, externalId: '${j['id']}', url: '${j['url']}', amount: amount, createdAt: DateTime.now());
  }

  @override
  Future<bool> isPaid(PaymentLink link) async {
    final r = await client.get(Uri.parse('https://api.moyasar.com/v1/invoices/${link.externalId}'), headers: _auth);
    if (r.statusCode >= 300) throw PayGatewayException(_err(r));
    return (jsonDecode(r.body) as Map)['status'] == 'paid';
  }
}

/// Tap Payments (الخليج: الكويت، البحرين، الإمارات، السعودية، قطر، عُمان)
class TapGateway implements PayGateway {
  final http.Client client;
  final String secretKey;
  final String currency;
  final String returnUrl;
  final String countryCode;
  TapGateway(this.client,
      {required this.secretKey, required this.currency, required this.returnUrl, required this.countryCode});

  @override
  String get name => 'tap';
  @override
  bool get canVerify => true;

  Map<String, String> get _headers => {'Authorization': 'Bearer $secretKey', 'Content-Type': 'application/json'};

  @override
  Future<PaymentLink> create({required Invoice invoice, required double amount, Member? member}) async {
    final cc = digitsOnly(countryCode);
    final phone = normalizePhone(member?.phone, cc) ?? '';
    final local = phone.startsWith(cc) ? phone.substring(cc.length) : phone;
    final r = await client.post(Uri.parse('https://api.tap.company/v2/charges/'),
        headers: _headers,
        body: jsonEncode({
          'amount': roundMoney(amount, Money.minorUnitsOf(currency)),
          'currency': currency.toUpperCase(),
          'description': '${tr('فاتورة')} ${invoice.number}',
          'reference': {'order': invoice.number},
          'customer': {
            'first_name': member?.firstName ?? invoice.customerName ?? 'Customer',
            if (phone.isNotEmpty) 'phone': {'country_code': cc, 'number': local},
            if (member?.email != null) 'email': member!.email,
          },
          'source': {'id': 'src_all'},
          'redirect': {'url': returnUrl.isEmpty ? 'https://www.tap.company' : returnUrl},
        }));
    if (r.statusCode >= 300) throw PayGatewayException(_err(r));
    final j = jsonDecode(r.body) as Map;
    final url = (j['transaction'] as Map?)?['url'];
    if (url == null) throw PayGatewayException(_err(r));
    return PaymentLink(provider: name, externalId: '${j['id']}', url: '$url', amount: amount, createdAt: DateTime.now());
  }

  @override
  Future<bool> isPaid(PaymentLink link) async {
    final r = await client.get(Uri.parse('https://api.tap.company/v2/charges/${link.externalId}'), headers: _headers);
    if (r.statusCode >= 300) throw PayGatewayException(_err(r));
    return (jsonDecode(r.body) as Map)['status'] == 'CAPTURED';
  }
}

/// رابط دفع ثابت (رابط انستاباي، فوري، PayPal.me، صفحة بنك...) يؤكد الموظف استلامه يدوياً
class TemplateLinkGateway implements PayGateway {
  final String template;
  TemplateLinkGateway(this.template);

  @override
  String get name => 'link';
  @override
  bool get canVerify => false;

  @override
  Future<PaymentLink> create({required Invoice invoice, required double amount, Member? member}) async {
    if (template.trim().isEmpty) throw PayGatewayException(tr('اكتب رابط الدفع في الإعدادات'));
    final url = template
        .replaceAll('{amount}', roundMoney(amount).toString())
        .replaceAll('{invoice}', Uri.encodeComponent(invoice.number))
        .replaceAll('{name}', Uri.encodeComponent(member?.name ?? ''))
        .replaceAll('{phone}', Uri.encodeComponent(member?.phone ?? ''));
    return PaymentLink(provider: name, externalId: invoice.number, url: url, amount: amount, createdAt: DateTime.now());
  }

  @override
  Future<bool> isPaid(PaymentLink link) async => false;
}

class PaymentLinkService {
  final GymData d;
  final http.Client client;
  PaymentLinkService(this.d, {http.Client? client}) : client = client ?? http.Client();

  bool get enabled => d.settings.payProvider != 'none' && gateway() != null;

  String get _returnUrl {
    final s = d.settings;
    if (s.payReturnUrl.isNotEmpty) return s.payReturnUrl;
    final gp = normalizePhone(s.gymPhone, s.countryCode);
    return gp == null ? '' : 'https://wa.me/$gp'; // بعد الدفع يعود العضو لمحادثة النادي
  }

  PayGateway? gateway() {
    final s = d.settings;
    if (s.payProvider == 'link' ? !d.has(Feature.walletQr) : !d.has(Feature.paymentGateways)) return null;
    switch (s.payProvider) {
      case 'stripe':
        return StripeGateway(client, secretKey: s.paySecretKey, currency: s.currencyCode, returnUrl: _returnUrl);
      case 'moyasar':
        return MoyasarGateway(client, secretKey: s.paySecretKey, currency: s.currencyCode, returnUrl: _returnUrl);
      case 'tap':
        return TapGateway(client,
            secretKey: s.paySecretKey, currency: s.currencyCode, returnUrl: _returnUrl, countryCode: s.countryCode);
      case 'link':
        return TemplateLinkGateway(s.payLinkTemplate);
      default:
        return null;
    }
  }

  /// إنشاء رابط دفع للمبلغ المتبقي (أو مبلغ القسط) وحفظه في الفاتورة
  Future<PaymentLink> createLink(Invoice inv, {double? amount}) async {
    final g = gateway();
    if (g == null) throw PayGatewayException(tr('فعّل بوابة الدفع من الإعدادات أولاً'));
    final a = roundMoney(amount ?? inv.balance);
    if (a <= 0) throw PayGatewayException(tr('لا يوجد مبلغ مستحق'));
    final link = await g.create(invoice: inv, amount: a, member: d.members[inv.memberId]);
    inv.links.add(link);
    await d.put(inv);
    return link;
  }

  /// فحص روابط الدفع المعلّقة: ما دُفع يُسجّل تلقائياً كدفعة «أونلاين». يرجع عدد الروابط المدفوعة.
  Future<int> checkPending() async {
    final g = gateway();
    if (g == null || !g.canVerify) return 0;
    var paid = 0;
    final billing = BillingService(d);
    for (final inv in d.invoices.all.toList()) {
      for (final l in inv.links) {
        if (l.status != LinkStatus.pending || l.provider != g.name) continue;
        if (DateTime.now().difference(l.createdAt).inDays > 30) continue;
        bool ok;
        try {
          ok = await g.isPaid(l);
        } catch (_) {
          continue;
        }
        if (!ok) continue;
        l
          ..status = LinkStatus.paid
          ..paidAt = d.now();
        final amount = l.amount > inv.balance ? inv.balance : l.amount;
        if (amount > 0) {
          await billing.collect(inv, amount, PayMethod.online, reference: '${l.provider}:${l.externalId}');
        } else {
          await d.put(inv);
        }
        paid++;
      }
    }
    return paid;
  }

  Future<void> markLinkPaidManually(Invoice inv, PaymentLink l) async {
    final amount = l.amount > inv.balance ? inv.balance : l.amount;
    l
      ..status = LinkStatus.paid
      ..paidAt = d.now();
    if (amount > 0) {
      await BillingService(d).collect(inv, amount, PayMethod.online, reference: '${l.provider}:${l.externalId}');
    } else {
      await d.put(inv);
    }
  }

  Future<void> cancelLink(Invoice inv, PaymentLink l) async {
    if (l.status != LinkStatus.pending) throw GymException(tr('الرابط ليس معلّقاً'));
    l.status = LinkStatus.cancelled;
    await d.put(inv);
  }
}
