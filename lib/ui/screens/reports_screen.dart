import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/money.dart';
import '../../services/data_tools.dart';
import '../../services/reports.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import 'member_detail_screen.dart';

enum _Period { today, week, month, last30, year, custom }

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  _Period _p = _Period.month;
  Range? _custom;

  Range _range(DateTime now) => switch (_p) {
        _Period.today => Range.today(now),
        _Period.week => Range.lastDays(now, 7),
        _Period.month => Range.thisMonth(now),
        _Period.last30 => Range.lastDays(now, 30),
        _Period.year => Range.thisYear(now),
        _Period.custom => _custom ?? Range.thisMonth(now),
      };

  String _pName(_Period p) => switch (p) {
        _Period.today => tr('اليوم'),
        _Period.week => tr('7 أيام'),
        _Period.month => tr('هذا الشهر'),
        _Period.last30 => tr('30 يوماً'),
        _Period.year => tr('هذه السنة'),
        _Period.custom => tr('فترة محددة'),
      };

  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    final sv = context.services;
    final rep = sv.reports;
    final r = _range(g.now());
    final collected = rep.collected(r);
    final expenses = rep.expenses(r);
    final byMethod = rep.collectedByMethod(r);
    final byKind = rep.salesByKind(r);
    final expCat = rep.expensesByCategory(r);
    final sold = rep.subsSold(r);
    final ren = rep.renewalRate(r);
    final visits = rep.dailyVisits(r);
    final totalVisits = visits.fold(0, (s, x) => s + x.count);
    final hours = rep.visitsByHour(r);
    final wd = rep.visitsByWeekday(r);
    final plans = rep.planPopularity(r);
    final trainers = rep.trainers(r);
    final top = rep.topAttendees(r, limit: 5);

    // التحصيل: يومي حتى شهرين، ثم شهري
    List<double> vals;
    List<String> labels;
    List<String> tips;
    if (r.days <= 62) {
      final s = rep.dailyCollections(r);
      vals = [for (final x in s) x.value];
      final step = (s.length / 8).ceil().clamp(1, 100);
      labels = [for (var i = 0; i < s.length; i++) i % step == 0 ? '${s[i].day.day}' : ''];
      tips = [for (final x in s) dayKey(x.day)];
    } else {
      final m = <String, double>{};
      for (final x in rep.dailyCollections(r)) {
        final k = '${x.day.year}-${x.day.month.toString().padLeft(2, '0')}';
        m[k] = (m[k] ?? 0) + x.value;
      }
      vals = m.values.toList();
      labels = [for (final k in m.keys) k.substring(5)];
      tips = m.keys.toList();
    }
    final maxMethod = byMethod.values.fold(0.0, (a, b) => b > a ? b : a);
    final maxKind = byKind.values.fold(0.0, (a, b) => b > a ? b : a);
    final maxExp = expCat.values.fold(0.0, (a, b) => b > a ? b : a);
    final maxPlan = plans.fold(0, (a, b) => b.count > a ? b.count : a);

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('التقارير')),
        actions: [
          IconButton(
            tooltip: tr('تقرير PDF'),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () => runAction(context, () async {
              final bytes = await (await sv.pdf()).periodReport(r);
              await sv.shareFile(bytes, 'report-${dayKey(r.from)}-${dayKey(r.to)}.pdf', 'application/pdf');
            }),
          ),
          IconButton(
            tooltip: tr('تصدير الدفعات CSV'),
            icon: const Icon(Icons.table_view_outlined),
            onPressed: () => runAction(context, () async {
              final rows = <List<Object?>>[
                [tr('رقم الإيصال'), tr('التاريخ'), tr('العضو'), tr('الفاتورة'), tr('طريقة الدفع'), tr('المبلغ'), tr('المرجع'), tr('الموظف')],
                for (final p in rep.paymentsIn(r))
                  [p.number, '${dayKey(p.date)} ${hhmm(minutesOfDay(p.date))}', g.members[p.memberId]?.name ?? '', g.invoices[p.invoiceId]?.number ?? '', payMethodName(p.method), p.amount, p.reference ?? '', p.by ?? ''],
              ];
              await sv.shareFile(Uint8List.fromList(utf8.encode(toCsv(rows))), 'payments-${dayKey(r.from)}.csv', 'text/csv');
            }),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        SizedBox(
          height: 48,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), children: [
            for (final p in _Period.values)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text(p == _Period.custom && _custom != null ? '${dayKey(_custom!.from)} – ${dayKey(_custom!.to)}' : _pName(p)),
                  selected: _p == p,
                  onSelected: (_) async {
                    if (p == _Period.custom) {
                      final dr = await showDateRangePicker(context: context, firstDate: DateTime(2015), lastDate: DateTime(2100), initialDateRange: DateTimeRange(start: r.from, end: r.to));
                      if (dr == null) return;
                      _custom = Range(dr.start, dr.end);
                    }
                    setState(() => _p = p);
                  },
                ),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: ResponsiveGrid(minWidth: 160, children: [
            Kpi(label: tr('المحصّل'), value: fmtMoney(collected), icon: Icons.payments_outlined, color: brandSeed),
            Kpi(label: tr('المصروفات'), value: fmtMoney(expenses), icon: Icons.south_west, color: StatusColors.expired),
            Kpi(label: tr('صافي الربح'), value: fmtMoney(collected - expenses), icon: Icons.trending_up, color: collected >= expenses ? StatusColors.active : StatusColors.expired),
            Kpi(label: tr('أعضاء جدد'), value: '${sold.fresh}', sub: tr('تجديد: {n}', {'n': sold.renewals}), icon: Icons.person_add_alt, color: const Color(0xFF6366F1)),
            Kpi(label: tr('نسبة التجديد'), value: ren.ended == 0 ? '—' : '${(ren.rate * 100).round()}%', sub: tr('{r} من {e} انتهى', {'r': ren.renewed, 'e': ren.ended}), icon: Icons.autorenew, color: StatusColors.expiring),
            Kpi(label: tr('الزيارات'), value: fmtNum(totalVisits), sub: tr('متوسط {n}/يوم', {'n': (totalVisits / r.days).toStringAsFixed(0)}), icon: Icons.directions_run, color: const Color(0xFF0EA5E9)),
          ]),
        ),
        Section(
          title: tr('التحصيل'),
          child: Card(child: Padding(padding: const EdgeInsets.fromLTRB(8, 16, 8, 8), child: SimpleBarChart(values: vals, labels: labels, tooltipTitles: tips, format: (v) => fmtMoney(v)))),
        ),
        if (byMethod.isNotEmpty)
          Section(
            title: tr('حسب طريقة الدفع'),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(children: [
                  for (final e in byMethod.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
                    ShareBar(label: payMethodName(e.key), value: fmtMoney(e.value), fraction: maxMethod == 0 ? 0 : e.value / maxMethod),
                ]),
              ),
            ),
          ),
        if (byKind.isNotEmpty)
          Section(
            title: tr('المبيعات حسب النوع'),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(children: [
                  for (final e in byKind.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
                    ShareBar(label: itemKindName(e.key), value: fmtMoney(e.value), fraction: maxKind == 0 ? 0 : e.value / maxKind),
                  if (rep.taxCollected(r) > 0) InfoRow(tr('منها ضريبة'), fmtMoney(rep.taxCollected(r))),
                ]),
              ),
            ),
          ),
        if (expCat.isNotEmpty)
          Section(
            title: tr('المصروفات'),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(children: [
                  for (final e in expCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
                    ShareBar(label: tr(e.key), value: fmtMoney(e.value), fraction: maxExp == 0 ? 0 : e.value / maxExp, color: StatusColors.expired),
                ]),
              ),
            ),
          ),
        if (totalVisits > 0) ...[
          Section(
            title: tr('أوقات الذروة'),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
                child: SimpleBarChart(
                  values: [for (var h = 5; h < 24; h++) hours[h].toDouble()],
                  labels: [for (var h = 5; h < 24; h++) h % 3 == 0 ? '$h' : ''],
                  tooltipTitles: [for (var h = 5; h < 24; h++) hhmmRange(h * 60, (h + 1) * 60 % 1440)],
                  format: (v) => tr('{n} زيارة', {'n': v.toInt()}),
                  color: const Color(0xFF0EA5E9),
                ),
              ),
            ),
          ),
          Section(
            title: tr('الزيارات حسب اليوم'),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
                child: SimpleBarChart(
                  values: [for (final d in weekOrder) wd[d]!.toDouble()],
                  labels: [for (final d in weekOrder) I18n.isAr ? weekdayNamesAr[d]!.substring(0, 3) : weekdayNamesEn[d]!],
                  tooltipTitles: [for (final d in weekOrder) I18n.isAr ? weekdayNamesAr[d]! : weekdayNamesEn[d]!],
                  format: (v) => tr('{n} زيارة', {'n': v.toInt()}),
                  color: const Color(0xFF0EA5E9),
                  height: 150,
                ),
              ),
            ),
          ),
        ],
        if (plans.isNotEmpty)
          Section(
            title: tr('الباقات الأكثر مبيعاً'),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(children: [
                  for (final p in plans.take(8))
                    ShareBar(label: '${p.plan} (${p.count})', value: fmtMoney(p.revenue), fraction: maxPlan == 0 ? 0 : p.count / maxPlan, color: const Color(0xFF6366F1)),
                ]),
              ),
            ),
          ),
        if (trainers.isNotEmpty)
          Section(
            title: tr('المدربون'),
            child: Card(
              child: Column(children: [
                for (final t in trainers)
                  ListTile(
                    title: Text(g.staff[t.trainerId]?.name ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(tr('مبيعات تدريب {s} • {n} جلسة', {'s': fmtMoney(t.ptSales), 'n': t.sessions})),
                    trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(fmtMoney(t.commission + t.sessionPay), style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text(tr('مستحق'), style: const TextStyle(fontSize: 11)),
                    ]),
                  ),
              ]),
            ),
          ),
        if (top.isNotEmpty)
          Section(
            title: tr('الأكثر حضوراً'),
            child: Card(
              child: Column(children: [
                for (final t in top)
                  if (g.members[t.memberId] case final m?)
                    ListTile(
                      leading: MemberAvatar(m, radius: 18),
                      title: Text(m.name),
                      trailing: Text(tr('{n} زيارة', {'n': t.visits}), style: const TextStyle(fontWeight: FontWeight.w700)),
                      onTap: () => context.push(MemberDetailScreen(memberId: m.id)),
                    ),
              ]),
            ),
          ),
      ]),
    );
  }
}
