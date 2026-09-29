import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/ids.dart';
import '../../core/money.dart';
import '../../models/business.dart';
import '../../models/member.dart';
import '../../models/settings.dart';
import '../../services/data_tools.dart';
import '../../services/demo_data.dart';
import '../../services/templates.dart';
import '../../services/license.dart';
import '../widgets/upgrade.dart';
import 'license_screen.dart';
import '../widgets/common.dart';
import 'messages_screen.dart';
import 'onboarding_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    final canSet = g.can(Perm.settings);
    Widget tile(IconData i, String t, String s, Widget page, {bool enabled = true}) => ListTile(
          enabled: enabled,
          leading: Icon(i),
          title: Text(t, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(s),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(page),
        );
    return Scaffold(
      appBar: AppBar(title: Text(tr('الإعدادات'))),
      body: ListView(children: [
        Card(
          margin: const EdgeInsets.all(12),
          color: tierColor(g.license.tier).withValues(alpha: 0.08),
          child: ListTile(
            leading: Icon(Icons.workspace_premium, color: tierColor(g.license.tier)),
            title: Text(tr('الترخيص والباقات'), style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(g.license.status().label),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(const LicenseScreen()),
          ),
        ),
        tile(Icons.storefront, tr('النادي'), tr('الاسم، الشعار، العملة، اللغة، المظهر'), const GeneralSettingsScreen(), enabled: canSet),
        tile(Icons.receipt_long, tr('الفواتير والضريبة'), tr('ضريبة القيمة المضافة، رمز QR، نص الفاتورة'), const InvoiceSettingsScreen(), enabled: canSet),
        tile(Icons.door_front_door_outlined, tr('قواعد الدخول'), tr('ساعات السيدات، فترة السماح، الديون'), const AccessSettingsScreen(), enabled: canSet),
        tile(Icons.chat_outlined, tr('الرسائل والتذكيرات'), tr('واتساب، SMS، القوالب، مواعيد التذكير'), const MessagingSettingsScreen(), enabled: canSet),
        tile(Icons.credit_card, tr('الدفع الإلكتروني'), tr('روابط الدفع، المحافظ، البوابات'), const PaymentSettingsScreen(), enabled: canSet),
        tile(Icons.local_offer_outlined, tr('كوبونات الخصم'), tr('عروض ومواسم وخصومات'), const CouponsScreen(), enabled: g.can(Perm.plans)),
        tile(Icons.lock_outline, tr('الأمان'), tr('الرقم السري للموظفين'), const SecuritySettingsScreen(), enabled: canSet),
        tile(Icons.storage_outlined, tr('البيانات'), tr('نسخ احتياطي، استرجاع، استيراد من Excel'), const DataSettingsScreen(), enabled: canSet || g.can(Perm.reports)),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.language),
          title: Text(tr('اللغة')),
          trailing: SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'ar', label: Text('ع')), ButtonSegment(value: 'en', label: Text('EN'))],
            selected: {g.settings.language},
            onSelectionChanged: (v) {
              g.settings.language = v.first;
              g.saveSettings();
            },
          ),
        ),
      ]),
    );
  }
}

/// حفظ تلقائي عند مغادرة الشاشة
mixin _AutoSave<T extends StatefulWidget> on State<T> {
  @override
  void deactivate() {
    context.gym.saveSettings();
    super.deactivate();
  }
}

class _Field extends StatelessWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final bool number;
  final int maxLines;
  final String? hint;
  final bool ltr;
  final bool obscure;
  const _Field(this.label, this.value, this.onChanged, {this.number = false, this.maxLines = 1, this.hint, this.ltr = false, this.obscure = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: TextFormField(
          initialValue: value,
          onChanged: onChanged,
          maxLines: obscure ? 1 : maxLines,
          obscureText: obscure,
          textDirection: ltr ? TextDirection.ltr : null,
          keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : (maxLines > 1 ? TextInputType.multiline : null),
          decoration: InputDecoration(labelText: label, hintText: hint, hintTextDirection: ltr ? TextDirection.ltr : null),
        ),
      );
}

class _Head extends StatelessWidget {
  final String text;
  const _Head(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Text(text, style: context.text.titleSmall?.copyWith(color: context.colors.primary, fontWeight: FontWeight.w800)),
      );
}

class _Note extends StatelessWidget {
  final String text;
  const _Note(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Text(text, style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
      );
}

// -----------------------------------------------------------------------------

class GeneralSettingsScreen extends StatefulWidget {
  const GeneralSettingsScreen({super.key});
  @override
  State<GeneralSettingsScreen> createState() => _GeneralSettingsScreenState();
}

class _GeneralSettingsScreenState extends State<GeneralSettingsScreen> with _AutoSave {
  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    final s = g.settings;
    return Scaffold(
      appBar: AppBar(title: Text(tr('النادي'))),
      body: ListView(children: [
        const SizedBox(height: 8),
        Center(
          child: GestureDetector(
            onTap: () async {
              final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 400, maxHeight: 400, imageQuality: 80);
              if (x == null) return;
              s.logo = base64Encode(await x.readAsBytes());
              await g.saveSettings();
            },
            child: CircleAvatar(
              radius: 40,
              backgroundImage: s.logo == null ? null : MemoryImage(base64Decode(s.logo!)),
              child: s.logo == null ? const Icon(Icons.add_a_photo_outlined) : null,
            ),
          ),
        ),
        Center(child: TextButton(onPressed: s.logo == null ? null : () { s.logo = null; g.saveSettings(); }, child: Text(tr('الشعار (يظهر في الفواتير والبطاقات)')))),
        _Field(tr('اسم النادي'), s.gymName, (v) => s.gymName = v),
        _Field(tr('هاتف النادي'), s.gymPhone, (v) => s.gymPhone = v, ltr: true),
        _Field(tr('العنوان'), s.address, (v) => s.address = v),
        _Head(tr('الدولة والعملة')),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DropdownButtonFormField<String>(
            initialValue: countryPresets.any((p) => p.currency == s.currencyCode && p.dial == s.countryCode) ? '${s.countryCode}|${s.currencyCode}' : null,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr('اختر الدولة')),
            items: [for (final p in countryPresets) DropdownMenuItem(value: '${p.dial}|${p.currency}', child: Text('${I18n.isAr ? p.ar : p.en} — ${p.currency}'))],
            onChanged: (v) {
              final p = countryPresets.firstWhere((x) => '${x.dial}|${x.currency}' == v);
              s
                ..countryCode = p.dial
                ..currencyCode = p.currency
                ..currencySymbol = p.symbol;
              g.saveSettings();
              setState(() {});
            },
          ),
        ),
        _Field(tr('رمز العملة الظاهر'), s.currencySymbol, (v) => s.currencySymbol = v),
        _Field(tr('رمز الاتصال الدولي للدولة'), s.countryCode, (v) => s.countryCode = v, number: true, ltr: true),
        _Note(tr('يُستخدم لتحويل أرقام الأعضاء المحلية (مثل 010...) إلى صيغة واتساب الدولية.')),
        _Head(tr('المظهر')),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'system', label: Text(tr('تلقائي'))),
              ButtonSegment(value: 'light', label: Text(tr('فاتح'))),
              ButtonSegment(value: 'dark', label: Text(tr('داكن'))),
            ],
            selected: {s.themeMode},
            onSelectionChanged: (v) {
              s.themeMode = v.first;
              g.saveSettings();
            },
          ),
        ),
        _Head(tr('التجديد والترشيح')),
        SwitchListTile(
          title: Text(tr('التجديد يبدأ من نهاية الاشتراك الحالي')),
          subtitle: Text(tr('لا يخسر العضو أياماً عند التجديد المبكر')),
          value: s.renewFromEnd,
          onChanged: (v) => setState(() => s.renewFromEnd = v),
        ),
        _Field(tr('أيام مجانية لمن يرشّح عضواً جديداً'), '${s.referralRewardDays}', (v) => s.referralRewardDays = int.tryParse(v) ?? 0, number: true),
        _Field(tr('أعلى خصم يمنحه موظف الاستقبال (%)'), fmtNum(s.maxDiscountPct), (v) => s.maxDiscountPct = parseAmount(v) ?? 0, number: true),
        const SizedBox(height: 32),
      ]),
    );
  }
}

class InvoiceSettingsScreen extends StatefulWidget {
  const InvoiceSettingsScreen({super.key});
  @override
  State<InvoiceSettingsScreen> createState() => _InvoiceSettingsScreenState();
}

class _InvoiceSettingsScreenState extends State<InvoiceSettingsScreen> with _AutoSave {
  @override
  Widget build(BuildContext context) {
    final s = context.gymWatch.settings;
    return Scaffold(
      appBar: AppBar(title: Text(tr('الفواتير والضريبة'))),
      body: ListView(children: [
        SwitchListTile(title: Text(tr('تفعيل ضريبة القيمة المضافة')), value: s.taxEnabled, onChanged: (v) => setState(() => s.taxEnabled = v)),
        if (s.taxEnabled) ...[
          _Field(tr('نسبة الضريبة %'), fmtNum(s.taxRate), (v) => s.taxRate = parseAmount(v) ?? 0, number: true),
          SwitchListTile(title: Text(tr('الأسعار شاملة الضريبة')), value: s.taxInclusive, onChanged: (v) => setState(() => s.taxInclusive = v)),
          _Field(tr('الرقم الضريبي'), s.taxNumber, (v) => s.taxNumber = v, ltr: true),
          SwitchListTile(
            title: Row(children: [Flexible(child: Text(tr('رمز QR للفاتورة الضريبية (السعودية)'))), const SizedBox(width: 6), ?lockFor(context, Feature.zatca)]),
            subtitle: Text(tr('صيغة هيئة الزكاة والضريبة للفواتير المبسطة')),
            value: s.zatcaQr,
            onChanged: (v) async {
              if (v && !await ensureFeature(context, Feature.zatca)) return;
              setState(() => s.zatcaQr = v);
            },
          ),
        ],
        _Head(tr('شكل الفاتورة')),
        _Field(tr('بادئة رقم الفاتورة'), s.invoicePrefix, (v) => s.invoicePrefix = v.trim().isEmpty ? 'INV' : v.trim(), ltr: true),
        _Field(tr('نص أسفل الفاتورة'), s.invoiceFooter, (v) => s.invoiceFooter = v, maxLines: 2),
        SwitchListTile(
          title: Text(tr('الطباعة الافتراضية: إيصال حراري 80مم')),
          subtitle: Text(tr('وإلا ورق A4')),
          value: s.receiptThermal,
          onChanged: (v) => setState(() => s.receiptThermal = v),
        ),
      ]),
    );
  }
}

class AccessSettingsScreen extends StatefulWidget {
  const AccessSettingsScreen({super.key});
  @override
  State<AccessSettingsScreen> createState() => _AccessSettingsScreenState();
}

class _AccessSettingsScreenState extends State<AccessSettingsScreen> with _AutoSave {
  @override
  Widget build(BuildContext context) {
    final s = context.gymWatch.settings;
    final windows = s.genderWindows;
    String days(List<int> w) => w.isEmpty ? tr('كل الأيام') : [for (final d in weekOrder) if (w.contains(d)) I18n.isAr ? weekdayNamesAr[d]! : weekdayNamesEn[d]!].join('، ');
    return Scaffold(
      appBar: AppBar(title: Text(tr('قواعد الدخول'))),
      body: ListView(children: [
        _Head(tr('أوقات مخصصة للسيدات أو للرجال')),
        _Note(tr('خلال الوقت المخصص لا يُسمح بدخول الجنس الآخر. مثال: السيدات من 10 صباحاً إلى 2 ظهراً.')),
        for (var i = 0; i < windows.length; i++)
          ListTile(
            leading: Icon(windows[i].gender == 'f' ? Icons.female : Icons.male),
            title: Text('${windows[i].gender == 'f' ? tr('السيدات') : tr('الرجال')}: ${hhmmRange(windows[i].from, windows[i].to)}'),
            subtitle: Text(days(windows[i].weekdays)),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => setState(() => s.genderWindows = [...windows]..removeAt(i)),
            ),
            onTap: () async {
              final w = await _editWindow(context, windows[i]);
              if (w != null) setState(() => s.genderWindows = [...windows]..[i] = w);
            },
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: OutlinedButton.icon(
            onPressed: () async {
              final w = await _editWindow(context, GenderWindow(gender: 'f', weekdays: [], from: 10 * 60, to: 14 * 60));
              if (w != null) setState(() => s.genderWindows = [...windows, w]);
            },
            icon: const Icon(Icons.add),
            label: Text(tr('إضافة وقت مخصص')),
          ),
        ),
        if (windows.isNotEmpty)
          SwitchListTile(
            title: Text(tr('لا يدخل الجنس المخصص له وقت إلا في وقته')),
            subtitle: Text(tr('مثلاً: السيدات يدخلن فقط في أوقات السيدات')),
            value: s.data['genderStrict'] != false,
            onChanged: (v) => setState(() => s.set('genderStrict', v)),
          ),
        _Head(tr('الانتهاء والديون')),
        _Field(tr('أيام سماح بعد انتهاء الاشتراك'), '${s.graceDays}', (v) => s.graceDays = int.tryParse(v) ?? 0, number: true),
        SwitchListTile(
          title: Text(tr('منع الدخول عند وجود مبلغ متأخر')),
          subtitle: Text(tr('وإلا يظهر تنبيه فقط')),
          value: s.blockOnDebt,
          onChanged: (v) => setState(() => s.blockOnDebt = v),
        ),
        if (s.blockOnDebt) _Field(tr('يُسمح بمتأخرات حتى'), fmtNum(s.debtLimit), (v) => s.debtLimit = parseAmount(v) ?? 0, number: true),
        _Field(tr('متوسط مدة التمرين بالدقائق (لعدّ الموجودين الآن)'), '${s.sessionMinutes}', (v) => s.sessionMinutes = int.tryParse(v) ?? 90, number: true),
      ]),
    );
  }

  Future<GenderWindow?> _editWindow(BuildContext context, GenderWindow w0) {
    final w = GenderWindow(gender: w0.gender, weekdays: [...w0.weekdays], from: w0.from, to: w0.to);
    return showDialog<GenderWindow>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(tr('وقت مخصص')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            SegmentedButton<String>(
              segments: [ButtonSegment(value: 'f', label: Text(tr('سيدات'))), ButtonSegment(value: 'm', label: Text(tr('رجال')))],
              selected: {w.gender},
              onSelectionChanged: (v) => set(() => w.gender = v.first),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () async {
                final t = await pickTime(c, w.from);
                if (t != null) set(() => w.from = t.hour * 60 + t.minute);
              }, child: Text('${tr('من')} ${hhmm(w.from)}'))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton(onPressed: () async {
                final t = await pickTime(c, w.to);
                if (t != null) set(() => w.to = t.hour * 60 + t.minute);
              }, child: Text('${tr('إلى')} ${hhmm(w.to)}'))),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 4, runSpacing: 4, children: [
              for (final d in weekOrder)
                FilterChip(
                  label: Text(I18n.isAr ? weekdayNamesAr[d]! : weekdayNamesEn[d]!),
                  selected: w.weekdays.contains(d),
                  onSelected: (v) => set(() => v ? w.weekdays.add(d) : w.weekdays.remove(d)),
                ),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('إلغاء'))),
            FilledButton(onPressed: () => Navigator.pop(c, w), child: Text(tr('حفظ'))),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// الرسائل
// -----------------------------------------------------------------------------

class MessagingSettingsScreen extends StatefulWidget {
  const MessagingSettingsScreen({super.key});
  @override
  State<MessagingSettingsScreen> createState() => _MessagingSettingsScreenState();
}

class _MessagingSettingsScreenState extends State<MessagingSettingsScreen> with _AutoSave {
  String _modeName(String m, bool wa) => switch (m) {
        'phone' => wa ? tr('من واتساب الجوال بلمسة (مجاني)') : tr('من تطبيق الرسائل بلمسة (مجاني)'),
        'cloud' => tr('WhatsApp Cloud API الرسمي (آلي)'),
        'twilio' => tr('Twilio (آلي)'),
        'gateway' => tr('مزوّد آخر برابط HTTP (آلي)'),
        'sim' => tr('من شريحة الجوال مباشرة (آلي، أندرويد)'),
        _ => m,
      };

  Future<void> _test(Channel ch) async {
    final phone = await askText(context, tr('رقم للتجربة'), initial: context.gym.settings.ownerPhone, hint: '01xxxxxxxxx');
    if (phone == null || !mounted) return;
    await context.gym.saveSettings();
    if (!mounted) return;
    await runAction(context, () => context.services.dispatcher.test(ch, phone), success: tr('أُرسلت رسالة التجربة ✓'));
  }

  Widget _gateway(String p) {
    final s = context.gym.settings;
    return Column(children: [
      _Field(tr('رابط المزوّد'), s.str('${p}GwUrl'), (v) => s.setStr('${p}GwUrl', v), ltr: true, hint: 'https://api.provider.com/send?to={phone}&msg={message}'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: s.str('${p}GwMethod', 'POST'),
              decoration: const InputDecoration(labelText: 'Method'),
              items: const [DropdownMenuItem(value: 'POST', child: Text('POST')), DropdownMenuItem(value: 'GET', child: Text('GET'))],
              onChanged: (v) => setState(() => s.setStr('${p}GwMethod', v!)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: s.str('${p}GwType', 'json'),
              decoration: const InputDecoration(labelText: 'Body'),
              items: const [DropdownMenuItem(value: 'json', child: Text('JSON')), DropdownMenuItem(value: 'form', child: Text('Form'))],
              onChanged: (v) => setState(() => s.setStr('${p}GwType', v!)),
            ),
          ),
        ]),
      ),
      if (s.str('${p}GwMethod', 'POST') == 'POST')
        _Field(tr('محتوى الطلب'), s.str('${p}GwBody'), (v) => s.setStr('${p}GwBody', v), maxLines: 4, ltr: true,
            hint: s.str('${p}GwType', 'json') == 'json' ? '{"to":"{phone}","body":"{message}"}' : 'token=XXXX\nto={phone_plus}\nbody={message}'),
      _Field(tr('ترويسات (سطر لكل ترويسة)'), s.str('${p}GwHeaders'), (v) => s.setStr('${p}GwHeaders', v), maxLines: 2, ltr: true, hint: 'Authorization: Bearer XXXX'),
      _Field(tr('نص يدل على النجاح (اختياري)'), s.str('${p}GwSuccess'), (v) => s.setStr('${p}GwSuccess', v), ltr: true),
      _Note(tr('المتغيرات: {phone} رقم دولي بدون +، {phone_plus} مع +، {phone_local} بالصفر المحلي، {message} نص الرسالة. يصلح لمعظم مزودي SMS وواتساب (UltraMsg، Green API، مزودي الرسائل المحليين...).')),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    final s = g.settings;
    return Scaffold(
      appBar: AppBar(title: Text(tr('الرسائل والتذكيرات'))),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        SwitchListTile(
          title: Text(tr('تجهيز التذكيرات تلقائياً كل يوم')),
          value: s.autoReminders,
          onChanged: (v) => setState(() => s.autoReminders = v),
        ),
        ListTile(
          title: Text(tr('ساعات الإرسال')),
          subtitle: Text(tr('لا تُرسل رسائل آلية خارج هذا الوقت')),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            TextButton(onPressed: () async {
              final t = await pickTime(context, s.sendFrom);
              if (t != null) setState(() => s.sendFrom = t.hour * 60 + t.minute);
            }, child: Text(hhmm(s.sendFrom))),
            const Text('—'),
            TextButton(onPressed: () async {
              final t = await pickTime(context, s.sendTo);
              if (t != null) setState(() => s.sendTo = t.hour * 60 + t.minute);
            }, child: Text(hhmm(s.sendTo))),
          ]),
        ),
        _Head(tr('واتساب')),
        RadioGroup<String>(
          groupValue: s.waMode,
          onChanged: (v) => setState(() => s.waMode = v!),
          child: Column(children: [
            for (final m in waModes)
              RadioListTile<String>(
                value: m,
                enabled: m == 'phone' || g.has(Feature.autoSend),
                title: Text(_modeName(m, true)),
                secondary: m == 'phone' ? null : lockFor(context, Feature.autoSend),
              ),
          ]),
        ),
        if (s.waMode == 'phone')
          _Note(tr('مجاني وبدون أي اشتراك: التطبيق يجهّز الرسالة ويفتح واتساب على رقم العضو، وأنت تضغط إرسال. مع «إرسال الكل» تُرسل عشرات التذكيرات في دقائق.')),
        if (s.waMode == 'cloud') ...[
          _Field('Phone number ID', s.str('waCloudPhoneId'), (v) => s.setStr('waCloudPhoneId', v.trim()), ltr: true),
          _Field('Access token', s.str('waCloudToken'), (v) => s.setStr('waCloudToken', v.trim()), ltr: true, obscure: true),
          _Field(tr('اسم القالب المعتمد (للتذكيرات)'), s.str('waCloudTemplate'), (v) => s.setStr('waCloudTemplate', v.trim()), ltr: true),
          _Field(tr('لغة القالب'), s.str('waCloudLang', 'ar'), (v) => s.setStr('waCloudLang', v.trim()), ltr: true),
          _Note(tr('من Meta Business: أنشئ قالباً من فئة Utility بمتغيرين، مثل:\n«رسالة من النادي: {{1}}\n{{2}}\nشكراً لكم»\nالمتغير الأول = السطر الأول من الرسالة، والثاني = بقيتها. بدون قالب تُرسل الرسائل النصية فقط لمن راسلك خلال 24 ساعة.')),
        ],
        if (s.waMode == 'twilio' || s.smsMode == 'twilio') ...[
          _Field('Twilio Account SID', s.str('twilioSid'), (v) => s.setStr('twilioSid', v.trim()), ltr: true),
          _Field('Twilio Auth Token', s.str('twilioToken'), (v) => s.setStr('twilioToken', v.trim()), ltr: true, obscure: true),
          if (s.waMode == 'twilio') _Field(tr('رقم واتساب المرسل'), s.str('twilioWaFrom'), (v) => s.setStr('twilioWaFrom', v.trim()), ltr: true, hint: '+14155238886'),
        ],
        if (s.waMode == 'gateway') _gateway('wa'),
        if (s.waMode != 'phone')
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: OutlinedButton.icon(onPressed: () => _test(Channel.whatsapp), icon: const Icon(Icons.send), label: Text(tr('إرسال رسالة تجربة')))),
        _Head(tr('الرسائل النصية SMS')),
        RadioGroup<String>(
          groupValue: s.smsMode,
          onChanged: (v) => setState(() => s.smsMode = v!),
          child: Column(children: [
            for (final m in smsModes)
              if (m != 'sim' || (!kIsWeb && defaultTargetPlatform == TargetPlatform.android))
                RadioListTile<String>(
                  value: m,
                  enabled: m == 'phone' || g.has(Feature.autoSend),
                  title: Text(_modeName(m, false)),
                  secondary: m == 'phone' ? null : lockFor(context, Feature.autoSend),
                ),
          ]),
        ),
        if (s.smsMode == 'sim')
          _Note(tr('تُرسل الرسائل آلياً من شريحة هذا الجوال بتكلفة باقة الرسائل لديك. سيطلب أندرويد الإذن عند أول إرسال. يجب أن يبقى التطبيق مفتوحاً على جهاز الاستقبال.')),
        if (s.smsMode == 'twilio') _Field(tr('رقم SMS المرسل'), s.str('twilioSmsFrom'), (v) => s.setStr('twilioSmsFrom', v.trim()), ltr: true),
        if (s.smsMode == 'gateway') _gateway('sms'),
        if (s.smsMode != 'phone')
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: OutlinedButton.icon(onPressed: () => _test(Channel.sms), icon: const Icon(Icons.send), label: Text(tr('إرسال رسالة تجربة')))),
        SwitchListTile(
          title: Text(tr('إن فشل واتساب يُرسل SMS')),
          value: s.fallbackToSms,
          onChanged: (v) => setState(() => s.fallbackToSms = v),
        ),
        _Head(tr('التذكيرات الآلية')),
        for (final k in Rk.all)
          ListTile(
            leading: Switch(value: s.reminderOn(k), onChanged: (v) => setState(() => s.setReminderOn(k, v))),
            title: Text(reminderKindName(k), style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(_reminderHint(k, s), maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => context.push(TemplateEditorScreen(kind: k)),
          ),
        if (s.reminderOn(Rk.ownerDaily))
          _Field(tr('جوال المالك (للملخص اليومي)'), s.ownerPhone, (v) => s.ownerPhone = v, ltr: true),
      ]),
    );
  }

  String _reminderHint(String k, GymSettings s) {
    final d = s.reminderDays(k);
    return switch (k) {
      Rk.expirySoon => tr('قبل الانتهاء بـ {d} يوم', {'d': d.join('، ')}),
      Rk.winback => tr('بعد الانتهاء بـ {d} يوم', {'d': d.join('، ')}),
      Rk.installmentDue => tr('قبل موعد القسط بـ {d} يوم', {'d': d.join('، ')}),
      Rk.installmentLate => tr('بعد التأخر بـ {d} يوم', {'d': d.join('، ')}),
      Rk.inactive => tr('بعد غياب {d} يوم', {'d': d.join('، ')}),
      Rk.visitsLow => tr('عند بقاء {d} حصة', {'d': d.join('، ')}),
      _ => s.template(k).split('\n').first,
    };
  }
}

class TemplateEditorScreen extends StatefulWidget {
  final String kind;
  const TemplateEditorScreen({super.key, required this.kind});
  @override
  State<TemplateEditorScreen> createState() => _TemplateEditorScreenState();
}

class _TemplateEditorScreenState extends State<TemplateEditorScreen> {
  late final _text = TextEditingController(text: context.gym.settings.template(widget.kind));
  late final _days = TextEditingController(text: context.gym.settings.reminderDays(widget.kind).join(', '));

  bool get _hasDays => [Rk.expirySoon, Rk.winback, Rk.installmentDue, Rk.installmentLate, Rk.inactive, Rk.visitsLow].contains(widget.kind);

  Future<void> _save() async {
    final g = context.gym;
    g.settings.setTemplate(widget.kind, _text.text.trim());
    if (_hasDays) {
      g.settings.setReminderDays(widget.kind, _days.text.split(RegExp(r'[,،\s]+')).map((x) => int.tryParse(x)).whereType<int>().toList());
    }
    await g.saveSettings();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final g = context.gym;
    final preview = renderTemplate(_text.text, {
      ...TemplateContext(g).base(null),
      'name': 'أحمد محمد', 'first_name': 'أحمد', 'code': '1001', 'plan': 'شهري', 'end_date': dayKey(addDays(g.today, 3)),
      'days': '3', 'visits_left': '2', 'amount': fmtMoney(500), 'balance': fmtMoney(500), 'due_date': dayKey(addDays(g.today, 2)),
      'invoice_no': 'INV-000123', 'class': 'كروس فت', 'time': '19:00', 'summary': '...',
    });
    return Scaffold(
      appBar: AppBar(
        title: Text(reminderKindName(widget.kind)),
        actions: [
          TextButton(
            onPressed: () => setState(() {
              g.settings.setTemplate(widget.kind, null);
              _text.text = g.settings.template(widget.kind);
            }),
            child: Text(tr('الافتراضي')),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(child: Padding(padding: const EdgeInsets.all(12), child: FilledButton(onPressed: _save, child: Text(tr('حفظ'))))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (_hasDays) ...[
          TextField(controller: _days, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('الأيام (افصل بفاصلة)'), hintText: '7, 3, 1')),
          const SizedBox(height: 12),
        ],
        TextField(controller: _text, maxLines: 8, minLines: 5, onChanged: (_) => setState(() {})),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final e in templateVars.entries)
            Tooltip(
              message: tr(e.value),
              child: ActionChip(label: Text(e.key, style: const TextStyle(fontSize: 12)), onPressed: () => setState(() => _text.text += e.key)),
            ),
        ]),
        const SizedBox(height: 16),
        Text(tr('معاينة'), style: context.text.titleSmall),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFDCF8C6), borderRadius: BorderRadius.circular(12)),
          child: Text(preview, style: const TextStyle(color: Colors.black87)),
        ),
      ]),
    );
  }
}

// -----------------------------------------------------------------------------

class PaymentSettingsScreen extends StatefulWidget {
  const PaymentSettingsScreen({super.key});
  @override
  State<PaymentSettingsScreen> createState() => _PaymentSettingsScreenState();
}

class _PaymentSettingsScreenState extends State<PaymentSettingsScreen> with _AutoSave {
  String _name(String p) => switch (p) {
        'none' => tr('بدون (نقداً وبطاقة وتحويل فقط)'),
        'stripe' => 'Stripe',
        'moyasar' => tr('ميسّر Moyasar (السعودية)'),
        'tap' => tr('Tap Payments (الخليج)'),
        'link' => tr('رابط دفع ثابت (انستاباي، فوري، PayPal.me...)'),
        _ => p,
      };

  @override
  Widget build(BuildContext context) {
    final s = context.gymWatch.settings;
    return Scaffold(
      appBar: AppBar(title: Text(tr('الدفع الإلكتروني'))),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        _Head(tr('بيانات التحويل (تظهر في رسائل التذكير)')),
        _Field(tr('انستاباي / فودافون كاش / STC Pay / IBAN'), s.walletInfo, (v) => s.walletInfo = v, maxLines: 3,
            hint: tr('للدفع: انستاباي gym@instapay أو فودافون كاش 010...')),
        _Head(tr('بوابة الدفع')),
        RadioGroup<String>(
          groupValue: s.payProvider,
          onChanged: (v) => setState(() => s.payProvider = v!),
          child: Column(children: [
            for (final p in payProviders)
              RadioListTile<String>(
                value: p,
                enabled: p == 'none' || context.gym.has(p == 'link' ? Feature.walletQr : Feature.paymentGateways),
                title: Text(_name(p)),
                secondary: p == 'none' ? null : lockFor(context, p == 'link' ? Feature.walletQr : Feature.paymentGateways),
              ),
          ]),
        ),
        if (['stripe', 'moyasar', 'tap'].contains(s.payProvider)) ...[
          _Field(tr('المفتاح السري (Secret key)'), s.paySecretKey, (v) => s.paySecretKey = v.trim(), ltr: true, obscure: true),
          _Field(tr('صفحة العودة بعد الدفع (اختياري)'), s.payReturnUrl, (v) => s.payReturnUrl = v.trim(), ltr: true, hint: 'https://wa.me/...'),
          _Note(tr('ينشئ التطبيق رابط دفع لكل فاتورة ويرسله للعضو، ثم يتحقق تلقائياً من الدفع ويسجله. ابدأ بمفتاح الاختبار (test) وجرّب قبل التشغيل الفعلي.')),
        ],
        if (s.payProvider == 'link') ...[
          _Field(tr('الرابط'), s.payLinkTemplate, (v) => s.payLinkTemplate = v.trim(), ltr: true, hint: 'https://ipn.eg/S/yourname/instapay/...'),
          _Note(tr('يمكن استخدام {amount} و {invoice} داخل الرابط. يؤكد الموظف استلام الدفع يدوياً من شاشة الفاتورة.')),
        ],
      ]),
    );
  }
}

class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});
  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> with _AutoSave {
  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    final s = g.settings;
    final withPin = g.staff.all.where((x) => x.active && x.pinHash != null).length;
    final ownerPin = g.staff.all.any((x) => x.active && x.pinHash != null && x.role == Role.owner);
    return Scaffold(
      appBar: AppBar(title: Text(tr('الأمان'))),
      body: ListView(children: [
        SwitchListTile(
          title: Text(tr('طلب الرقم السري عند فتح التطبيق')),
          subtitle: Text(tr('كل موظف يدخل برقمه وتظهر له الشاشات حسب صلاحياته')),
          value: s.requirePin,
          onChanged: !ownerPin
              ? null
              : (v) => setState(() => s.requirePin = v),
        ),
        _Note(ownerPin
            ? tr('{n} موظف لديهم رقم سري. أضف الأرقام من «الموظفون والمدربون».', {'n': withPin})
            : tr('ضع رقماً سرياً للمالك أولاً من «الموظفون والمدربون» حتى لا تُقفل خارج التطبيق.')),
      ]),
    );
  }
}

class DataSettingsScreen extends StatelessWidget {
  const DataSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    final sv = context.services;
    return Scaffold(
      appBar: AppBar(title: Text(tr('البيانات'))),
      body: ListView(children: [
        _Note(tr('بياناتك محفوظة على هذا الجهاز. خذ نسخة احتياطية أسبوعياً وأرسلها لنفسك (Google Drive أو واتساب). يأخذ التطبيق أيضاً نسخة تلقائية يومية داخل الجوال.')),
        ListTile(
          leading: const Icon(Icons.backup_outlined),
          title: Text(tr('أخذ نسخة احتياطية ومشاركتها')),
          subtitle: Text(tr('{m} عضو • {i} فاتورة', {'m': g.members.items.length, 'i': g.invoices.items.length})),
          onTap: () => runAction(context, () async {
            final bytes = await sv.backup.exportBytes();
            await sv.shareFile(bytes, sv.backup.fileName(), 'application/json');
          }),
        ),
        if (g.can(Perm.settings)) ...[
          ListTile(
            leading: const Icon(Icons.restore),
            title: Text(tr('استرجاع من نسخة احتياطية')),
            subtitle: Text(tr('يستبدل كل البيانات الحالية')),
            onTap: () async {
              final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['json']);
              if (f == null || !context.mounted) return;
              if (!await confirm(context, tr('استبدال كل البيانات بالنسخة؟'), danger: true, ok: tr('استرجاع'))) return;
              if (!context.mounted) return;
              await runAction(context, () async => sv.backup.restore(await f.readAsBytes()), success: tr('تم الاسترجاع ✓'));
            },
          ),
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: Text(tr('استيراد الأعضاء من Excel (CSV)')),
            subtitle: Text(tr('احفظ الجدول من Excel بصيغة CSV. الأعمدة: الاسم، الجوال، الجنس، الباقة، تاريخ الانتهاء، الرصيد')),
            isThreeLine: true,
            trailing: lockFor(context, Feature.importExport),
            onTap: () async {
              if (!await ensureFeature(context, Feature.importExport)) return;
              final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['csv', 'txt']);
              if (f == null || !context.mounted) return;
              final res = await runAction(context, () async => MemberImporter(g).importCsv(utf8.decode(await f.readAsBytes(), allowMalformed: true)));
              if (res == null || !context.mounted) return;
              await showDialog(
                context: context,
                builder: (c) => AlertDialog(
                  title: Text(tr('نتيجة الاستيراد')),
                  content: SingleChildScrollView(
                    child: Text([
                      tr('أعضاء: {n}', {'n': res.members}),
                      tr('اشتراكات: {n}', {'n': res.subscriptions}),
                      tr('تم تخطي: {n}', {'n': res.skipped}),
                      ...res.errors.take(20),
                    ].join('\n')),
                  ),
                  actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('حسناً')))],
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.table_view_outlined),
            title: Text(tr('تصدير الأعضاء (CSV)')),
            trailing: lockFor(context, Feature.importExport),
            onTap: () => runAction(context, () async {
              g.require(Feature.importExport);
              final ms = sv.members;
              final rows = <List<Object?>>[
                [tr('رقم العضوية'), tr('الاسم'), tr('الجوال'), tr('الجنس'), tr('الباقة'), tr('البداية'), tr('الانتهاء'), tr('الرصيد')],
                for (final m in g.members.all)
                  if (ms.currentSub(m.id) case final s)
                    [m.code, m.name, m.phone, m.gender == Gender.female ? tr('أنثى') : (m.gender == Gender.male ? tr('ذكر') : ''), s?.planName, s == null ? '' : dayKey(s.start), s == null ? '' : dayKey(s.end), g.balanceOf(m.id)],
              ];
              await sv.shareFile(Uint8List.fromList(utf8.encode(toCsv(rows))), 'members-${dayKey(g.today)}.csv', 'text/csv');
            }),
          ),
          if (g.isEmpty || g.members.items.length < 5)
            ListTile(
              leading: const Icon(Icons.science_outlined),
              title: Text(tr('تحميل بيانات تجريبية')),
              onTap: () => runAction(context, () => DemoData(g).generate(), success: tr('تم')),
            ),
          const Divider(),
          ListTile(
            leading: Icon(Icons.delete_forever, color: context.colors.error),
            title: Text(tr('مسح كل البيانات'), style: TextStyle(color: context.colors.error)),
            onTap: () async {
              final t = await askText(context, tr('اكتب «مسح» للتأكيد'));
              if (t?.trim() != 'مسح' && t?.trim().toLowerCase() != 'delete') return;
              if (!context.mounted) return;
              await g.wipe();
              if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
            },
          ),
        ],
      ]),
    );
  }
}

class CouponsScreen extends StatelessWidget {
  const CouponsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    final list = g.coupons.all.toList();
    return Scaffold(
      appBar: AppBar(title: Text(tr('كوبونات الخصم'))),
      floatingActionButton: FloatingActionButton(onPressed: () => _edit(context, null), child: const Icon(Icons.add)),
      body: list.isEmpty
          ? EmptyState(icon: Icons.local_offer_outlined, title: tr('لا توجد كوبونات'), message: tr('مثال: RAMADAN20 خصم 20% حتى نهاية الشهر'))
          : ListView(children: [
              for (final c in list)
                ListTile(
                  leading: Icon(Icons.local_offer, color: c.active ? context.colors.primary : context.colors.outline),
                  title: Text(c.code, style: const TextStyle(fontWeight: FontWeight.w800), textDirection: TextDirection.ltr),
                  subtitle: Text([
                    c.percent ? '${fmtNum(c.value)}%' : fmtMoney(c.value),
                    if (c.validUntil != null) '${tr('حتى')} ${dayKey(c.validUntil!)}',
                    tr('استُخدم {n}', {'n': c.uses}) + (c.maxUses > 0 ? '/${c.maxUses}' : ''),
                  ].join(' • ')),
                  trailing: Switch(value: c.active, onChanged: (v) {
                    c.active = v;
                    g.put(c);
                  }),
                  onTap: () => _edit(context, c),
                ),
            ]),
    );
  }

  Future<void> _edit(BuildContext context, Coupon? c0) async {
    final g = context.gym;
    final c = c0 ?? Coupon(id: newId(), code: '', value: 10);
    final code = TextEditingController(text: c.code);
    final value = TextEditingController(text: fmtNum(c.value));
    final max = TextEditingController(text: c.maxUses == 0 ? '' : '${c.maxUses}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(tr('كوبون')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: code, textCapitalization: TextCapitalization.characters, decoration: InputDecoration(labelText: tr('الرمز'))),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(controller: value, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: tr('القيمة')))),
              const SizedBox(width: 8),
              SegmentedButton<bool>(
                segments: [const ButtonSegment(value: true, label: Text('%')), ButtonSegment(value: false, label: Text(Money.symbol))],
                selected: {c.percent},
                onSelectionChanged: (v) => set(() => c.percent = v.first),
              ),
            ]),
            const SizedBox(height: 10),
            TextField(controller: max, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('أقصى عدد استخدامات (فارغ = بلا حد)'))),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('صالح حتى')),
              trailing: Text(c.validUntil == null ? tr('دائماً') : dayKey(c.validUntil!)),
              onTap: () async {
                final d = await pickDay(ctx, c.validUntil ?? addDays(g.today, 30));
                set(() => c.validUntil = d);
              },
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('إلغاء'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('حفظ'))),
          ],
        ),
      ),
    );
    if (ok != true || code.text.trim().isEmpty) return;
    c
      ..code = code.text.trim().toUpperCase()
      ..value = parseAmount(value.text) ?? 0
      ..maxUses = int.tryParse(max.text) ?? 0;
    await g.put(c);
  }
}
