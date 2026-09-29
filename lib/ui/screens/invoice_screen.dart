import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/money.dart';
import '../../models/billing.dart';
import '../../models/business.dart';
import '../../models/member.dart';
import '../../services/reports.dart';
import '../theme.dart';
import '../../services/license.dart';
import '../widgets/upgrade.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import '../widgets/pay_widgets.dart';
import 'member_detail_screen.dart';

class InvoiceScreen extends StatelessWidget {
  final String invoiceId;
  const InvoiceScreen({super.key, required this.invoiceId});

  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    final inv = g.invoices[invoiceId];
    if (inv == null) return Scaffold(appBar: AppBar(), body: EmptyState(icon: Icons.receipt_long, title: tr('الفاتورة غير موجودة')));
    final sv = context.services;
    final m = g.members[inv.memberId];
    final pays = g.paymentsOf(inv.id).toList()..sort((a, b) => a.date.compareTo(b.date));
    final st = inv.status;
    final (label, color) = switch (st) {
      InvoiceStatus.paid => (tr('مدفوعة بالكامل'), StatusColors.active),
      InvoiceStatus.partial => (tr('مدفوعة جزئياً'), StatusColors.expiring),
      InvoiceStatus.unpaid => (tr('غير مدفوعة'), StatusColors.expired),
      InvoiceStatus.voided => (tr('ملغاة'), StatusColors.none),
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(inv.number),
        actions: [
          IconButton(
              tooltip: tr('طباعة'),
              icon: const Icon(Icons.print_outlined),
              onPressed: () async {
                if (await ensureFeature(context, Feature.pdfPrint) && context.mounted) await _print(context, inv);
              }),
          IconButton(
              tooltip: tr('مشاركة PDF'),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              onPressed: () async {
                if (await ensureFeature(context, Feature.pdfPrint) && context.mounted) await runAction(context, () => sv.shareInvoicePdf(inv));
              }),
          PopupMenuButton<String>(
            onSelected: (v) => _menu(context, v, inv),
            itemBuilder: (_) => [
              if (!inv.voided && inv.paid > 0 && g.can(Perm.refund))
                PopupMenuItem(value: 'refund', child: ListTile(leading: const Icon(Icons.undo), title: Text(tr('استرداد مبلغ')))),
              if (!inv.voided && g.can(Perm.refund))
                PopupMenuItem(value: 'void', child: ListTile(leading: Icon(Icons.block, color: context.colors.error), title: Text(tr('إلغاء الفاتورة')))),
              PopupMenuItem(value: 'text', child: ListTile(leading: const Icon(Icons.copy), title: Text(tr('نسخ نص الفاتورة')))),
            ],
          ),
        ],
      ),
      bottomNavigationBar: inv.voided
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  if (inv.balance > 0 && g.can(Perm.sell)) ...[
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => showCollectDialog(context, invoice: inv),
                        icon: const Icon(Icons.payments_outlined),
                        label: Text(tr('تحصيل')),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (m != null)
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
                        onPressed: () => _send(context, inv, m),
                        icon: const Icon(Icons.send),
                        label: Text(tr('إرسال')),
                      ),
                    ),
                ]),
              ),
            ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (inv.pendingPlanId != null && !inv.voided)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              color: StatusColors.frozen.withValues(alpha: 0.08),
              child: ListTile(
                leading: const Icon(Icons.autorenew, color: StatusColors.frozen),
                title: Text(tr('فاتورة تجديد'), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(tr('يتجدد الاشتراك تلقائياً عند اكتمال الدفع')),
              ),
            ),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Pill(label, color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${dayKey(inv.date)}  ${hhmm(minutesOfDay(inv.date))}',
                      textAlign: TextAlign.end, style: TextStyle(color: context.colors.onSurfaceVariant)),
                ),
              ]),
              const SizedBox(height: 12),
              if (m != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: MemberAvatar(m),
                  title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('#${m.code} • ${m.phone}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(MemberDetailScreen(memberId: m.id)),
                )
              else
                Text(inv.customerName ?? tr('زائر'), style: const TextStyle(fontWeight: FontWeight.w700)),
              if (inv.voided) Text('${tr('سبب الإلغاء')}: ${inv.voidReason ?? ''}', style: TextStyle(color: context.colors.error)),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              for (final i in inv.items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Text('${i.description}${i.qty != 1 ? '  ×${fmtNum(i.qty)}' : ''}')),
                    const SizedBox(width: 8),
                    Text(fmtMoney(i.total), style: const TextStyle(fontWeight: FontWeight.w600)),
                  ]),
                ),
              const Divider(height: 20),
              if (inv.discount > 0) InfoRow(tr('الخصم'), '- ${fmtMoney(inv.discount)}'),
              if (inv.taxRate > 0) InfoRow('${tr('الضريبة')} ${fmtNum(inv.taxRate * 100)}%', fmtMoney(inv.tax)),
              InfoRow(tr('الإجمالي'), fmtMoney(inv.total), bold: true),
              InfoRow(tr('المدفوع'), fmtMoney(inv.paid), color: StatusColors.active),
              if (inv.balance > 0) InfoRow(tr('المتبقي'), fmtMoney(inv.balance), bold: true, color: StatusColors.expired),
            ]),
          ),
        ),
        if (inv.installments.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(tr('الأقساط'), style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Card(
            child: Column(children: [
              for (final x in inv.installmentStatus())
                ListTile(
                  dense: true,
                  leading: Icon(x.left <= 0 ? Icons.check_circle : Icons.schedule,
                      color: x.left <= 0 ? StatusColors.active : (x.inst.due.isBefore(g.today) ? StatusColors.expired : StatusColors.expiring)),
                  title: Text(dayKey(x.inst.due)),
                  subtitle: x.left > 0 && x.paid > 0 ? Text(tr('دُفع {a}', {'a': fmtMoney(x.paid)})) : null,
                  trailing: Text(fmtMoney(x.inst.amount), style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
            ]),
          ),
        ],
        const SizedBox(height: 12),
        Text(tr('الدفعات'), style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        if (pays.isEmpty) Text(tr('لا توجد دفعات'), style: TextStyle(color: context.colors.onSurfaceVariant)),
        if (pays.isNotEmpty)
          Card(
            child: Column(children: [
              for (final p in pays)
                ListTile(
                  dense: true,
                  leading: Icon(p.isRefund ? Icons.undo : Icons.south_east, color: p.isRefund ? StatusColors.expired : StatusColors.active),
                  title: Row(children: [
                    Flexible(child: Text('${p.account ?? payMethodName(p.method)}${p.reference == null ? '' : ' • ${p.reference}'}')),
                    if (p.needsCheck) ...[const SizedBox(width: 6), Pill(tr('بانتظار التأكد'), StatusColors.expiring)],
                  ]),
                  subtitle: Text([p.number, dayKey(p.date), if (p.by != null) p.by!, if (p.note != null) p.note!].join(' • ')),
                  trailing: Text(fmtMoney(p.amount), style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
            ]),
          ),
        if (!inv.voided && (inv.balance > 0 || inv.links.isNotEmpty)) ...[
          const SizedBox(height: 16),
          _PaymentLinks(inv: inv),
        ],
        const SizedBox(height: 24),
      ]),
    );
  }

  Future<void> _print(BuildContext context, Invoice inv) async {
    final sv = context.services;
    final v = await pickFromSheet<bool>(context, tr('طباعة'), [
      (false, tr('ورق A4'), Icons.description_outlined),
      (true, tr('إيصال حراري 80مم'), Icons.receipt_outlined),
    ]);
    if (v == null || !context.mounted) return;
    await runAction(context, () => sv.printInvoice(inv, thermal: v));
  }

  Future<void> _send(BuildContext context, Invoice inv, Member m) async {
    final sv = context.services;
    final v = await pickFromSheet<String>(context, tr('إرسال الفاتورة'), [
      ('wa', tr('رسالة واتساب (نص الفاتورة)'), Icons.chat),
      ('sms', tr('رسالة SMS'), Icons.sms_outlined),
      ('pdf', tr('ملف PDF (اختر واتساب من قائمة المشاركة)'), Icons.picture_as_pdf_outlined),
      if (inv.balance > 0 && context.gym.has(Feature.walletQr) && context.gym.settings.activeAccounts.any((a) => a.qr.isNotEmpty))
        ('qr', tr('طلب دفع: صورة رمز QR + المبلغ'), Icons.qr_code_2),
    ]);
    if (v == null || !context.mounted) return;
    if (v == 'qr') {
      final acc = context.gym.settings.activeAccounts.firstWhere((a) => a.qr.isNotEmpty);
      await runAction(context, () async {
        final png = await payQrPng(acc, amount: inv.balance, title: context.gym.settings.gymName);
        final text = tr('مرحباً {n}، المطلوب {a} (فاتورة {i}). امسح الرمز من تطبيق البنك أو المحفظة، ثم أرسل لنا رقم العملية. شكراً 🙏',
            {'n': m.firstName, 'a': fmtMoney(inv.balance), 'i': inv.number});
        await sv.shareFile(png, 'pay-${inv.number}.png', 'image/png', text: text);
      });
      return;
    }
    if (v == 'pdf') {
      if (!await ensureFeature(context, Feature.pdfPrint) || !context.mounted) return;
      await runAction(context, () => sv.shareInvoicePdf(inv));
      return;
    }
    final r = await runAction(context, () => sv.sendInvoice(inv, channel: v == 'wa' ? Channel.whatsapp : Channel.sms));
    if (r != null && context.mounted) context.toast(r);
  }

  Future<void> _menu(BuildContext context, String v, Invoice inv) async {
    final sv = context.services;
    switch (v) {
      case 'refund':
        final a = await askText(context, tr('مبلغ الاسترداد'), initial: roundMoney(inv.paid).toString(), number: true);
        if (a == null || !context.mounted) return;
        final reason = await askText(context, tr('سبب الاسترداد'));
        if (reason == null || !context.mounted) return;
        await runAction(context, () => sv.billing.refund(inv, parseAmount(a) ?? 0, PayMethod.cash, reason), success: tr('تم الاسترداد'));
      case 'void':
        final reason = await askText(context, tr('سبب إلغاء الفاتورة'));
        if (reason == null || !context.mounted) return;
        await runAction(context, () => sv.billing.voidInvoice(inv, reason), success: tr('أُلغيت الفاتورة'));
      case 'text':
        await Clipboard.setData(ClipboardData(text: sv.reminders.invoiceText(inv)));
        if (context.mounted) context.toast(tr('نُسخ النص'));
    }
  }
}

/// روابط الدفع الإلكتروني للفاتورة
class _PaymentLinks extends StatelessWidget {
  final Invoice inv;
  const _PaymentLinks({required this.inv});

  @override
  Widget build(BuildContext context) {
    final g = context.gym;
    final sv = context.services;
    final enabled = sv.payLinks.enabled;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.link),
            const SizedBox(width: 8),
            Expanded(child: Text(tr('الدفع الإلكتروني'), style: const TextStyle(fontWeight: FontWeight.w800))),
            if (enabled && inv.links.any((l) => l.status == LinkStatus.pending))
              TextButton(
                onPressed: () => runAction(context, () async {
                  final n = await sv.payLinks.checkPending();
                  return n;
                }, success: tr('تم التحقق')),
                child: Text(tr('تحقق من الدفع')),
              ),
          ]),
          for (final l in inv.links.reversed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text('${l.provider} • ${fmtMoney(l.amount)}'),
              subtitle: Text(l.url, maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr),
              trailing: l.status == LinkStatus.pending
                  ? PopupMenuButton<String>(
                      onSelected: (v) async {
                        switch (v) {
                          case 'copy':
                            await Clipboard.setData(ClipboardData(text: l.url));
                          case 'paid':
                            await runAction(context, () => sv.payLinks.markLinkPaidManually(inv, l), success: tr('سُجّل الدفع'));
                          case 'cancel':
                            await runAction(context, () => sv.payLinks.cancelLink(inv, l));
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(value: 'copy', child: Text(tr('نسخ الرابط'))),
                        PopupMenuItem(value: 'paid', child: Text(tr('تأكيد استلام الدفع يدوياً'))),
                        PopupMenuItem(value: 'cancel', child: Text(tr('إلغاء الرابط'))),
                      ],
                    )
                  : Pill(l.status == LinkStatus.paid ? tr('مدفوع') : tr('ملغي'), l.status == LinkStatus.paid ? StatusColors.active : StatusColors.none),
            ),
          if (inv.balance > 0)
            enabled
                ? OutlinedButton.icon(
                    onPressed: () async {
                      final link = await runAction(context, () => sv.payLinks.createLink(inv));
                      if (link == null || !context.mounted) return;
                      final m = g.members[inv.memberId];
                      if (m == null) {
                        await Clipboard.setData(ClipboardData(text: link.url));
                        if (context.mounted) context.toast(tr('نُسخ الرابط'));
                        return;
                      }
                      final r = await runAction(context, () => sv.sendInvoice(inv));
                      if (r != null && context.mounted) context.toast(r);
                    },
                    icon: const Icon(Icons.add_link),
                    label: Text(tr('إنشاء رابط دفع وإرساله للعضو')),
                  )
                : Text(tr('فعّل بوابة دفع من الإعدادات (Stripe، ميسّر، Tap أو رابط انستاباي/محفظة) ليدفع العضو من جواله'),
                    style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 13)),
        ]),
      ),
    );
  }
}
