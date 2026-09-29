import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../core/dates.dart';
import '../core/i18n.dart';
import '../core/phone.dart';
import '../data/gym_data.dart';
import '../models/activity.dart';
import '../models/member.dart';
import '../models/settings.dart';
import 'license.dart';

class SendException implements Exception {
  final String message;
  SendException(this.message);
  @override
  String toString() => message;
}

/// مزوّد إرسال آلي
abstract class Sender {
  String get name;

  /// [phone] بالصيغة الدولية بدون + . يرجع معرّف الرسالة عند المزوّد إن وجد.
  Future<String?> send(String phone, String body, {Uint8List? pdf, String? pdfName});
}

String _err(http.Response r) {
  var b = r.body;
  if (b.length > 300) b = b.substring(0, 300);
  return 'HTTP ${r.statusCode}: $b';
}

/// WhatsApp Cloud API الرسمي من Meta.
/// ملاحظة: رسائل المبادرة (التذكيرات) تحتاج قالباً معتمداً من Meta؛ يُرسل اسم العضو والنص كمتغيرين للقالب.
class WhatsAppCloudSender implements Sender {
  final http.Client client;
  final String phoneNumberId;
  final String token;
  final String? templateName; // فارغ = رسالة نصية عادية (تعمل فقط خلال 24 ساعة من آخر رسالة من العضو)
  final String templateLang;
  static const api = 'https://graph.facebook.com/v21.0';

  WhatsAppCloudSender(this.client,
      {required this.phoneNumberId, required this.token, this.templateName, this.templateLang = 'ar'});

  @override
  String get name => 'whatsapp_cloud';

  Map<String, String> get _headers => {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};

  /// متغيرات القوالب لا تقبل أسطراً جديدة
  static String flatten(String s) => s.replaceAll(RegExp(r'\s*\n+\s*'), ' — ').replaceAll(RegExp(r' {4,}'), ' ');

  @override
  Future<String?> send(String phone, String body, {Uint8List? pdf, String? pdfName}) async {
    Map<String, Object?> payload;
    if (templateName != null && templateName!.isNotEmpty) {
      final nl = body.indexOf('\n');
      final first = nl < 0 ? body : body.substring(0, nl);
      final rest = nl < 0 ? '' : body.substring(nl + 1);
      payload = {
        'messaging_product': 'whatsapp',
        'to': phone,
        'type': 'template',
        'template': {
          'name': templateName,
          'language': {'code': templateLang},
          'components': [
            {
              'type': 'body',
              'parameters': [
                {'type': 'text', 'text': flatten(first)},
                {'type': 'text', 'text': flatten(rest.isEmpty ? '-' : rest)},
              ],
            },
          ],
        },
      };
    } else {
      payload = {
        'messaging_product': 'whatsapp',
        'to': phone,
        'type': 'text',
        'text': {'body': body, 'preview_url': true},
      };
    }
    final r = await client.post(Uri.parse('$api/$phoneNumberId/messages'), headers: _headers, body: jsonEncode(payload));
    if (r.statusCode >= 300) throw SendException(_err(r));
    final id = (jsonDecode(r.body) as Map)['messages']?[0]?['id']?.toString();
    if (pdf != null) {
      try {
        await _sendDocument(phone, pdf, pdfName ?? 'invoice.pdf');
      } catch (_) {
        // النص وصل؛ المرفق يحتاج نافذة محادثة مفتوحة (24 ساعة) فلا نعتبرها فشلاً
      }
    }
    return id;
  }

  Future<void> _sendDocument(String phone, Uint8List pdf, String fileName) async {
    final up = http.MultipartRequest('POST', Uri.parse('$api/$phoneNumberId/media'))
      ..headers['Authorization'] = 'Bearer $token'
      ..fields['messaging_product'] = 'whatsapp'
      ..fields['type'] = 'application/pdf'
      ..files.add(http.MultipartFile.fromBytes('file', pdf, filename: fileName));
    final res = await http.Response.fromStream(await client.send(up));
    if (res.statusCode >= 300) throw SendException(_err(res));
    final mediaId = (jsonDecode(res.body) as Map)['id'];
    final r = await client.post(Uri.parse('$api/$phoneNumberId/messages'),
        headers: _headers,
        body: jsonEncode({
          'messaging_product': 'whatsapp',
          'to': phone,
          'type': 'document',
          'document': {'id': mediaId, 'filename': fileName},
        }));
    if (r.statusCode >= 300) throw SendException(_err(r));
  }
}

/// Twilio للـ SMS أو واتساب
class TwilioSender implements Sender {
  final http.Client client;
  final String sid;
  final String token;
  final String from;
  final bool whatsapp;

  TwilioSender(this.client, {required this.sid, required this.token, required this.from, this.whatsapp = false});

  @override
  String get name => whatsapp ? 'twilio_whatsapp' : 'twilio_sms';

  @override
  Future<String?> send(String phone, String body, {Uint8List? pdf, String? pdfName}) async {
    final to = whatsapp ? 'whatsapp:+$phone' : '+$phone';
    var f = from.trim();
    if (whatsapp && !f.startsWith('whatsapp:')) f = 'whatsapp:${f.startsWith('+') ? f : '+$f'}';
    final r = await client.post(
      Uri.parse('https://api.twilio.com/2010-04-01/Accounts/$sid/Messages.json'),
      headers: {'Authorization': 'Basic ${base64Encode(utf8.encode('$sid:$token'))}'},
      body: {'To': to, 'From': f, 'Body': body},
    );
    if (r.statusCode >= 300) throw SendException(_err(r));
    return (jsonDecode(r.body) as Map)['sid']?.toString();
  }
}

/// أي مزوّد له واجهة HTTP بسيطة (UltraMsg، Green API، مزودو SMS المحليون...).
/// المتغيرات: {phone} رقم دولي بدون +، {phone_plus} مع +، {phone_local} بصفر محلي، {message} النص.
class HttpGatewaySender implements Sender {
  final http.Client client;
  final String url;
  final String method; // GET / POST
  final String contentType; // json / form
  final String bodyTemplate;
  final String headers; // سطر لكل ترويسة: Key: Value
  final String successText; // نص يجب أن يظهر في الرد (اختياري)
  final String countryCode;
  @override
  final String name;

  HttpGatewaySender(this.client,
      {required this.url,
      this.method = 'POST',
      this.contentType = 'json',
      this.bodyTemplate = '',
      this.headers = '',
      this.successText = '',
      this.countryCode = '',
      this.name = 'gateway'});

  Map<String, String> _vars(String phone, String body) {
    final cc = digitsOnly(countryCode);
    final local = cc.isNotEmpty && phone.startsWith(cc) ? '0${phone.substring(cc.length)}' : phone;
    return {'phone': phone, 'phone_plus': '+$phone', 'phone_local': local, 'message': body};
  }

  String _fill(String tpl, Map<String, String> vars, String Function(String) enc) {
    var s = tpl;
    vars.forEach((k, v) => s = s.replaceAll('{$k}', enc(v)));
    return s;
  }

  @override
  Future<String?> send(String phone, String body, {Uint8List? pdf, String? pdfName}) async {
    if (url.trim().isEmpty) throw SendException(tr('رابط المزوّد غير مضبوط'));
    final vars = _vars(phone, body);
    final uri = Uri.parse(_fill(url.trim(), vars, Uri.encodeComponent));
    final h = <String, String>{};
    for (final line in headers.split('\n')) {
      final i = line.indexOf(':');
      if (i > 0) h[line.substring(0, i).trim()] = line.substring(i + 1).trim();
    }
    http.Response r;
    if (method.toUpperCase() == 'GET') {
      r = await client.get(uri, headers: h);
    } else if (contentType == 'form') {
      final fields = <String, String>{};
      for (final line in bodyTemplate.split('\n')) {
        final i = line.indexOf('=');
        if (i > 0) fields[line.substring(0, i).trim()] = _fill(line.substring(i + 1).trim(), vars, (v) => v);
      }
      r = await client.post(uri, headers: h, body: fields);
    } else {
      h.putIfAbsent('Content-Type', () => 'application/json');
      // داخل JSON: النص يُهرّب (علامات التنصيص والأسطر الجديدة)
      final body0 = _fill(bodyTemplate, vars, (v) {
        final e = jsonEncode(v);
        return e.substring(1, e.length - 1);
      });
      r = await client.post(uri, headers: h, body: body0);
    }
    if (r.statusCode >= 300) throw SendException(_err(r));
    if (successText.isNotEmpty && !r.body.contains(successText)) throw SendException(_err(r));
    return null;
  }
}

/// SMS من شريحة الجوال مباشرة (أندرويد فقط) عبر كود أصلي في MainActivity
class SimSmsSender implements Sender {
  static const channel = MethodChannel('nadi/sms');

  @override
  String get name => 'sim';

  @override
  Future<String?> send(String phone, String body, {Uint8List? pdf, String? pdfName}) async {
    try {
      await channel.invokeMethod('send', {'phone': '+$phone', 'text': body});
      return null;
    } on PlatformException catch (e) {
      throw SendException(e.message ?? e.code);
    } on MissingPluginException {
      throw SendException(tr('الإرسال من الشريحة متاح على أندرويد فقط'));
    }
  }
}

/// يجهّز المزوّد حسب الإعدادات، ويرسل ما في صندوق الصادر.
class Dispatcher {
  final GymData d;
  final http.Client client;
  final Future<Uint8List?> Function(String invoiceId)? pdfFor;

  Dispatcher(this.d, {http.Client? client, this.pdfFor}) : client = client ?? http.Client();

  GymSettings get s => d.settings;

  Sender? senderFor(Channel ch) {
    if (!d.has(Feature.autoSend)) return null; // الإرسال الآلي في Pro؛ غيرها بلمسة من الجوال
    final mode = ch == Channel.whatsapp ? s.waMode : s.smsMode;
    final p = ch == Channel.whatsapp ? 'wa' : 'sms';
    switch (mode) {
      case 'cloud':
        if (ch != Channel.whatsapp) return null;
        return WhatsAppCloudSender(client,
            phoneNumberId: s.str('waCloudPhoneId'),
            token: s.str('waCloudToken'),
            templateName: s.str('waCloudTemplate'),
            templateLang: s.str('waCloudLang', 'ar'));
      case 'twilio':
        return TwilioSender(client,
            sid: s.str('twilioSid'),
            token: s.str('twilioToken'),
            from: ch == Channel.whatsapp ? s.str('twilioWaFrom') : s.str('twilioSmsFrom'),
            whatsapp: ch == Channel.whatsapp);
      case 'gateway':
        return HttpGatewaySender(client,
            url: s.str('${p}GwUrl'),
            method: s.str('${p}GwMethod', 'POST'),
            contentType: s.str('${p}GwType', 'json'),
            bodyTemplate: s.str('${p}GwBody'),
            headers: s.str('${p}GwHeaders'),
            successText: s.str('${p}GwSuccess'),
            countryCode: s.countryCode,
            name: '${p}_gateway');
      case 'sim':
        return ch == Channel.sms ? SimSmsSender() : null;
      default:
        return null; // phone = يدوي
    }
  }

  bool isAuto(Channel ch) => senderFor(ch) != null;

  bool inSendWindow([DateTime? t]) {
    final m = minutesOfDay(t ?? d.now());
    return m >= s.sendFrom && m <= s.sendTo;
  }

  /// رابط الإرسال اليدوي: يفتح واتساب أو تطبيق الرسائل والنص جاهز
  Uri manualLink(Message m) {
    final num = normalizePhone(m.phone, s.countryCode) ?? m.phone;
    if (m.channel == Channel.whatsapp) {
      return Uri.parse('https://wa.me/$num?text=${Uri.encodeComponent(m.body)}');
    }
    return Uri.parse('sms:+$num?body=${Uri.encodeComponent(m.body)}');
  }

  static Uri whatsappTo(String phone, String countryCode, [String text = '']) {
    final num = normalizePhone(phone, countryCode) ?? phone;
    return Uri.parse('https://wa.me/$num${text.isEmpty ? '' : '?text=${Uri.encodeComponent(text)}'}');
  }

  Future<void> markSentManually(Message m) async {
    m
      ..status = MsgStatus.sent
      ..sentAt = d.now()
      ..provider = m.channel == Channel.whatsapp ? 'whatsapp_app' : 'sms_app';
    await d.put(m);
  }

  /// إرسال رسالة واحدة آلياً الآن. عند فشل واتساب يمكن التحويل إلى SMS.
  Future<bool> sendOne(Message m) async {
    final sender = senderFor(m.channel);
    if (sender == null) {
      m.status = MsgStatus.manual;
      await d.put(m);
      return false;
    }
    final num = normalizePhone(m.phone, s.countryCode);
    if (num == null) {
      m
        ..status = MsgStatus.failed
        ..error = tr('رقم غير صحيح');
      await d.put(m);
      return false;
    }
    m.attempts++;
    try {
      Uint8List? pdf;
      if (m.invoiceId != null && m.channel == Channel.whatsapp && pdfFor != null && sender is WhatsAppCloudSender) {
        pdf = await pdfFor!(m.invoiceId!);
      }
      await sender.send(num, m.body, pdf: pdf, pdfName: pdf == null ? null : 'invoice.pdf');
      m
        ..status = MsgStatus.sent
        ..sentAt = d.now()
        ..provider = sender.name
        ..error = null;
      await d.put(m);
      return true;
    } catch (e) {
      m.error = e.toString();
      m.provider = sender.name;
      if (m.attempts >= 3) {
        if (m.channel == Channel.whatsapp && s.fallbackToSms) {
          // المحاولة الأخيرة: تحويلها إلى SMS
          m
            ..channel = Channel.sms
            ..attempts = 0
            ..status = isAuto(Channel.sms) ? MsgStatus.queued : MsgStatus.manual;
        } else {
          m.status = MsgStatus.failed;
        }
      }
      await d.put(m);
      return false;
    }
  }

  /// إرسال كل الرسائل المنتظرة (ضمن ساعات الإرسال إلا إذا [force])
  Future<({int sent, int failed})> dispatchQueued({bool force = false}) async {
    if (!force && !inSendWindow()) return (sent: 0, failed: 0);
    var sent = 0, failed = 0;
    final queue = d.messages.all.where((m) => m.status == MsgStatus.queued).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    for (final m in queue) {
      if (await sendOne(m)) {
        sent++;
      } else {
        failed++;
      }
    }
    return (sent: sent, failed: failed);
  }

  /// رسالة تجربة لإعدادات المزوّد
  Future<void> test(Channel ch, String phone) async {
    final sender = senderFor(ch);
    if (sender == null) throw SendException(tr('طريقة الإرسال يدوية؛ لا يوجد مزوّد آلي لاختباره'));
    final num = normalizePhone(phone, s.countryCode);
    if (num == null) throw SendException(tr('رقم غير صحيح'));
    await sender.send(num, tr('رسالة تجربة من {g} ✅', {'g': s.gymName}));
  }
}
