import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/money.dart';
import '../../services/accounting.dart';
import '../../services/data_tools.dart';
import '../../services/license.dart';
import '../../services/reports.dart';
import '../widgets/common.dart';
import '../widgets/upgrade.dart';

/// المحاسبة والتدقيق: البرنامج هو المحاسب — قيود آلية، قوائم مالية، تدقيق يومي، وإغلاق الصندوق
class AccountingScreen extends StatelessWidget {
  const AccountingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    if (!g.has(Feature.accounting)) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('المحاسبة والتدقيق'))),
        body: EmptyState(
          icon: Icons.account_balance_outlined,
          title: featureName(Feature.accounting),
          message: tr('قيود يومية آلية، قائمة الدخل، أرصدة الحسابات، أعمار الديون، تدقيق مالي يومي، وإغلاق الصندوق.'),
          action: FilledButton(onPressed: () => showUpgradeDialog(context, feature: Feature.accounting), child: Text(tr('ترقية'))),
        ),
      );
    }
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr('المحاسبة والتدقيق')),
          bottom: TabBar(isScrollable: true, tabs: [
            Tab(text: tr('التدقيق')),
            Tab(text: tr('قائمة الدخل')),
            Tab(text: tr('الأرصدة')),
            Tab(text: tr('دفتر اليومية')),
          ]),
        ),
        body: const TabBarView(children: [_AuditTab(), _IncomeTab(), _BalancesTab(), _JournalTab()]),
      ),
    );
  }
}

Color _sevColor(BuildContext c, Severity s) => switch (s) {
      Severity.critical => c.colors.error,
      Severity.warning => const Color(0xFFD97706),
      Severity.info => c.colors.primary,
    };

IconData _sevIcon(Severity s) => switch (s) {
      Severity.critical => Icons.error_outline,
      Severity.warning => Icons.warning_amber_rounded,
      Severity.info => Icons.info_outline,
    };

// -----------------------------------------------------------------------------
// التدقيق وإغلاق الصندوق
// -----------------------------------------------------------------------------
class _AuditTab extends StatelessWidget {
  const _AuditTab();

  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    final sv = context.services;
    final findings = sv.auditFindings();
    final crit = findings.where((f) => f.severity == Severity.critical).length;
    final warn = findings.where((f) => f.severity == Severity.warning).length;
    final ok = crit == 0 && warn == 0;
    final a = sv.accounting;
    final today = a.cashDay(g.today);
    final closed = a.closeOf(g.today);
    final closes = g.closes.all.toList()..sort((x, y) => y.time.compareTo(x.time));
    return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
      Card(
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        color: (ok ? const Color(0xFF16A34A) : (crit > 0 ? context.colors.error : const Color(0xFFD97706))).withValues(alpha: 0.10),
        child: ListTile(
          leading: Icon(ok ? Icons.verified_outlined : _sevIcon(crit > 0 ? Severity.critical : Severity.warning),
              size: 36, color: ok ? const Color(0xFF16A34A) : _sevColor(context, crit > 0 ? Severity.critical : Severity.warning)),
          title: Text(ok ? tr('الحسابات سليمة') : tr('{c} مشكلة حرجة، {w} تنبيه', {'c': crit, 'w': warn}),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          subtitle: Text(tr('يفحص البرنامج كل فاتورة ودفعة ومصروف تلقائياً: التطابق، التسلسل، التوازن، الصندوق، والعمليات الحساسة.')),
        ),
      ),
      for (final f in findings) _FindingTile(f),
      Section(
        title: tr('إغلاق الصندوق اليوم'),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              InfoRow(tr('نقد مقبوض'), fmtMoney(today.cashIn)),
              if (today.cashRefunds > 0) InfoRow(tr('نقد مردود للأعضاء'), '- ${fmtMoney(today.cashRefunds)}'),
              if (today.cashExpenses > 0) InfoRow(tr('مصروفات من الصندوق'), '- ${fmtMoney(today.cashExpenses)}'),
              const Divider(),
              InfoRow(tr('المفروض أن يكون في الصندوق'), fmtMoney(today.expected), bold: true),
              if (today.otherAccounts.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(tr('حركة الحسابات الأخرى اليوم (قارنها بكشف كل حساب):'), style: context.text.bodySmall),
                for (final e in today.otherAccounts.entries) InfoRow(Accounts.label(e.key), fmtMoney(e.value)),
              ],
              const SizedBox(height: 10),
              if (closed != null)
                Text(
                  tr('أُغلق {t} بواسطة {b}: المعدود {c}، الفرق {v}', {
                    't': hhmm(closed.time.hour * 60 + closed.time.minute),
                    'b': closed.by ?? tr('المالك'),
                    'c': fmtMoney(closed.counted),
                    'v': fmtMoney(closed.variance),
                  }),
                  style: TextStyle(fontWeight: FontWeight.w700, color: closed.variance.abs() < 0.5 ? const Color(0xFF16A34A) : context.colors.error),
                ),
              const SizedBox(height: 8),
              FilledButton.icon(
                icon: const Icon(Icons.point_of_sale),
                label: Text(closed == null ? tr('إغلاق الصندوق') : tr('إعادة العدّ')),
                onPressed: () => _close(context, today.expected),
              ),
            ]),
          ),
        ),
      ),
      if (closes.isNotEmpty)
        Section(
          title: tr('سجل إغلاق الصندوق'),
          child: Card(
            child: Column(children: [
              for (final c in closes.take(14))
                ListTile(
                  dense: true,
                  leading: Icon(c.variance.abs() < 0.5 ? Icons.check_circle_outline : Icons.error_outline,
                      color: c.variance.abs() < 0.5 ? const Color(0xFF16A34A) : context.colors.error),
                  title: Text('${dayKey(c.day)} — ${c.by ?? tr('المالك')}'),
                  subtitle: Text(tr('المتوقع {e} • المعدود {c}', {'e': fmtMoney(c.expected), 'c': fmtMoney(c.counted)})),
                  trailing: Text(c.variance == 0 ? '✓' : '${c.variance > 0 ? '+' : ''}${fmtMoney(c.variance)}',
                      style: TextStyle(fontWeight: FontWeight.w800, color: c.variance.abs() < 0.5 ? null : context.colors.error)),
                ),
            ]),
          ),
        ),
    ]);
  }

  Future<void> _close(BuildContext context, double expected) async {
    final counted = TextEditingController();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('إغلاق الصندوق')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr('عُدّ النقد الموجود من حركة اليوم (بدون الفكّة الثابتة) واكتب المبلغ. يُسجَّل الفرق في التدقيق ولا يمكن تعديله.')),
            const SizedBox(height: 12),
            TextField(controller: counted, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: tr('المبلغ المعدود'))),
            const SizedBox(height: 10),
            TextField(controller: note, decoration: InputDecoration(labelText: tr('ملاحظة (اختياري)'))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('إلغاء'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('حفظ'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final v = parseAmount(counted.text);
    if (v == null) {
      context.toast(tr('اكتب المبلغ المعدود'), error: true);
      return;
    }
    final g = context.gym;
    final res = await runAction(context, () => context.services.accounting.closeCash(g.today, v, note: note.text.trim().isEmpty ? null : note.text.trim()));
    if (res != null && context.mounted) {
      context.toast(res.variance.abs() < 0.5
          ? tr('الصندوق مطابق ✓')
          : tr('يوجد فرق {v} — سُجّل في التدقيق', {'v': '${res.variance > 0 ? '+' : ''}${fmtMoney(res.variance)}'}),
          error: res.variance.abs() >= 0.5);
    }
  }
}

class _FindingTile extends StatelessWidget {
  final Finding f;
  const _FindingTile(this.f);

  @override
  Widget build(BuildContext context) {
    final col = _sevColor(context, f.severity);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: ExpansionTile(
        leading: Icon(_sevIcon(f.severity), color: col),
        title: Text(f.title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(tr('{n} عنصر', {'n': f.count})),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(f.advice, style: TextStyle(color: context.colors.onSurfaceVariant)),
          const SizedBox(height: 8),
          for (final i in f.items.take(30)) Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text('• $i')),
          if (f.count > 30) Text(tr('و{n} غيرها', {'n': f.count - 30})),
          if (f.fix != null) ...[
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.build_outlined),
              label: Text(f.fixLabel ?? tr('إصلاح')),
              onPressed: () => runAction(context, f.fix!, success: tr('تم الإصلاح ✓')),
            ),
          ],
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// الفترات
// -----------------------------------------------------------------------------
enum _P { month, lastMonth, year, all }

Range _range(_P p, DateTime today) => switch (p) {
      _P.month => Range.thisMonth(today),
      _P.lastMonth => Range(DateTime(today.year, today.month - 1, 1), DateTime(today.year, today.month, 0)),
      _P.year => Range.thisYear(today),
      _P.all => Range(DateTime(2000), today),
    };

String _pName(_P p) => switch (p) {
      _P.month => tr('هذا الشهر'),
      _P.lastMonth => tr('الشهر الماضي'),
      _P.year => tr('هذه السنة'),
      _P.all => tr('منذ البداية'),
    };

class _PeriodBar extends StatelessWidget {
  final _P value;
  final ValueChanged<_P> onChanged;
  const _PeriodBar(this.value, this.onChanged);

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 52,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(12, 8, 12, 4), children: [
          for (final p in _P.values)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(label: Text(_pName(p)), selected: p == value, onSelected: (_) => onChanged(p)),
            ),
        ]),
      );
}

// -----------------------------------------------------------------------------
// قائمة الدخل
// -----------------------------------------------------------------------------
class _IncomeTab extends StatefulWidget {
  const _IncomeTab();
  @override
  State<_IncomeTab> createState() => _IncomeTabState();
}

class _IncomeTabState extends State<_IncomeTab> {
  _P _p = _P.month;

  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    final a = context.services.accounting;
    final r = _range(_p, g.today);
    final s = a.incomeStatement(r);
    final staff = a.staffReport(r);
    final profitColor = s.netProfit >= 0 ? const Color(0xFF16A34A) : context.colors.error;
    return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
      _PeriodBar(_p, (v) => setState(() => _p = v)),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: Text('${dayKey(r.from)} – ${dayKey(r.to)}', style: context.text.bodySmall),
      ),
      Card(
        margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr('صافي الربح'), style: context.text.titleSmall),
            Text(fmtMoney(s.netProfit), style: context.text.headlineMedium?.copyWith(fontWeight: FontWeight.w900, color: profitColor)),
            if (s.netRevenue > 0) Text(tr('هامش الربح {p}%', {'p': fmtNum(s.margin)}), style: TextStyle(color: profitColor, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
      Section(
        title: tr('الإيرادات (حسب الفواتير، بدون الضريبة)'),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              for (final e in s.revenue.entries) InfoRow(Accounts.label(e.key), fmtMoney(e.value)),
              if (s.discounts > 0) InfoRow(tr('خصومات ممنوحة'), '- ${fmtMoney(s.discounts)}', color: const Color(0xFFD97706)),
              const Divider(),
              InfoRow(tr('صافي الإيرادات'), fmtMoney(s.netRevenue), bold: true),
            ]),
          ),
        ),
      ),
      Section(
        title: tr('المصروفات'),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              if (s.expenses.isEmpty) Text(tr('لا مصروفات في هذه الفترة')),
              for (final e in s.expenses.entries) InfoRow(tr(e.key), fmtMoney(e.value)),
              const Divider(),
              InfoRow(tr('مجموع المصروفات'), fmtMoney(s.totalExpenses), bold: true),
            ]),
          ),
        ),
      ),
      Section(
        title: tr('النقد الفعلي'),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              InfoRow(tr('المقبوض من الأعضاء والزبائن'), fmtMoney(s.collected)),
              if (s.refunds > 0) InfoRow(tr('المردود للأعضاء'), '- ${fmtMoney(s.refunds)}'),
              InfoRow(tr('المصروفات المدفوعة'), '- ${fmtMoney(roundMoney(s.paidOut - s.refunds))}'),
              const Divider(),
              InfoRow(tr('صافي النقد الداخل'), fmtMoney(s.netCash), bold: true),
              const SizedBox(height: 6),
              Text(tr('الربح يُحسب من الفواتير (ما استحقه النادي)، والنقد من المقبوض فعلاً. الفرق بينهما ديون لم تُحصَّل أو مقبوض عن فترات سابقة.'),
                  style: context.text.bodySmall),
            ]),
          ),
        ),
      ),
      if (s.vat.abs() > 0.001)
        Section(
          title: tr('الضريبة'),
          child: Card(
            child: ListTile(
              leading: const Icon(Icons.account_balance_outlined),
              title: Text(tr('ضريبة القيمة المضافة المستحقة للحكومة')),
              subtitle: Text(tr('ليست ربحاً: تُورَّد لدائرة الضريبة')),
              trailing: Text(fmtMoney(s.vat), style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ),
      if (staff.isNotEmpty)
        Section(
          title: tr('الموظفون'),
          child: Card(
            child: Column(children: [
              for (final x in staff)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.badge_outlined),
                  title: Text(x.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(tr('{n} إيصال • خصومات {d} • مردود {r}', {'n': x.receipts, 'd': fmtMoney(x.discounts), 'r': fmtMoney(x.refunds)})),
                  trailing: Text(fmtMoney(x.collected), style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
            ]),
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: OutlinedButton.icon(
          icon: const Icon(Icons.ios_share),
          label: Text(tr('تصدير قائمة الدخل (Excel)')),
          onPressed: () => _export(context, 'income-${dayKey(r.from)}_${dayKey(r.to)}.csv', [
            [tr('البند'), tr('المبلغ')],
            for (final e in s.revenue.entries) [Accounts.label(e.key), e.value],
            [tr('خصومات ممنوحة'), -s.discounts],
            [tr('صافي الإيرادات'), s.netRevenue],
            for (final e in s.expenses.entries) [tr('مصروف: {c}', {'c': tr(e.key)}), -e.value],
            [tr('صافي الربح'), s.netProfit],
            [tr('ضريبة مستحقة'), s.vat],
            [tr('المقبوض'), s.collected],
            [tr('صافي النقد الداخل'), s.netCash],
          ]),
        ),
      ),
    ]);
  }
}

Future<void> _export(BuildContext context, String name, List<List<Object?>> rows) => runAction(
    context, () => context.services.shareFile(Uint8List.fromList(utf8.encode('﻿${toCsv(rows)}')), name, 'text/csv'));

// -----------------------------------------------------------------------------
// الأرصدة: الحسابات، أعمار الديون، ميزان المراجعة
// -----------------------------------------------------------------------------
class _BalancesTab extends StatelessWidget {
  const _BalancesTab();

  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    final a = context.services.accounting;
    final money = a.moneyBalances(g.today);
    final aging = a.aging(g.today);
    final deferred = a.deferredRevenue(g.today);
    final tb = a.trialBalance();
    final dr = roundMoney(tb.fold(0.0, (s, t) => s + t.debit));
    final cr = roundMoney(tb.fold(0.0, (s, t) => s + t.credit));
    final balanced = (dr - cr).abs() < 0.01;
    return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
      Section(
        title: tr('أين المال الآن'),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              for (final e in money.entries) InfoRow(Accounts.label(e.key), fmtMoney(e.value), color: e.value < 0 ? context.colors.error : null),
              const Divider(),
              InfoRow(tr('المجموع'), fmtMoney(money.values.fold(0.0, (s, v) => s + v)), bold: true),
              const SizedBox(height: 6),
              Text(tr('قارن كل رصيد بكشف المحفظة أو البنك. الرصيد السالب يعني مصروفات سُجّلت على حساب أكثر مما دخله.'), style: context.text.bodySmall),
            ]),
          ),
        ),
      ),
      Section(
        title: tr('ديون الأعضاء حسب عمرها'),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              InfoRow(tr('حتى 30 يوماً'), fmtMoney(aging.d30)),
              InfoRow(tr('31 – 60 يوماً'), fmtMoney(aging.d60)),
              InfoRow(tr('61 – 90 يوماً'), fmtMoney(aging.d90), color: aging.d90 > 0 ? const Color(0xFFD97706) : null),
              InfoRow(tr('أكثر من 90 يوماً'), fmtMoney(aging.older), color: aging.older > 0 ? context.colors.error : null),
              const Divider(),
              InfoRow(tr('المجموع'), fmtMoney(aging.total), bold: true),
              if (aging.top.isNotEmpty) ...[
                const SizedBox(height: 10),
                Align(alignment: AlignmentDirectional.centerStart, child: Text(tr('أكبر المدينين'), style: const TextStyle(fontWeight: FontWeight.w700))),
                for (final t in aging.top.take(5))
                  InfoRow('${g.members[t.memberId]?.name ?? t.memberId} (${tr('{n} يوم', {'n': t.days})})', fmtMoney(t.amount)),
              ],
            ]),
          ),
        ),
      ),
      Section(
        title: tr('اشتراكات مدفوعة لم تُستهلك بعد'),
        child: Card(
          child: ListTile(
            leading: const Icon(Icons.hourglass_bottom),
            title: Text(fmtMoney(deferred), style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(tr('قيمة الأيام المتبقية في اشتراكات الأعضاء: خدمة ما زال النادي مديناً بها. لا تصرفها كلها كربح.')),
          ),
        ),
      ),
      Section(
        title: tr('ميزان المراجعة'),
        trailing: Text(balanced ? tr('متوازن ✓') : tr('غير متوازن'),
            style: TextStyle(fontWeight: FontWeight.w800, color: balanced ? const Color(0xFF16A34A) : context.colors.error)),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(children: [
              Row(children: [
                Expanded(flex: 3, child: Text(tr('الحساب'), style: const TextStyle(fontWeight: FontWeight.w800))),
                Expanded(flex: 2, child: Text(tr('مدين'), textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w800))),
                Expanded(flex: 2, child: Text(tr('دائن'), textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w800))),
              ]),
              const Divider(),
              for (final t in tb)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Expanded(flex: 3, child: Text(Accounts.label(t.account), style: const TextStyle(fontSize: 13))),
                    Expanded(flex: 2, child: Text(t.balance > 0 ? fmtNum(t.balance) : '', textAlign: TextAlign.end, style: const TextStyle(fontSize: 13))),
                    Expanded(flex: 2, child: Text(t.balance < 0 ? fmtNum(-t.balance) : '', textAlign: TextAlign.end, style: const TextStyle(fontSize: 13))),
                  ]),
                ),
              const Divider(),
              Row(children: [
                Expanded(flex: 3, child: Text(tr('المجموع'), style: const TextStyle(fontWeight: FontWeight.w800))),
                Expanded(flex: 2, child: Text(fmtNum(_side(tb, true)), textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w800))),
                Expanded(flex: 2, child: Text(fmtNum(_side(tb, false)), textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w800))),
              ]),
            ]),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: OutlinedButton.icon(
          icon: const Icon(Icons.ios_share),
          label: Text(tr('تصدير ميزان المراجعة (Excel)')),
          onPressed: () => _export(context, 'trial-balance-${dayKey(g.today)}.csv', a.trialRows(Range(DateTime(2000), g.today))),
        ),
      ),
    ]);
  }

  /// مجموع الأرصدة المدينة أو الدائنة
  static double _side(List<TrialRow> tb, bool debit) =>
      roundMoney(tb.fold(0.0, (s, t) => s + (debit ? (t.balance > 0 ? t.balance : 0) : (t.balance < 0 ? -t.balance : 0))));
}

// -----------------------------------------------------------------------------
// دفتر اليومية
// -----------------------------------------------------------------------------
class _JournalTab extends StatefulWidget {
  const _JournalTab();
  @override
  State<_JournalTab> createState() => _JournalTabState();
}

class _JournalTabState extends State<_JournalTab> {
  _P _p = _P.month;

  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    final a = context.services.accounting;
    final r = _range(_p, g.today);
    final j = a.journal(r).reversed.toList();
    return Column(children: [
      _PeriodBar(_p, (v) => setState(() => _p = v)),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Row(children: [
          Expanded(child: Text(tr('{n} قيد — كل قيد يُنشأ تلقائياً من الفواتير والدفعات والمصروفات', {'n': j.length}), style: context.text.bodySmall)),
          TextButton.icon(
            icon: const Icon(Icons.ios_share, size: 18),
            label: Text(tr('Excel')),
            onPressed: () => _export(context, 'journal-${dayKey(r.from)}_${dayKey(r.to)}.csv', a.journalRows(r)),
          ),
        ]),
      ),
      Expanded(
        child: j.isEmpty
            ? EmptyState(icon: Icons.menu_book_outlined, title: tr('لا قيود في هذه الفترة'))
            : ListView.builder(
                itemCount: j.length,
                itemBuilder: (c, i) {
                  final e = j[i];
                  return Card(
                    margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Row(children: [
                          Expanded(child: Text(e.text, style: const TextStyle(fontWeight: FontWeight.w700))),
                          Text(dayKey(e.date), style: context.text.bodySmall),
                        ]),
                        const SizedBox(height: 6),
                        for (final l in e.lines)
                          Row(children: [
                            Expanded(child: Text(l.debit > 0 ? Accounts.label(l.account) : '    ${Accounts.label(l.account)}', style: const TextStyle(fontSize: 13))),
                            SizedBox(width: 90, child: Text(l.debit > 0 ? fmtNum(l.debit) : '', textAlign: TextAlign.end, style: const TextStyle(fontSize: 13))),
                            SizedBox(width: 90, child: Text(l.credit > 0 ? fmtNum(l.credit) : '', textAlign: TextAlign.end, style: const TextStyle(fontSize: 13))),
                          ]),
                      ]),
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}
