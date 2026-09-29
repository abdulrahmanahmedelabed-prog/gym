import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/money.dart';
import '../../models/billing.dart';
import '../../models/member.dart';
import '../../models/settings.dart';
import '../../services/templates.dart';
import '../screens/sale_screen.dart';
import 'common.dart';
import 'pay_widgets.dart';

/// تحصيل دفعة: على فاتورة محددة أو من رصيد العضو (يوزَّع على الأقدم)
Future<void> showCollectDialog(BuildContext context, {Invoice? invoice, String? memberId}) async {
  final g = context.gym;
  final due = invoice?.balance ?? g.balanceOf(memberId!);
  if (due <= 0) {
    context.toast(tr('لا يوجد مبلغ مستحق'));
    return;
  }
  final amount = TextEditingController(text: roundMoney(due).toString());
  final pay = PayChoice();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: Text(tr('تحصيل دفعة')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr('المستحق: {a}', {'a': fmtMoney(due)})),
            const SizedBox(height: 12),
            TextField(
              controller: amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: tr('المبلغ'), prefixIcon: const Icon(Icons.payments_outlined)),
            ),
            const SizedBox(height: 12),
            PayPicker(choice: pay, amount: parseAmount(amount.text) ?? due),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('إلغاء'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('تحصيل'))),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  final a = parseAmount(amount.text) ?? 0;
  final sv = context.services;
  final pays = await runAction(context, () async {
    if (invoice != null) {
      return [await sv.billing.collect(invoice, a, pay.method, reference: pay.ref, account: pay.accountName, verified: pay.isVerified)];
    }
    return sv.billing.collectFromMember(memberId!, a, pay.method, reference: pay.ref, account: pay.accountName, verified: pay.isVerified);
  }, success: tr('تم تسجيل الدفعة ✓'));
  if (pays == null || pays.isEmpty || !context.mounted) return;
  // إيصال للعضو
  final inv = g.invoices[pays.last.invoiceId]!;
  final msg = sv.reminders.receipt(inv, pays.last);
  if (msg == null) return;
  final m = g.members[inv.memberId];
  if (m != null && sv.dispatcher.isAuto(m.channel)) {
    await g.put(msg);
    await sv.dispatcher.sendOne(msg);
  } else if (context.mounted) {
    final send = await confirm(context, tr('إرسال إيصال للعضو؟'), message: msg.body, ok: tr('إرسال'));
    if (send && context.mounted) await runAction(context, () => sv.send(msg));
  }
}

/// كتابة رسالة لعضو (أو أكثر) مع قوالب جاهزة
Future<void> showComposeDialog(BuildContext context, Member m, {String? initial}) async {
  final g = context.gym;
  final sv = context.services;
  final ctx = TemplateContext(g);
  final sub = sv.members.currentSub(m.id);
  final text = TextEditingController(text: initial ?? '');
  var channel = m.channel;
  final quick = <(String, String)>[
    if (sub != null) (tr('تذكير بالانتهاء'), renderTemplate(g.settings.template(Rk.expirySoon), ctx.forSub(m, sub))),
    if (g.balanceOf(m.id) > 0)
      (tr('تذكير بالمستحق'), tr('مرحباً {n}، نذكّرك بمبلغ {a} مستحق لدى {g}.\n{p}', {'n': m.firstName, 'a': fmtMoney(g.balanceOf(m.id)), 'g': g.settings.gymName, 'p': ctx.payInfo()})),
    if (sub != null && g.lastVisit(m.id) != null)
      (tr('غياب'), renderTemplate(g.settings.template(Rk.inactive), {...ctx.forSub(m, sub), 'days': '${daysBetween(g.lastVisit(m.id)!.time, g.today)}'})),
    (tr('عرض خاص'), tr('مرحباً {n} 👋\nعرض خاص لك في {g}: خصم على التجديد هذا الأسبوع فقط! 💪', {'n': m.firstName, 'g': g.settings.gymName})),
  ];
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: Text(tr('رسالة إلى {n}', {'n': m.firstName})),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final q in quick) ActionChip(label: Text(q.$1), onPressed: () => set(() => text.text = q.$2)),
              ]),
              const SizedBox(height: 10),
              TextField(controller: text, maxLines: 6, minLines: 3, decoration: InputDecoration(hintText: tr('اكتب رسالتك...'))),
              const SizedBox(height: 10),
              SegmentedButton<Channel>(
                segments: [
                  ButtonSegment(value: Channel.whatsapp, label: Text(tr('واتساب')), icon: const Icon(Icons.chat)),
                  ButtonSegment(value: Channel.sms, label: Text(tr('SMS')), icon: const Icon(Icons.sms_outlined)),
                ],
                selected: {channel},
                onSelectionChanged: (v) => set(() => channel = v.first),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('إلغاء'))),
          FilledButton.icon(onPressed: () => Navigator.pop(c, true), icon: const Icon(Icons.send), label: Text(tr('إرسال'))),
        ],
      ),
    ),
  );
  if (ok != true || text.text.trim().isEmpty || !context.mounted) return;
  final msg = sv.reminders.custom(m, text.text.trim(), channel: channel);
  if (msg == null) {
    context.toast(tr('رقم غير صحيح'), error: true);
    return;
  }
  final r = await runAction(context, () => sv.send(msg));
  if (r != null && context.mounted) context.toast(r);
}

/// بطاقة معلومات الاشتراك (للملف الشخصي وشاشة الدخول)
class SubProgress extends StatelessWidget {
  final int daysTotal;
  final int daysLeft;
  final int? visitsTotal;
  final int? visitsLeft;
  const SubProgress({super.key, required this.daysTotal, required this.daysLeft, this.visitsTotal, this.visitsLeft});

  @override
  Widget build(BuildContext context) {
    final useVisits = visitsTotal != null && visitsTotal! > 0;
    final frac = useVisits ? (visitsLeft ?? 0) / visitsTotal! : (daysTotal <= 0 ? 0.0 : (daysLeft + 1) / daysTotal);
    final color = frac > 0.3 ? const Color(0xFF16A34A) : (frac > 0.1 ? const Color(0xFFF59E0B) : const Color(0xFFDC2626));
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LinearProgressIndicator(value: frac.clamp(0.0, 1.0), minHeight: 8, color: color, backgroundColor: context.colors.surfaceContainerHighest),
    );
  }
}

Future<void> openSale(BuildContext context, String memberId) => context.push(SaleScreen(memberId: memberId));
