import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/money.dart';
import '../../core/vendor.dart';
import '../../services/license.dart';
import '../../models/business.dart';
import '../widgets/common.dart';
import '../widgets/upgrade.dart';

String periodName(String p) => switch (p) {
      'monthly' => tr('شهرياً'),
      'yearly' => tr('سنوياً'),
      'lifetime' => tr('مدى الحياة'),
      _ => p,
    };

/// الترخيص والباقات: مقارنة، شراء بالمحافظ أو الرمز الموحد، وإدخال مفتاح التفعيل
class LicenseScreen extends StatefulWidget {
  const LicenseScreen({super.key});
  @override
  State<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends State<LicenseScreen> {
  final _key = TextEditingController();

  Future<void> _activate() async {
    final g = context.gym;
    final st = await runAction(context, () => g.license.activate(_key.text));
    if (st == null || !mounted) return;
    g.touch();
    _key.clear();
    context.toast(tr('تم التفعيل ✓ {l}', {'l': st.label}));
  }

  Future<void> _requestActivation(Tier tier) async {
    final g = context.gym;
    final prices = tier == Tier.pro ? Vendor.proPrices : Vendor.plusPrices;
    var period = prices.last.period;
    var account = Vendor.accounts.isEmpty ? '' : Vendor.accounts.first.name;
    final ref = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(tr('طلب تفعيل {t}', {'t': tierName(tier)})),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Wrap(spacing: 6, children: [
                  for (final p in prices)
                    ChoiceChip(
                      label: Text('${periodName(p.period)} — ${fmtNum(p.amount)} ${Vendor.currency}'),
                      selected: period == p.period,
                      onSelected: (_) => set(() => period = p.period),
                    ),
                ]),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: account.isEmpty ? null : account,
                  decoration: InputDecoration(labelText: tr('حوّلت عبر')),
                  items: [for (final a in Vendor.accounts) DropdownMenuItem(value: a.name, child: Text(a.name))],
                  onChanged: (v) => account = v ?? '',
                ),
                const SizedBox(height: 12),
                TextField(controller: ref, decoration: InputDecoration(labelText: tr('رقم العملية / الحوالة'))),
                const SizedBox(height: 8),
                Text(tr('سيفتح واتساب برسالة جاهزة فيها رمز جهازك. يصلك مفتاح التفعيل بعد التأكد من التحويل.'),
                    style: Theme.of(c).textTheme.bodySmall),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('إلغاء'))),
            FilledButton.icon(onPressed: () => Navigator.pop(c, true), icon: const Icon(Icons.send), label: Text(tr('إرسال الطلب'))),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final price = prices.firstWhere((p) => p.period == period);
    final text = [
      tr('طلب تفعيل نادي جيم'),
      '${tr('الباقة')}: ${tierName(tier)} — ${periodName(period)} (${fmtNum(price.amount)} ${Vendor.currency})',
      '${tr('النادي')}: ${g.settings.gymName}',
      '${tr('رمز الجهاز')}: ${g.license.deviceCode}',
      '${tr('حوّلت عبر')}: $account',
      '${tr('رقم العملية')}: ${ref.text.trim()}',
    ].join('\n');
    await runAction(context, () => context.services.openWhatsApp('+${Vendor.whatsapp}', text));
  }

  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    final st = g.license.status();
    final active = st.tier;
    return Scaffold(
      appBar: AppBar(title: Text(tr('الترخيص والباقات'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          color: tierColor(active).withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Icon(Icons.workspace_premium, color: tierColor(active), size: 32),
                const SizedBox(width: 10),
                Expanded(child: Text(st.label, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
              ]),
              if (st.keyError != null)
                Padding(padding: const EdgeInsets.only(top: 6), child: Text(st.keyError!, style: TextStyle(color: context.colors.error))),
              const SizedBox(height: 12),
              Row(children: [
                Text(tr('رمز الجهاز:')),
                const SizedBox(width: 8),
                SelectableText(g.license.deviceCode, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, letterSpacing: 1)),
                IconButton(
                  tooltip: tr('نسخ'),
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: g.license.deviceCode));
                    context.toast(tr('نُسخ رمز الجهاز'));
                  },
                ),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        ResponsiveGrid(minWidth: 260, children: [
          _TierCard(tier: Tier.free, current: active, onBuy: null),
          _TierCard(tier: Tier.plus, current: active, onBuy: () => _requestActivation(Tier.plus)),
          _TierCard(tier: Tier.pro, current: active, onBuy: () => _requestActivation(Tier.pro)),
        ]),
        const SizedBox(height: 20),
        Text(tr('طريقة الشراء'), style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(tr('1. حوّل ثمن الباقة إلى أحد الحسابات (أو امسح الرمز الموحد من أي تطبيق بنكي أو محفظة):')),
              const SizedBox(height: 8),
              for (final a in Vendor.accounts)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.account_balance_wallet_outlined),
                  title: Text(a.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${a.number}${a.holder.isEmpty ? '' : ' — ${a.holder}'}', textDirection: TextDirection.ltr, textAlign: TextAlign.start),
                  trailing: IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: a.number));
                      context.toast(tr('نُسخ'));
                    },
                  ),
                ),
              if (Vendor.qrPayload.isNotEmpty)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    color: Colors.white,
                    child: QrImageView(data: Vendor.qrPayload, size: 180),
                  ),
                ),
              const SizedBox(height: 8),
              Text(tr('2. اضغط «اشترِ» على الباقة واكتب رقم العملية؛ يُرسل الطلب بواتساب مع رمز جهازك.')),
              const SizedBox(height: 4),
              Text(tr('3. الصق مفتاح التفعيل الذي يصلك هنا:')),
              const SizedBox(height: 8),
              TextField(
                controller: _key,
                minLines: 2,
                maxLines: 4,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(hintText: 'NG1.xxxxx.xxxxx'),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(onPressed: _activate, icon: const Icon(Icons.verified), label: Text(tr('تفعيل'))),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          tr('بياناتك تبقى متاحة دائماً: عند انتهاء الاشتراك يعود التطبيق للنسخة المجانية ولا يُحذف شيء.'),
          textAlign: TextAlign.center,
          style: context.text.bodySmall,
        ),
        if (g.license.key != null && g.can(Perm.settings))
          TextButton(
            onPressed: () async {
              if (await confirm(context, tr('إزالة مفتاح التفعيل من هذا الجهاز؟'), danger: true)) {
                await g.license.removeKey();
                g.touch();
              }
            },
            child: Text(tr('إزالة المفتاح')),
          ),
        const SizedBox(height: 24),
        Text('${tr('آخر تحقق')}: ${dayKey(g.license.lastSeen)}', textAlign: TextAlign.center, style: context.text.labelSmall),
      ]),
    );
  }
}

class _TierCard extends StatelessWidget {
  final Tier tier;
  final Tier current;
  final VoidCallback? onBuy;
  const _TierCard({required this.tier, required this.current, this.onBuy});

  @override
  Widget build(BuildContext context) {
    final color = tierColor(tier);
    final features = tier == Tier.free
        ? [
            tr('حتى {n} عضو فعّال', {'n': Vendor.freeMemberLimit}),
            tr('الاشتراكات والتجديد والتجميد'),
            tr('الدخول بمسح QR أو البحث'),
            tr('الدفع النقدي والبطاقة والمحفظة'),
            tr('الفواتير وإرسالها بواتساب'),
            tr('رسائل فردية بواتساب و SMS'),
            tr('النسخ الاحتياطي'),
          ]
        : [
            if (tier == Tier.plus) tr('كل مزايا المجاني وأعضاء بلا حد') else tr('كل مزايا Plus'),
            for (final e in featureTier.entries)
              if (e.value == tier) featureName(e.key),
          ];
    final prices = tier == Tier.pro ? Vendor.proPrices : (tier == Tier.plus ? Vendor.plusPrices : const <VendorPrice>[]);
    final isCurrent = current == tier;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: isCurrent ? color : context.colors.outlineVariant.withValues(alpha: 0.5), width: isCurrent ? 2.5 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text(tierName(tier), style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w900, color: color)),
            const Spacer(),
            if (isCurrent) Pill(tr('الحالية'), color),
          ]),
          const SizedBox(height: 4),
          Text(
            prices.isEmpty ? tr('مجاناً دائماً') : prices.map((p) => '${fmtNum(p.amount)} ${Vendor.currency} ${periodName(p.period)}').join(' • '),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const Divider(height: 20),
          for (final f in features)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.check_circle, size: 18, color: color),
                const SizedBox(width: 6),
                Expanded(child: Text(f)),
              ]),
            ),
          if (onBuy != null && current.index < tier.index) ...[
            const SizedBox(height: 12),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: color), onPressed: onBuy, child: Text(tr('اشترِ {t}', {'t': tierName(tier)}))),
          ],
        ]),
      ),
    );
  }
}

