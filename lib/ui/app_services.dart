import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/i18n.dart';
import '../data/gym_data.dart';
import '../models/activity.dart';
import '../models/billing.dart';
import '../models/member.dart';
import '../services/billing.dart';
import '../services/checkin.dart';
import '../services/classes.dart';
import '../services/data_tools.dart';
import '../services/membership.dart';
import '../services/messaging.dart';
import '../services/payments.dart';
import '../services/pdf_service.dart';
import '../services/reminders.dart';
import '../services/reports.dart';

/// كل الخدمات في مكان واحد + المهام الدورية (التذكيرات، الإرسال الآلي، فحص روابط الدفع، النسخ الاحتياطي).
class AppServices {
  final GymData d;
  late final members = MembershipService(d);
  late final billing = BillingService(d);
  late final checkin = CheckinService(d);
  late final classes = ClassService(d);
  late final reminders = ReminderEngine(d);
  late final reports = Reports(d);
  late final dispatcher = Dispatcher(d, pdfFor: _pdfForInvoice);
  late final payLinks = PaymentLinkService(d);
  late final backup = BackupService(d);

  Timer? _timer;
  bool _busy = false;
  final status = ValueNotifier<String?>(null);

  AppServices(this.d);

  PdfFonts? _fonts;
  Future<PdfFonts> fonts() async => _fonts ??= PdfFonts.fromBytes(
        await rootBundle.load('assets/fonts/Tajawal-Regular.ttf'),
        await rootBundle.load('assets/fonts/Tajawal-Bold.ttf'),
      );

  Future<PdfService> pdf() async => PdfService(d, await fonts());

  Future<Uint8List?> _pdfForInvoice(String id) async {
    final inv = d.invoices[id];
    if (inv == null) return null;
    return (await pdf()).invoice(inv, thermal: false);
  }

  /// يبدأ المهام الدورية: الآن ثم كل 5 دقائق ما دام التطبيق مفتوحاً
  void start() {
    Future.delayed(const Duration(seconds: 3), tick);
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => tick());
  }

  void stop() => _timer?.cancel();

  Future<void> tick() async {
    if (_busy) return;
    _busy = true;
    try {
      await reminders.run();
      await dispatcher.dispatchQueued();
      if (payLinks.enabled) await payLinks.checkPending();
      if (!kIsWeb) await backup.autoDaily();
    } catch (e) {
      debugPrint('tick: $e');
    } finally {
      _busy = false;
    }
  }

  int get pendingManual => d.messages.all.where((m) => m.status == MsgStatus.manual).length;

  // ---------------------------------------------------------------------------
  // الإرسال والمشاركة
  // ---------------------------------------------------------------------------

  /// يرسل رسالة: آلياً إن كان هناك مزوّد، وإلا يفتح واتساب/الرسائل بالنص جاهزاً. يرجع وصفاً للنتيجة.
  Future<String> send(Message m) async {
    if (!d.messages.items.containsKey(m.id)) await d.put(m);
    if (dispatcher.isAuto(m.channel)) {
      final ok = await dispatcher.sendOne(m);
      if (ok) return tr('تم الإرسال ✓');
      if (m.status == MsgStatus.manual) return openManual(m);
      throw SendException(m.error ?? tr('تعذر الإرسال'));
    }
    return openManual(m);
  }

  Future<String> openManual(Message m) async {
    if (isDesktop && m.channel == Channel.sms) {
      // لا تطبيق رسائل على الكمبيوتر: يُنسخ النص ليُرسل من الجوال
      await Clipboard.setData(ClipboardData(text: '${m.phone}\n${m.body}'));
      await dispatcher.markSentManually(m);
      return tr('نُسخ نص الرسالة ورقم الجوال — أرسلها من جوالك');
    }
    final ok = await launchUrl(dispatcher.manualLink(m), mode: LaunchMode.externalApplication);
    if (!ok) throw SendException(tr('تعذر فتح التطبيق'));
    await dispatcher.markSentManually(m);
    return m.channel == Channel.whatsapp ? tr('فُتح واتساب — اضغط إرسال') : tr('فُتحت الرسائل — اضغط إرسال');
  }

  Future<void> call(String phone) => launchUrl(Uri.parse('tel:$phone'));

  Future<void> openWhatsApp(String phone, [String text = '']) =>
      launchUrl(Dispatcher.whatsappTo(phone, d.settings.countryCode, text), mode: LaunchMode.externalApplication);

  /// على الكمبيوتر لا توجد قائمة مشاركة: يُحفظ الملف حيث يختار المستخدم
  static bool get isDesktop =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.linux || defaultTargetPlatform == TargetPlatform.macOS);

  Future<void> shareFile(Uint8List bytes, String name, String mime, {String? text}) async {
    if (isDesktop) {
      await FilePicker.saveFile(fileName: name, bytes: bytes, mimeType: mime, dialogTitle: tr('حفظ الملف'));
      return;
    }
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(bytes, name: name, mimeType: mime)],
      fileNameOverrides: [name],
      text: text,
    ));
  }

  Future<void> shareText(String text) => SharePlus.instance.share(ShareParams(text: text));

  Future<void> shareInvoicePdf(Invoice inv, {bool? thermal}) async {
    final bytes = await (await pdf()).invoice(inv, thermal: thermal);
    await shareFile(bytes, '${inv.number}.pdf', 'application/pdf', text: '${d.settings.gymName} — ${inv.number}');
  }

  Future<void> printInvoice(Invoice inv, {bool? thermal}) async {
    final bytes = await (await pdf()).invoice(inv, thermal: thermal);
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: inv.number);
  }

  /// إرسال الفاتورة للعضو برسالة (نص الفاتورة + رابط الدفع)
  Future<String> sendInvoice(Invoice inv, {Channel? channel}) async {
    final m = reminders.invoiceMessage(inv);
    if (m == null) throw SendException(tr('الفاتورة ليست لعضو'));
    if (channel != null) m.channel = channel;
    return send(m);
  }

  Future<void> onResume() async => tick();
}
