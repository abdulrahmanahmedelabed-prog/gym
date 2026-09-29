import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/money.dart';
import '../../models/billing.dart';
import '../../models/business.dart';
import '../../services/reports.dart';
import '../theme.dart';
import '../../services/license.dart';
import '../widgets/upgrade.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import 'invoice_screen.dart';
import 'member_detail_screen.dart';
import 'reports_screen.dart';
import 'shop_screen.dart';

const expenseCategories = ['إيجار', 'رواتب', 'كهرباء ومياه', 'صيانة الأجهزة', 'إعلانات', 'مستلزمات', 'نظافة', 'أخرى'];

class FinanceScreen extends StatelessWidget {
  const FinanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    final canExp = g.can(Perm.expenses) && g.has(Feature.fullReports);
    final canRec = g.has(Feature.walletQr);
    final pendingChecks = canRec ? context.services.billing.unverified().length : 0;
    return DefaultTabController(
      length: (canExp ? 4 : 3) + (canRec ? 1 : 0),
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr('المالية')),
          actions: [
            if (g.can(Perm.sell))
              IconButton(
                  tooltip: tr('المتجر'),
                  icon: const Icon(Icons.shopping_bag_outlined),
                  onPressed: () async {
                    if (await ensureFeature(context, Feature.shop) && context.mounted) context.push(const ShopScreen());
                  }),
            if (g.can(Perm.reports))
              IconButton(
                  tooltip: tr('التقارير'),
                  icon: const Icon(Icons.insights_outlined),
                  onPressed: () async {
                    if (await ensureFeature(context, Feature.fullReports) && context.mounted) context.push(const ReportsScreen());
                  }),
          ],
          bottom: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
            Tab(text: tr('الفواتير')),
            Tab(text: tr('الأقساط')),
            Tab(text: tr('المدينون')),
            if (canRec) Tab(child: Badge(isLabelVisible: pendingChecks > 0, label: Text('$pendingChecks'), child: Text(tr('المطابقة')))),
            if (canExp) Tab(text: tr('المصروفات')),
          ]),
        ),
        body: TabBarView(children: [
          const _InvoicesList(),
          const _InstallmentsList(),
          const _DebtorsList(),
          if (canRec) const _Reconciliation(),
          if (canExp) const _ExpensesList(),
        ]),
      ),
    );
  }
}

class InvoiceTile extends StatelessWidget {
  final Invoice inv;
  final bool showMember;
  const InvoiceTile({super.key, required this.inv, this.showMember = true});

  @override
  Widget build(BuildContext context) {
    final g = context.gym;
    final m = g.members[inv.memberId];
    final st = inv.status;
    final (label, color) = switch (st) {
      InvoiceStatus.paid => (tr('مدفوعة'), StatusColors.active),
      InvoiceStatus.partial => (tr('جزئي'), StatusColors.expiring),
      InvoiceStatus.unpaid => (tr('غير مدفوعة'), StatusColors.expired),
      InvoiceStatus.voided => (tr('ملغاة'), StatusColors.none),
    };
    return ListTile(
      onTap: () => context.push(InvoiceScreen(invoiceId: inv.id)),
      leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.12), child: Icon(Icons.receipt_long, color: color, size: 20)),
      title: Text(showMember ? (m?.name ?? inv.customerName ?? tr('زائر')) : inv.items.map((i) => i.description).join('، '),
          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text('${inv.number} • ${dayKey(inv.date)}${inv.installments.isNotEmpty ? ' • ${tr('مقسطة')}' : ''}'),
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(fmtMoney(inv.voided ? inv.subtotal : inv.total), style: TextStyle(fontWeight: FontWeight.w800, decoration: inv.voided ? TextDecoration.lineThrough : null)),
        const SizedBox(height: 2),
        Pill(st == InvoiceStatus.partial ? '${tr('باقي')} ${fmtMoney(inv.balance)}' : label, color),
      ]),
    );
  }
}

enum _InvFilter { all, open, today, month }

class _InvoicesList extends StatefulWidget {
  const _InvoicesList();
  @override
  State<_InvoicesList> createState() => _InvoicesListState();
}

class _InvoicesListState extends State<_InvoicesList> {
  _InvFilter _f = _InvFilter.all;
  final _q = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    final now = g.now();
    final q = _q.text.trim().toLowerCase();
    var list = g.invoices.all.where((i) {
      switch (_f) {
        case _InvFilter.open:
          if (i.balance <= 0.001) return false;
        case _InvFilter.today:
          if (!Range.today(now).has(i.date)) return false;
        case _InvFilter.month:
          if (!Range.thisMonth(now).has(i.date)) return false;
        case _InvFilter.all:
          break;
      }
      if (q.isEmpty) return true;
      final m = g.members[i.memberId];
      return i.number.toLowerCase().contains(q) || (m?.name.toLowerCase().contains(q) ?? false) || (i.customerName?.contains(q) ?? false);
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final total = list.fold(0.0, (s, i) => s + i.total);
    final open = list.fold(0.0, (s, i) => s + i.balance);
    final count = list.length;
    if (list.length > 300) list = list.take(300).toList();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: SearchField(controller: _q, hint: tr('رقم الفاتورة أو اسم العضو'), onChanged: (_) => setState(() {})),
      ),
      SizedBox(
        height: 44,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), children: [
          for (final f in _InvFilter.values)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(switch (f) {
                  _InvFilter.all => tr('الكل'),
                  _InvFilter.open => tr('غير مسددة'),
                  _InvFilter.today => tr('اليوم'),
                  _InvFilter.month => tr('هذا الشهر'),
                }),
                selected: _f == f,
                onSelected: (_) => setState(() => _f = f),
              ),
            ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Wrap(spacing: 12, runSpacing: 2, alignment: WrapAlignment.spaceBetween, children: [
          Text(tr('{n} فاتورة', {'n': count}), style: TextStyle(color: context.colors.onSurfaceVariant)),
          Text('${tr('الإجمالي')} ${fmtMoney(total)}', style: const TextStyle(fontWeight: FontWeight.w700)),
          if (open > 0) Text('${tr('غير مسدد')} ${fmtMoney(open)}', style: const TextStyle(color: StatusColors.expired, fontWeight: FontWeight.w700)),
        ]),
      ),
      Expanded(
        child: list.isEmpty
            ? EmptyState(icon: Icons.receipt_long, title: tr('لا توجد فواتير'))
            : ListView.separated(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(indent: 72),
                itemBuilder: (_, i) => InvoiceTile(inv: list[i]),
              ),
      ),
    ]);
  }
}

class _InstallmentsList extends StatelessWidget {
  const _InstallmentsList();
  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    final list = context.services.billing.dueInstallments();
    if (list.isEmpty) return EmptyState(icon: Icons.event_available, title: tr('لا توجد أقساط مستحقة'));
    final today = g.today;
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24, top: 8),
      itemCount: list.length,
      separatorBuilder: (_, _) => const Divider(indent: 72),
      itemBuilder: (c, i) {
        final x = list[i];
        final m = g.members[x.invoice.memberId];
        final days = daysBetween(today, x.inst.due);
        final color = days < 0 ? StatusColors.expired : (days <= 3 ? StatusColors.expiring : StatusColors.none);
        return ListTile(
          leading: m == null ? const Icon(Icons.person) : MemberAvatar(m),
          title: Text(m?.name ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('${dayKey(x.inst.due)} • ${relativeDays(days)} • ${x.invoice.number}'),
          trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(fmtMoney(x.left), style: const TextStyle(fontWeight: FontWeight.w800)),
            Pill(days < 0 ? tr('متأخر') : tr('قادم'), color),
          ]),
          onTap: () => context.push(InvoiceScreen(invoiceId: x.invoice.id)),
        );
      },
    );
  }
}

class _DebtorsList extends StatelessWidget {
  const _DebtorsList();
  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    final list = context.services.billing.debtors();
    if (list.isEmpty) return EmptyState(icon: Icons.verified_outlined, title: tr('لا توجد ديون 👏'));
    final total = list.fold(0.0, (s, x) => s + x.balance);
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Text(tr('إجمالي الديون {a} على {n} عضو', {'a': fmtMoney(total), 'n': list.length}), style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      for (final x in list)
        if (g.members[x.memberId] case final m?)
          ListTile(
            leading: MemberAvatar(m),
            title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(x.overdue > 0 ? tr('متأخر {a}', {'a': fmtMoney(x.overdue)}) : tr('أقساط قادمة')),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(fmtMoney(x.balance), style: const TextStyle(fontWeight: FontWeight.w800, color: StatusColors.expired)),
              IconButton(
                tooltip: tr('تذكير'),
                icon: const Icon(Icons.chat_outlined),
                onPressed: () => showComposeDialog(context, m,
                    initial: tr('مرحباً {n}، نذكّرك بمبلغ {a} مستحق لدى {g}. شكراً لك 🙏', {'n': m.firstName, 'a': fmtMoney(x.balance), 'g': g.settings.gymName})),
              ),
            ]),
            onTap: () => context.push(MemberDetailScreen(memberId: m.id)),
          ),
    ]);
  }
}

/// مطابقة المحافظ والحسابات البنكية: تأكيد وصول التحويلات ومجاميع كل حساب
class _Reconciliation extends StatefulWidget {
  const _Reconciliation();
  @override
  State<_Reconciliation> createState() => _ReconciliationState();
}

class _ReconciliationState extends State<_Reconciliation> {
  bool _month = false;

  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    final sv = context.services;
    final list = sv.billing.unverified();
    final r = _month ? Range.thisMonth(g.now()) : Range.today(g.now());
    final byAcc = sv.reports.collectedByAccount(r);
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(tr('قارن هذه المجاميع مع كشف كل محفظة أو حساب بنكي'), style: TextStyle(color: context.colors.onSurfaceVariant)),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SegmentedButton<bool>(
          segments: [ButtonSegment(value: false, label: Text(tr('اليوم'))), ButtonSegment(value: true, label: Text(tr('هذا الشهر')))],
          selected: {_month},
          onSelectionChanged: (v) => setState(() => _month = v.first),
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(16),
        child: Card(
          child: Column(children: [
            if (byAcc.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(tr('لا دفعات في هذه الفترة'))),
            for (final e in byAcc.entries.toList()..sort((a, b) => b.value.total.compareTo(a.value.total)))
              ListTile(
                title: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(tr('{n} عملية', {'n': e.value.count}) + (e.value.unverified > 0 ? ' • ${tr('{n} بانتظار التأكد', {'n': e.value.unverified})}' : '')),
                trailing: Text(fmtMoney(e.value.total), style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(tr('بانتظار التأكد من الوصول ({n})', {'n': list.length}), style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
      ),
      if (list.isEmpty)
        Padding(padding: const EdgeInsets.all(16), child: Text(tr('كل التحويلات مؤكدة ✓'), style: const TextStyle(color: StatusColors.active))),
      for (final p in list)
        Card(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: ListTile(
            title: Text('${fmtMoney(p.amount)} — ${p.account ?? payMethodName(p.method)}', style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text([
              g.members[p.memberId]?.name ?? '',
              if (p.reference != null) '${tr('رقم العملية')}: ${p.reference}',
              '${dayKey(p.date)} ${hhmm(minutesOfDay(p.date))}',
            ].where((x) => x.isNotEmpty).join('\n')),
            isThreeLine: true,
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: tr('لم يصل'),
                icon: const Icon(Icons.close, color: StatusColors.expired),
                onPressed: () async {
                  final reason = await askText(context, tr('المبلغ لم يصل؟ سيعود ديناً على العضو'), hint: tr('السبب'), ok: tr('تأكيد'));
                  if (reason == null || !context.mounted) return;
                  await runAction(context, () => sv.billing.rejectPayment(p, reason), success: tr('عُكست الدفعة'));
                },
              ),
              IconButton.filledTonal(
                tooltip: tr('وصل'),
                icon: const Icon(Icons.check, color: StatusColors.active),
                onPressed: () => runAction(context, () => sv.billing.verifyPayment(p), success: tr('تم التأكيد ✓')),
              ),
            ]),
          ),
        ),
    ]);
  }
}

class _ExpensesList extends StatelessWidget {
  const _ExpensesList();
  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    final list = g.expenses.all.toList()..sort((a, b) => b.date.compareTo(a.date));
    final month = Range.thisMonth(g.now());
    final monthTotal = list.where((e) => month.has(e.date)).fold(0.0, (s, e) => s + e.amount);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'expense',
        onPressed: () => showExpenseDialog(context),
        icon: const Icon(Icons.add),
        label: Text(tr('مصروف')),
      ),
      body: list.isEmpty
          ? EmptyState(icon: Icons.money_off, title: tr('لا توجد مصروفات'), message: tr('سجّل الإيجار والرواتب والفواتير لتعرف ربحك الحقيقي'))
          : ListView(padding: const EdgeInsets.only(bottom: 88), children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(tr('مصروفات هذا الشهر: {a}', {'a': fmtMoney(monthTotal)}), style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              for (final e in list.take(300))
                ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.south_west, size: 18)),
                  title: Text(tr(e.category), style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text([dayKey(e.date), if (e.note != null) e.note!, if (e.by != null) e.by!].join(' • ')),
                  trailing: Text(fmtMoney(e.amount), style: const TextStyle(fontWeight: FontWeight.w800)),
                  onLongPress: () async {
                    if (await confirm(context, tr('حذف المصروف؟'), danger: true, ok: tr('حذف'))) {
                      await g.remove(e);
                      await g.log('expense_delete', '${e.category} ${fmtMoney(e.amount)}');
                    }
                  },
                ),
            ]),
    );
  }
}

Future<void> showExpenseDialog(BuildContext context) async {
  final g = context.gym;
  var cat = expenseCategories.first;
  var date = g.today;
  final amount = TextEditingController();
  final note = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: Text(tr('مصروف جديد')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            initialValue: cat,
            decoration: InputDecoration(labelText: tr('البند')),
            items: [for (final x in expenseCategories) DropdownMenuItem(value: x, child: Text(tr(x)))],
            onChanged: (v) => set(() => cat = v!),
          ),
          const SizedBox(height: 12),
          TextField(controller: amount, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: tr('المبلغ'))),
          const SizedBox(height: 12),
          TextField(controller: note, decoration: InputDecoration(labelText: tr('ملاحظة'))),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('التاريخ')),
            trailing: Text(dayKey(date)),
            onTap: () async {
              final d = await pickDay(c, date);
              if (d != null) set(() => date = d);
            },
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('إلغاء'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('حفظ'))),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  await runAction(
      context,
      () => context.services.billing
          .addExpense(date: date, category: cat, amount: parseAmount(amount.text) ?? 0, note: note.text.trim().isEmpty ? null : note.text.trim()),
      success: tr('تم الحفظ'));
}
