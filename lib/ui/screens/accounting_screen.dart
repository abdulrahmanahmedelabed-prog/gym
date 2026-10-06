import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/money.dart';
import '../../models/business.dart';
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
    final score = Accounting.healthScore(findings);
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
          trailing: Text.rich(TextSpan(children: [
            TextSpan(
                text: '$score',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: score >= 90 ? const Color(0xFF16A34A) : (score >= 70 ? const Color(0xFFD97706) : context.colors.error))),
            TextSpan(text: '/100', style: context.text.bodySmall),
          ])),
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
              if (today.movesIn > 0) InfoRow(tr('إيداع من المالك'), '+ ${fmtMoney(today.movesIn)}'),
              if (today.movesOut > 0) InfoRow(tr('خرج من الصندوق (إيداع بنكي أو سحب)'), '- ${fmtMoney(today.movesOut)}'),
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
                onPressed: () => showCashCloseDialog(context),
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

}

/// إغلاق الصندوق. للموظف بدون صلاحية التقارير يكون «أعمى»: يعدّ دون أن يرى المبلغ المتوقع، فلا يُعدَّل العدّ ليطابق.
Future<void> showCashCloseDialog(BuildContext context) async {
  final g = context.gym;
  final a = context.services.accounting;
  final blind = !g.can(Perm.reports);
  final expected = a.cashDay(g.today).expected;
  final counted = TextEditingController();
  final note = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(tr('إغلاق الصندوق')),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr('عُدّ النقد الموجود من حركة اليوم (بدون الفكّة الثابتة) واكتب المبلغ. يُسجَّل الفرق في التدقيق ولا يمكن تعديله.')),
          if (!blind) ...[
            const SizedBox(height: 8),
            InfoRow(tr('المفروض أن يكون في الصندوق'), fmtMoney(expected), bold: true),
          ],
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
  final text = counted.text, n = note.text.trim();
  if (ok != true || !context.mounted) return;
  final v = parseAmount(text);
  if (v == null) {
    context.toast(tr('اكتب المبلغ المعدود'), error: true);
    return;
  }
  final res = await runAction(context, () => a.closeCash(g.today, v, note: n.isEmpty ? null : n));
  if (res != null && context.mounted) {
    context.toast(res.variance.abs() < 0.5
        ? tr('الصندوق مطابق ✓')
        : tr('يوجد فرق {v} — سُجّل في التدقيق', {'v': '${res.variance > 0 ? '+' : ''}${fmtMoney(res.variance)}'}),
        error: res.variance.abs() >= 0.5);
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

/// الفترة السابقة المماثلة للمقارنة
Range? _prev(_P p, DateTime today) => switch (p) {
      _P.month => Range(DateTime(today.year, today.month - 1, 1), DateTime(today.year, today.month, 0)),
      _P.lastMonth => Range(DateTime(today.year, today.month - 2, 1), DateTime(today.year, today.month - 1, 0)),
      _P.year => Range(DateTime(today.year - 1, 1, 1), DateTime(today.year - 1, 12, 31)),
      _P.all => null,
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
    final prevR = _prev(_p, g.today);
    final prev = prevR == null ? null : a.incomeStatement(prevR);
    final trend = a.trend(6);
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
            if (prev != null) ...[
              const SizedBox(height: 6),
              Text(
                tr('{p}: {v} (الفرق {d})', {
                  'p': switch (_p) { _P.month => tr('الشهر الماضي'), _P.lastMonth => tr('الشهر الذي قبله'), _ => tr('السنة الماضية') },
                  'v': fmtMoney(prev.netProfit),
                  'd': '${s.netProfit >= prev.netProfit ? '+' : ''}${fmtMoney(roundMoney(s.netProfit - prev.netProfit))}',
                }),
                style: context.text.bodySmall,
              ),
            ],
          ]),
        ),
      ),
      Section(
        title: tr('آخر 6 أشهر'),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              Row(children: [
                Expanded(flex: 2, child: Text(tr('الشهر'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
                for (final h in [tr('الإيرادات'), tr('المصروفات'), tr('الربح')])
                  Expanded(flex: 3, child: Text(h, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
              ]),
              const Divider(),
              for (final m in trend)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Expanded(flex: 2, child: Text(dayKey(m.month).substring(0, 7), style: const TextStyle(fontSize: 13))),
                    Expanded(flex: 3, child: Text(fmtNum(m.revenue), textAlign: TextAlign.end, style: const TextStyle(fontSize: 13))),
                    Expanded(flex: 3, child: Text(fmtNum(m.expenses), textAlign: TextAlign.end, style: const TextStyle(fontSize: 13))),
                    Expanded(
                        flex: 3,
                        child: Text(fmtNum(m.profit),
                            textAlign: TextAlign.end,
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: m.profit >= 0 ? const Color(0xFF16A34A) : context.colors.error))),
                  ]),
                ),
            ]),
          ),
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
    final bs = a.balanceSheet(g.today);
    final tb = a.trialBalance();
    final dr = roundMoney(tb.fold(0.0, (s, t) => s + t.debit));
    final cr = roundMoney(tb.fold(0.0, (s, t) => s + t.credit));
    final balanced = (dr - cr).abs() < 0.01;
    final moves = g.moves.all.toList()..sort((x, y) => y.date.compareTo(x.date));
    final locked = g.lockedUntil;
    final lastMonthEnd = DateTime(g.today.year, g.today.month, 0);
    void ledger(String acc) => context.push(LedgerScreen(account: acc));
    Widget tapRow(String acc, double v, {Color? color}) => InkWell(
          onTap: () => ledger(acc),
          child: InfoRow(Accounts.label(acc), fmtMoney(v), color: color),
        );
    return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
      Section(
        title: tr('أين المال الآن'),
        trailing: g.can(Perm.expenses)
            ? TextButton.icon(icon: const Icon(Icons.swap_horiz, size: 18), label: Text(tr('حركة مال')), onPressed: () => showMoneyMoveDialog(context))
            : null,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              for (final e in money.entries) tapRow(e.key, e.value, color: e.value < 0 ? context.colors.error : null),
              const Divider(),
              InfoRow(tr('المجموع'), fmtMoney(money.values.fold(0.0, (s, v) => s + v)), bold: true),
              const SizedBox(height: 6),
              Text(tr('اضغط أي حساب لكشفه. قارن كل رصيد بكشف المحفظة أو البنك، وسجّل الإيداع في البنك وسحوباتك من «حركة مال».'), style: context.text.bodySmall),
            ]),
          ),
        ),
      ),
      Section(
        title: tr('الميزانية العمومية'),
        trailing: Text(bs.balanced ? tr('متوازنة ✓') : tr('غير متوازنة'),
            style: TextStyle(fontWeight: FontWeight.w800, color: bs.balanced ? const Color(0xFF16A34A) : context.colors.error)),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(tr('ما يملكه النادي'), style: const TextStyle(fontWeight: FontWeight.w800)),
              for (final e in bs.assets.entries) tapRow(e.key, e.value),
              InfoRow(tr('مجموع الأصول'), fmtMoney(bs.totalAssets), bold: true),
              const Divider(),
              Text(tr('ما على النادي'), style: const TextStyle(fontWeight: FontWeight.w800)),
              if (bs.liabilities.isEmpty) InfoRow(tr('لا التزامات'), fmtMoney(0)),
              for (final e in bs.liabilities.entries) tapRow(e.key, e.value),
              const Divider(),
              Text(tr('حق المالك'), style: const TextStyle(fontWeight: FontWeight.w800)),
              for (final e in bs.equity.entries) tapRow(e.key, e.value),
              InfoRow(tr('الأرباح المتراكمة'), fmtMoney(bs.retained), color: bs.retained < 0 ? context.colors.error : null),
              InfoRow(tr('الالتزامات + حق المالك'), fmtMoney(roundMoney(bs.totalLiabilities + bs.totalEquity)), bold: true),
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
        title: tr('إقفال الفترات'),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Icon(locked == null ? Icons.lock_open : Icons.lock_outline, color: locked == null ? null : const Color(0xFF16A34A)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(locked == null ? tr('لا توجد فترة مقفلة') : tr('مقفلة حتى {d}', {'d': dayKey(locked)}),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ]),
              const SizedBox(height: 6),
              Text(tr('بعد مراجعة الشهر أقفله: لا يُسجَّل بعدها مصروف أو حركة بتاريخ داخله، ويُحفظ ميزانه ليكشف التدقيق أي تغيير لاحق.'),
                  style: context.text.bodySmall),
              if (g.can(Perm.settings)) ...[
                const SizedBox(height: 10),
                if (locked == null || locked.isBefore(lastMonthEnd))
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.lock_outline),
                    label: Text(tr('إقفال حتى {d}', {'d': dayKey(lastMonthEnd)})),
                    onPressed: () async {
                      if (await confirm(context, tr('إقفال حتى {d}', {'d': dayKey(lastMonthEnd)}),
                              message: tr('تأكد أن مصروفات الشهر وحركاته مسجّلة كلها. يمكن فتح الإقفال لاحقاً ويُسجَّل ذلك في العمليات الحساسة.')) &&
                          context.mounted) {
                        await runAction(context, () => a.lockPeriod(lastMonthEnd), success: tr('تم الإقفال ✓'));
                      }
                    },
                  ),
                if (locked != null)
                  TextButton.icon(
                    icon: const Icon(Icons.lock_open),
                    label: Text(tr('فتح آخر إقفال')),
                    onPressed: () async {
                      if (await confirm(context, tr('فتح آخر إقفال'), danger: true) && context.mounted) {
                        await runAction(context, a.unlockLast);
                      }
                    },
                  ),
              ],
            ]),
          ),
        ),
      ),
      if (moves.isNotEmpty)
        Section(
          title: tr('حركات المال'),
          child: Card(
            child: Column(children: [
              for (final m in moves.take(15))
                ListTile(
                  dense: true,
                  leading: Icon(_moveIcon(m.kind)),
                  title: Text('${Accounting.moveKindName(m.kind)} — ${fmtMoney(m.amount)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text([
                    dayKey(m.date),
                    if (m.from != null) Accounts.label(m.from!),
                    if (m.from != null && m.to != null) '←',
                    if (m.to != null) Accounts.label(m.to!),
                    if (m.note != null) '• ${m.note}',
                  ].join(' ')),
                  trailing: g.can(Perm.expenses) && (locked == null || m.date.isAfter(locked))
                      ? IconButton(
                          tooltip: tr('حذف'),
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            if (await confirm(context, tr('حذف الحركة؟'), danger: true) && context.mounted) {
                              await runAction(context, () => a.deleteMove(m));
                            }
                          })
                      : null,
                ),
            ]),
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
                InkWell(
                  onTap: () => ledger(t.account),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(children: [
                      Expanded(flex: 3, child: Text(Accounts.label(t.account), style: const TextStyle(fontSize: 13))),
                      Expanded(flex: 2, child: Text(t.balance > 0 ? fmtNum(t.balance) : '', textAlign: TextAlign.end, style: const TextStyle(fontSize: 13))),
                      Expanded(flex: 2, child: Text(t.balance < 0 ? fmtNum(-t.balance) : '', textAlign: TextAlign.end, style: const TextStyle(fontSize: 13))),
                    ]),
                  ),
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
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: OutlinedButton.icon(
          icon: const Icon(Icons.ios_share),
          label: Text(tr('تصدير الميزانية العمومية (Excel)')),
          onPressed: () => _export(context, 'balance-sheet-${dayKey(g.today)}.csv', [
            [tr('البند'), tr('المبلغ')],
            for (final e in bs.assets.entries) [Accounts.label(e.key), e.value],
            [tr('مجموع الأصول'), bs.totalAssets],
            for (final e in bs.liabilities.entries) [Accounts.label(e.key), e.value],
            for (final e in bs.equity.entries) [Accounts.label(e.key), e.value],
            [tr('الأرباح المتراكمة'), bs.retained],
            [tr('الالتزامات + حق المالك'), roundMoney(bs.totalLiabilities + bs.totalEquity)],
          ]),
        ),
      ),
    ]);
  }

  /// مجموع الأرصدة المدينة أو الدائنة
  static double _side(List<TrialRow> tb, bool debit) =>
      roundMoney(tb.fold(0.0, (s, t) => s + (debit ? (t.balance > 0 ? t.balance : 0) : (t.balance < 0 ? -t.balance : 0))));
}

IconData _moveIcon(String k) => switch (k) {
      'transfer' => Icons.swap_horiz,
      'draw' => Icons.north_east,
      'capital' => Icons.south_west,
      'opening' => Icons.flag_outlined,
      _ => Icons.account_balance_outlined,
    };

/// حركة مال: إيداع النقد في البنك، سحب المالك، إيداع رأس مال، رصيد افتتاحي، توريد الضريبة
Future<void> showMoneyMoveDialog(BuildContext context) async {
  final g = context.gym;
  final a = context.services.accounting;
  final accounts = a.moneyAccounts();
  var kind = 'transfer';
  String? from = Accounts.cash;
  String? to = accounts.firstWhere((x) => x != Accounts.cash, orElse: () => '');
  if (to.isEmpty) to = null;
  var date = g.today;
  final amount = TextEditingController();
  final note = TextEditingController();
  String hint(String k) => switch (k) {
        'transfer' => tr('مثل إيداع نقد الصندوق في البنك، أو تحويل رصيد المحفظة للبنك.'),
        'draw' => tr('مال أخذه المالك لنفسه. ليس مصروفاً ولا يُنقص الربح.'),
        'capital' => tr('مال وضعه المالك في النادي من جيبه.'),
        'opening' => tr('رصيد الحساب يوم بدأت استخدام البرنامج.'),
        _ => tr('دفع الضريبة المستحقة لدائرة الضريبة.'),
      };
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, set) {
      final needFrom = kind == 'transfer' || kind == 'draw' || kind == 'vat';
      final needTo = kind == 'transfer' || kind == 'capital' || kind == 'opening';
      Widget pick(String label, String? v, ValueChanged<String?> on) => DropdownButtonFormField<String>(
            key: ValueKey('$label$kind'),
            initialValue: accounts.contains(v) ? v : null,
            isExpanded: true,
            decoration: InputDecoration(labelText: label),
            items: [for (final x in accounts) DropdownMenuItem(value: x, child: Text(Accounts.label(x), overflow: TextOverflow.ellipsis))],
            onChanged: on,
          );
      return AlertDialog(
        title: Text(tr('حركة مال')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final k in MoneyMove.kinds)
                ChoiceChip(label: Text(Accounting.moveKindName(k)), selected: kind == k, onSelected: (_) => set(() => kind = k)),
            ]),
            const SizedBox(height: 8),
            Text(hint(kind), style: Theme.of(c).textTheme.bodySmall),
            const SizedBox(height: 8),
            if (needFrom) pick(tr('من'), from, (v) => set(() => from = v)),
            if (needTo) pick(tr('إلى'), to, (v) => set(() => to = v)),
            const SizedBox(height: 8),
            TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: tr('المبلغ'))),
            const SizedBox(height: 8),
            TextField(controller: note, decoration: InputDecoration(labelText: tr('ملاحظة (اختياري)'))),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('التاريخ')),
              trailing: Text(dayKey(date)),
              onTap: () async {
                final d = await pickDay(c, date, last: g.today);
                if (d != null) set(() => date = d);
              },
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('إلغاء'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('حفظ'))),
        ],
      );
    }),
  );
  final v = parseAmount(amount.text), n = note.text.trim();
  if (ok != true || !context.mounted) return;
  if (v == null) {
    context.toast(tr('اكتب مبلغاً صحيحاً'), error: true);
    return;
  }
  await runAction(context, () => a.addMove(kind: kind, date: date, amount: v, from: from, to: to, note: n.isEmpty ? null : n), success: tr('تم الحفظ ✓'));
}

/// كشف حساب: كل حركة على الحساب والرصيد بعدها
class LedgerScreen extends StatelessWidget {
  final String account;
  const LedgerScreen({super.key, required this.account});

  @override
  Widget build(BuildContext context) {
    context.gymWatch;
    final a = context.services.accounting;
    final lines = a.ledger(account);
    final rows = lines.reversed.toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(Accounts.label(account)),
        actions: [
          IconButton(
            tooltip: tr('تصدير'),
            icon: const Icon(Icons.ios_share),
            onPressed: () => _export(context, 'ledger.csv', [
              [tr('التاريخ'), tr('المرجع'), tr('البيان'), tr('مدين'), tr('دائن'), tr('الرصيد')],
              for (final l in lines) [dayKey(l.date), l.ref, l.text, l.debit == 0 ? '' : l.debit, l.credit == 0 ? '' : l.credit, l.balance],
            ]),
          ),
        ],
      ),
      body: rows.isEmpty
          ? EmptyState(icon: Icons.menu_book_outlined, title: tr('لا حركات على هذا الحساب'))
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: rows.length + 1,
              itemBuilder: (c, i) {
                if (i == 0) {
                  return ListTile(
                    title: Text(tr('الرصيد الحالي'), style: const TextStyle(fontWeight: FontWeight.w800)),
                    trailing: Text(fmtMoney(lines.last.balance), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                  );
                }
                final l = rows[i - 1];
                final inc = l.debit > 0;
                return ListTile(
                  dense: true,
                  title: Text(l.text, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${dayKey(l.date)}${l.ref.isEmpty ? '' : ' • ${l.ref}'} • ${tr('الرصيد')} ${fmtNum(l.balance)}'),
                  trailing: Text('${inc ? '+' : '−'}${fmtNum(inc ? l.debit : l.credit)}',
                      style: TextStyle(fontWeight: FontWeight.w800, color: inc ? const Color(0xFF16A34A) : context.colors.error)),
                );
              },
            ),
    );
  }
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
