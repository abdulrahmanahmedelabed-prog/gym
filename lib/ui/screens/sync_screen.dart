import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../services/license.dart';
import '../../services/sync.dart';
import '../widgets/common.dart';
import '../widgets/pay_widgets.dart';
import '../widgets/upgrade.dart';
import 'pay_accounts_screen.dart';

String syncPhaseLabel(SyncService s) => switch (s.phase) {
  SyncPhase.off => tr('غير مفعلة'),
  SyncPhase.synced => tr('متزامن'),
  SyncPhase.syncing => tr('جارٍ المزامنة...'),
  SyncPhase.pending => tr('{n} تعديل بانتظار الرفع', {'n': s.pending}),
  SyncPhase.offline => tr('بدون نت — {n} تعديل محفوظ على الجهاز', {'n': s.pending}),
  SyncPhase.error => tr('خطأ في المزامنة'),
  SyncPhase.locked => tr('متوقفة (الترخيص)'),
};

IconData syncPhaseIcon(SyncPhase p) => switch (p) {
  SyncPhase.off => Icons.cloud_off_outlined,
  SyncPhase.synced => Icons.cloud_done_outlined,
  SyncPhase.syncing => Icons.cloud_sync_outlined,
  SyncPhase.pending => Icons.cloud_upload_outlined,
  SyncPhase.offline => Icons.cloud_off_outlined,
  SyncPhase.error => Icons.sync_problem_outlined,
  SyncPhase.locked => Icons.cloud_off_outlined,
};

String _when(DateTime? t) {
  if (t == null) return tr('لم تتم بعد');
  final l = t.toLocal();
  return '${dayKey(l)} ${hhmm(l.hour * 60 + l.minute)}';
}

/// أيقونة حالة المزامنة (في الرئيسية) — تظهر فقط عند تفعيل المزامنة
class SyncStatusButton extends StatelessWidget {
  const SyncStatusButton({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SyncService>();
    if (!s.enabled) return const SizedBox.shrink();
    final warn = s.phase == SyncPhase.error || s.phase == SyncPhase.locked;
    return IconButton(
      tooltip: syncPhaseLabel(s),
      onPressed: () => context.push(const SyncScreen()),
      icon: Badge(
        isLabelVisible: s.pending > 0,
        label: Text('${s.pending}'),
        child: Icon(syncPhaseIcon(s.phase), color: warn ? context.colors.error : null),
      ),
    );
  }
}

/// المزامنة السحابية: التطبيق يعمل كاملاً بدون نت، وعند توفره تتزامن الأجهزة تلقائياً
class SyncScreen extends StatelessWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SyncService>();
    final g = context.gymWatch;
    return Scaffold(
      appBar: AppBar(title: Text(tr('المزامنة السحابية'))),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              tr(
                'كل شيء يُحفظ على هذا الجهاز أولاً، والتطبيق يعمل بالكامل بدون إنترنت. عند توفر النت تُرفع تعديلاتك وتصل تعديلات أجهزة النادي الأخرى تلقائياً، وتبقى نسخة من بياناتك على السحابة إن ضاع الجهاز.',
              ),
              style: TextStyle(color: context.colors.onSurfaceVariant),
            ),
          ),
          if (!s.enabled) ..._setup(context, s, g.has(Feature.cloudSync)) else ..._status(context, s),
        ],
      ),
    );
  }

  List<Widget> _setup(BuildContext context, SyncService s, bool allowed) => [
    Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_upload_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(tr('أول جهاز في النادي'), style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
                if (!allowed) TierBadge(featureTier[Feature.cloudSync]!),
              ],
            ),
            const SizedBox(height: 6),
            Text(tr('يرفع بيانات هذا الجهاز إلى السحابة ويعطيك رمزاً لربط باقي الأجهزة.')),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.cloud_upload),
              label: Text(tr('تفعيل المزامنة على هذا الجهاز')),
              onPressed: () async {
                if (!await ensureFeature(context, Feature.cloudSync)) return;
                if (!context.mounted) return;
                var url = '', key = '';
                if (!SyncService.vendorServer) {
                  final r = await _askServer(context);
                  if (r == null) return;
                  (url, key) = r;
                }
                if (!context.mounted) return;
                await runAction(context, () async {
                  await s.create(url: url.isEmpty ? null : url, key: key.isEmpty ? null : key);
                }, success: tr('تم رفع بيانات النادي ✓'));
              },
            ),
          ],
        ),
      ),
    ),
    Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.devices_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(tr('ربط بجهاز النادي'), style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(tr('على الجهاز الأول افتح: الإعدادات › المزامنة السحابية › إضافة جهاز، ثم امسح الرمز من هنا.')),
            const SizedBox(height: 12),
            JoinButtons(sync: s),
          ],
        ),
      ),
    ),
  ];

  List<Widget> _status(BuildContext context, SyncService s) {
    final limit = context.gym.license.syncDeviceLimit;
    final warn = s.phase == SyncPhase.error || s.phase == SyncPhase.locked;
    return [
      Card(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        color: (warn ? context.colors.errorContainer : context.colors.primaryContainer).withValues(alpha: 0.5),
        child: Column(
          children: [
            ListTile(
              leading: Icon(syncPhaseIcon(s.phase), size: 32),
              title: Text(syncPhaseLabel(s), style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(tr('آخر مزامنة: {t}', {'t': _when(s.lastSync)})),
            ),
            if (s.lastError != null && s.phase != SyncPhase.synced)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(s.lastError!, style: TextStyle(color: warn ? context.colors.error : null)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(tr('الأجهزة: {n} من {l} • هذا الجهاز رقم {s}', {'n': s.devices == 0 ? 1 : s.devices, 'l': limit, 's': s.slot})),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: s.phase == SyncPhase.syncing ? null : () => s.syncNow(),
                    icon: const Icon(Icons.sync),
                    label: Text(tr('مزامنة الآن')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      ListTile(
        leading: const Icon(Icons.qr_code_2),
        title: Text(tr('إضافة جهاز')),
        subtitle: Text(tr('اعرض رمز الربط وامسحه من الجهاز الجديد')),
        trailing: (s.devices >= limit && limit < proSyncDevices) ? TierBadge(featureTier[Feature.multiDevice]!) : null,
        onTap: () => _showJoinCode(context, s),
      ),
      SwitchListTile(
        secondary: const Icon(Icons.star_outline),
        title: Text(tr('الجهاز الرئيسي')),
        subtitle: Text(tr('يجهّز التذكيرات الآلية ويرسلها ويفحص روابط الدفع. فعّله على جهاز واحد فقط (جهاز الاستقبال) حتى لا تتكرر الرسائل.')),
        value: s.isMain,
        onChanged: (v) => s.setMain(v),
      ),
      const Divider(),
      ListTile(
        leading: Icon(Icons.link_off, color: context.colors.error),
        title: Text(tr('إيقاف المزامنة على هذا الجهاز'), style: TextStyle(color: context.colors.error)),
        subtitle: Text(tr('تبقى البيانات على هذا الجهاز وعلى السحابة. التعديلات التي لم تُرفع بعد ستبقى هنا فقط.')),
        onTap: () async {
          if (!await confirm(context, tr('إيقاف المزامنة؟'), danger: true, ok: tr('إيقاف'))) return;
          await s.leave();
        },
      ),
    ];
  }

  Future<void> _showJoinCode(BuildContext context, SyncService s) async {
    final code = s.joinCode;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('رمز ربط جهاز جديد')),
        content: SizedBox(
          width: 320,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(8),
                  child: QrImageView(data: code, size: 200),
                ),
                const SizedBox(height: 10),
                SelectableText(code, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 11)),
                const SizedBox(height: 10),
                Text(
                  tr('من يملك هذا الرمز يصل لبيانات النادي. لا ترسله إلا لأجهزة ناديك.'),
                  style: TextStyle(color: Theme.of(c).colorScheme.error, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (c.mounted) Navigator.pop(c);
            },
            child: Text(tr('نسخ الرمز')),
          ),
          FilledButton(onPressed: () => Navigator.pop(c), child: Text(tr('تم'))),
        ],
      ),
    );
  }

  Future<(String, String)?> _askServer(BuildContext context) async {
    final url = TextEditingController();
    final key = TextEditingController();
    return showDialog<(String, String)>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('خادم المزامنة')),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tr('أدخل عنوان مشروع Supabase ومفتاح anon (بعد تنفيذ ملف server/supabase_sync.sql). يُعطى لك مع النسخة المدفوعة.')),
                const SizedBox(height: 10),
                TextField(
                  controller: url,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(labelText: 'Project URL', hintText: 'https://xxxx.supabase.co'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: key,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(labelText: 'anon key'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('إلغاء'))),
          FilledButton(
            onPressed: () {
              if (url.text.trim().isEmpty || key.text.trim().isEmpty) return;
              Navigator.pop(c, (url.text.trim(), key.text.trim()));
            },
            child: Text(tr('متابعة')),
          ),
        ],
      ),
    );
  }
}

/// أزرار ربط الجهاز بنادٍ موجود (مسح الرمز أو لصقه) — في شاشة المزامنة وشاشة أول تشغيل
class JoinButtons extends StatelessWidget {
  final SyncService sync;
  const JoinButtons({super.key, required this.sync});

  Future<void> _join(BuildContext context, String? code) async {
    if (code == null || code.trim().isEmpty) return;
    if (!await ensureFeature(context, Feature.cloudSync)) return;
    if (!context.mounted) return;
    final hasData = !context.gym.isEmpty;
    if (hasData &&
        !await confirm(
          context,
          tr('استبدال بيانات هذا الجهاز؟'),
          message: tr('ستُحذف البيانات الموجودة على هذا الجهاز وتُستبدل ببيانات النادي من السحابة.'),
          danger: true,
          ok: tr('ربط'),
        )) {
      return;
    }
    if (!context.mounted) return;
    await runAction(context, () => sync.join(code), success: tr('تم ربط الجهاز واستلام بيانات النادي ✓'));
    if (sync.enabled && sync.lastError == null && context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      if (canScanWithCamera)
        FilledButton.tonalIcon(
          icon: const Icon(Icons.qr_code_scanner),
          label: Text(tr('مسح رمز الربط')),
          onPressed: () async {
            final v = await context.push<String>(const ScanQrScreen());
            if (context.mounted) await _join(context, v);
          },
        ),
      OutlinedButton.icon(
        icon: const Icon(Icons.content_paste),
        label: Text(tr('لصق الرمز')),
        onPressed: () async {
          final v = await askText(context, tr('رمز الربط'), hint: 'NS1....', ok: tr('ربط'));
          if (context.mounted) await _join(context, v);
        },
      ),
    ],
  );
}
