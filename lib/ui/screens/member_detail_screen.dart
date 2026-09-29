import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/phone.dart';
import '../../core/ids.dart';
import '../../core/money.dart';
import '../../models/activity.dart';
import '../../models/billing.dart';
import '../../models/business.dart';
import '../../models/member.dart';
import '../../models/plan.dart';
import '../../models/subscription.dart';
import '../../models/settings.dart';
import '../../services/membership.dart';
import '../../services/templates.dart';
import '../theme.dart';
import '../../services/license.dart';
import '../widgets/upgrade.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import 'dashboard_screen.dart';
import 'finance_screen.dart';
import 'invoice_screen.dart';
import 'member_card.dart';
import 'member_form_screen.dart';
import 'sale_screen.dart';

class MemberDetailScreen extends StatelessWidget {
  final String memberId;
  const MemberDetailScreen({super.key, required this.memberId});

  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    final m = g.members[memberId];
    if (m == null) return Scaffold(appBar: AppBar(), body: EmptyState(icon: Icons.person_off, title: tr('العضو غير موجود')));
    final sv = context.services;
    final ms = sv.members;
    final st = ms.stateOf(m.id);
    final sub = ms.currentSub(m.id);
    final bal = g.balanceOf(m.id);
    final pts = ms.ptSubs(m.id).where((s) => s.statusOn(g.today) == SubStatus.active).toList();

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: Text('#${m.code}'),
          actions: [
            IconButton(tooltip: tr('تعديل'), icon: const Icon(Icons.edit_outlined), onPressed: () => context.push(MemberFormScreen(memberId: m.id))),
            PopupMenuButton<String>(
              onSelected: (v) => _menu(context, v, m, sub),
              itemBuilder: (_) => [
                if (sub != null && sub.statusOn(g.today) != SubStatus.frozen && !sub.cancelled)
                  PopupMenuItem(value: 'freeze', child: ListTile(leading: const Icon(Icons.ac_unit), title: Text(tr('تجميد الاشتراك')))),
                if (sub != null && sub.upcomingFreeze(g.today) != null)
                  PopupMenuItem(value: 'unfreeze', child: ListTile(leading: const Icon(Icons.wb_sunny_outlined), title: Text(tr('إنهاء التجميد')))),
                if (sub != null && g.can(Perm.override))
                  PopupMenuItem(value: 'adjust', child: ListTile(leading: const Icon(Icons.edit_calendar), title: Text(tr('تعديل تاريخ الانتهاء')))),
                if (sub != null && g.can(Perm.refund))
                  PopupMenuItem(value: 'cancel', child: ListTile(leading: const Icon(Icons.cancel_outlined), title: Text(tr('إلغاء الاشتراك واسترداد')))),
                if (sub != null && g.can(Perm.sell))
                  PopupMenuItem(value: 'renewal', child: ListTile(leading: const Icon(Icons.autorenew), title: Text(tr('إرسال طلب تجديد')), trailing: lockFor(context, Feature.autoRenew))),
                PopupMenuItem(value: 'invoice', child: ListTile(leading: const Icon(Icons.receipt_long_outlined), title: Text(tr('فاتورة يدوية')))),
                PopupMenuItem(value: 'measure', child: ListTile(leading: const Icon(Icons.monitor_weight_outlined), title: Text(tr('إضافة قياسات')))),
                PopupMenuItem(value: 'archive', child: ListTile(leading: const Icon(Icons.archive_outlined), title: Text(m.archived ? tr('إلغاء الأرشفة') : tr('أرشفة العضو')))),
                if (g.can(Perm.deleteData))
                  PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline, color: context.colors.error), title: Text(tr('حذف نهائي')))),
              ],
            ),
          ],
        ),
        body: NestedScrollView(
          headerSliverBuilder: (c, _) => [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    MemberAvatar(m, radius: 34, ring: memberStateStyle(st).color),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(m.name, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(m.phone, style: TextStyle(color: context.colors.onSurfaceVariant), textDirection: TextDirection.ltr),
                        const SizedBox(height: 6),
                        Wrap(spacing: 6, runSpacing: 4, children: [
                          StatePill(st),
                          if (m.isBirthday(g.today)) Pill(tr('عيد ميلاده 🎂'), const Color(0xFFDB2777)),
                          if (m.optOut) Pill(tr('أوقف الرسائل'), StatusColors.none),
                          if (m.archived) Pill(tr('مؤرشف'), StatusColors.none),
                        ]),
                      ]),
                    ),
                  ]),
                  if (m.medicalNotes != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: StatusColors.expired.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
                      child: Row(children: [
                        const Icon(Icons.medical_information_outlined, color: StatusColors.expired),
                        const SizedBox(width: 8),
                        Expanded(child: Text(m.medicalNotes!)),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _SubCard(m: m, sub: sub, st: st),
                  if (bal > 0.001) ...[
                    const SizedBox(height: 10),
                    Card(
                      color: StatusColors.expired.withValues(alpha: 0.06),
                      child: ListTile(
                        leading: const Icon(Icons.account_balance_wallet_outlined, color: StatusColors.expired),
                        title: Text(tr('المستحق عليه: {a}', {'a': fmtMoney(bal)}), style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: g.overdueOf(m.id) > 0 ? Text(tr('متأخر: {a}', {'a': fmtMoney(g.overdueOf(m.id))})) : null,
                        trailing: g.can(Perm.sell)
                            ? FilledButton(onPressed: () => showCollectDialog(context, memberId: m.id), child: Text(tr('تحصيل')))
                            : null,
                      ),
                    ),
                  ],
                  for (final pt in pts) ...[
                    const SizedBox(height: 10),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.sports, color: Color(0xFF6D4C41)),
                        title: Text(pt.planName, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('${g.staff[pt.trainerId]?.name ?? ''} • ${tr('متبقي {n} من {t}', {'n': pt.visitsLeft, 't': pt.visitsTotal})}'),
                        trailing: OutlinedButton(
                          onPressed: () => runAction(context, () => sv.checkin.recordPtSession(pt), success: tr('سُجلت الجلسة ✓')),
                          child: Text(tr('جلسة')),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      if (g.can(Perm.sell))
                        ActionCircle(icon: Icons.autorenew, label: sub == null ? tr('اشتراك') : tr('تجديد'), color: StatusColors.active, onTap: () => context.push(SaleScreen(memberId: m.id))),
                      ActionCircle(icon: Icons.login, label: tr('دخول'), color: brandSeed, onTap: () => _checkin(context, m)),
                      ActionCircle(icon: Icons.chat, label: tr('واتساب'), color: const Color(0xFF25D366), onTap: () => showComposeDialog(context, m)),
                      ActionCircle(icon: Icons.call_outlined, label: tr('اتصال'), color: const Color(0xFF0EA5E9), onTap: () => sv.call(m.phone)),
                      ActionCircle(icon: Icons.qr_code_2, label: tr('البطاقة'), color: const Color(0xFF6366F1), onTap: () => showMemberCard(context, m)),
                      if (g.can(Perm.sell) && bal > 0)
                        ActionCircle(icon: Icons.payments_outlined, label: tr('تحصيل'), color: StatusColors.expired, onTap: () => showCollectDialog(context, memberId: m.id)),
                    ]),
                  ),
                ]),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabsHeader(TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: tr('الاشتراكات')),
                  Tab(text: tr('الفواتير')),
                  Tab(text: tr('الحضور')),
                  Tab(text: tr('القياسات')),
                  Tab(text: tr('الرسائل')),
                ],
              ), context.colors.surface),
            ),
          ],
          body: TabBarView(children: [
            _SubsTab(m: m),
            _InvoicesTab(m: m),
            _VisitsTab(m: m),
            _MeasurementsTab(m: m),
            _MessagesTab(m: m),
          ]),
        ),
      ),
    );
  }

  Future<void> _checkin(BuildContext context, Member m) async {
    final sv = context.services;
    final dec = sv.checkin.evaluate(m);
    if (dec.allowed) {
      await runAction(context, () => sv.checkin.commit(dec, method: 'manual'), success: '${dec.message} ✓');
      return;
    }
    final canOverride = dec.overridable && context.gym.can(Perm.override);
    final ok = await confirm(context, tr('الدخول مرفوض'), message: dec.message, ok: canOverride ? tr('سماح استثنائي') : tr('حسناً'), danger: canOverride);
    if (ok && canOverride && context.mounted) {
      await runAction(context, () => sv.checkin.commit(dec, override: true), success: tr('سُجل الدخول استثنائياً'));
    }
  }

  Future<void> _menu(BuildContext context, String v, Member m, Subscription? sub) async {
    final g = context.gym;
    final sv = context.services;
    switch (v) {
      case 'freeze':
        await _freezeDialog(context, sub!);
      case 'unfreeze':
        if (await confirm(context, tr('إنهاء التجميد اليوم؟'), message: tr('تُعاد الأيام غير المستخدمة للاشتراك'))) {
          if (context.mounted) await runAction(context, () => sv.members.unfreeze(sub!), success: tr('انتهى التجميد'));
        }
      case 'adjust':
        final d = await pickDay(context, sub!.end, first: sub.start);
        if (d == null || !context.mounted) return;
        final reason = await askText(context, tr('سبب التعديل'), hint: tr('تعويض، خطأ إدخال...'));
        if (reason == null || !context.mounted) return;
        await runAction(context, () => sv.members.adjustEnd(sub, d, reason), success: tr('تم التعديل'));
      case 'cancel':
        await _cancelDialog(context, sub!);
      case 'renewal':
        if (!await ensureFeature(context, Feature.autoRenew) || !context.mounted) return;
        final plan = g.plans[sub!.planId];
        if (plan == null || !plan.active) {
          context.toast(tr('باقة الاشتراك الحالي غير متاحة للبيع'), error: true);
          return;
        }
        final inv = await runAction(context, () => sv.members.createRenewalInvoice(m, plan));
        if (inv == null || !context.mounted) return;
        final msg = sv.reminders.build(
            member: m,
            kind: Rk.renewalRequest,
            body: renderTemplate(g.settings.template(Rk.renewalRequest), {...TemplateContext(g).forSub(m, sub), ...TemplateContext(g).forInvoice(m, inv)}),
            invoiceId: inv.id);
        if (msg != null) {
          final r = await runAction(context, () => sv.send(msg));
          if (r != null && context.mounted) context.toast(r);
        }
      case 'invoice':
        await _manualInvoice(context, m);
      case 'measure':
        if (await ensureFeature(context, Feature.measurements) && context.mounted) await showMeasurementDialog(context, m);
      case 'archive':
        m.archived = !m.archived;
        await g.put(m);
      case 'delete':
        final ok = await confirm(context, tr('حذف {n} نهائياً؟', {'n': m.name}),
            message: tr('ستُحذف بيانات العضو وسجل حضوره. الفواتير تبقى في الحسابات. الأفضل استخدام الأرشفة.'), ok: tr('حذف'), danger: true);
        if (!ok || !context.mounted) return;
        await g.removeWhere<Checkin>((c) => c.memberId == m.id);
        await g.removeWhere<Measurement>((x) => x.memberId == m.id);
        await g.log('delete', '${m.name} #${m.code}');
        await g.remove(m);
        if (context.mounted) Navigator.pop(context);
    }
  }

  Future<void> _freezeDialog(BuildContext context, Subscription s) async {
    final g = context.gym;
    var start = g.today;
    final days = TextEditingController(text: '${s.freezeDaysLeft > 0 ? (s.freezeDaysLeft > 7 ? 7 : s.freezeDaysLeft) : 7}');
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(tr('تجميد الاشتراك')),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr('المتبقي من حق التجميد: {d} يوم و{t} مرة', {'d': s.freezeDaysLeft, 't': s.freezeTimesLeft})),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text(tr('من تاريخ')),
              trailing: Text(fmtDay(start)),
              onTap: () async {
                final d = await pickDay(c, start, first: g.today);
                if (d != null) set(() => start = d);
              },
            ),
            TextField(controller: days, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('عدد الأيام'))),
            const SizedBox(height: 12),
            TextField(controller: reason, decoration: InputDecoration(labelText: tr('السبب (سفر، مرض...)'))),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('إلغاء'))),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('تجميد'))),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    await runAction(context,
        () => context.services.members.freeze(s, start: start, days: parseIntInput(days.text) ?? 0, reason: reason.text.trim().isEmpty ? null : reason.text.trim()),
        success: tr('تم التجميد، ومُدّد الاشتراك'));
  }

  Future<void> _cancelDialog(BuildContext context, Subscription s) async {
    final g = context.gym;
    final inv = g.invoices[s.invoiceId];
    final paid = inv?.paid ?? 0;
    final refund = TextEditingController(text: '0');
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('إلغاء الاشتراك')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(tr('المدفوع في هذا الاشتراك: {a}', {'a': fmtMoney(paid)})),
          const SizedBox(height: 12),
          TextField(controller: refund, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: tr('المبلغ المسترد'))),
          const SizedBox(height: 12),
          TextField(controller: reason, decoration: InputDecoration(labelText: tr('السبب'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('رجوع'))),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: context.colors.error), onPressed: () => Navigator.pop(c, true), child: Text(tr('إلغاء الاشتراك'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await runAction(
        context,
        () => context.services.members.cancel(s,
            reason: reason.text.trim().isEmpty ? tr('بدون سبب') : reason.text.trim(), refund: parseAmount(refund.text) ?? 0),
        success: tr('أُلغي الاشتراك'));
  }

  Future<void> _manualInvoice(BuildContext context, Member m) async {
    final desc = TextEditingController();
    final price = TextEditingController();
    var kind = ItemKind.other;
    var paidNow = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(tr('فاتورة يدوية')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<ItemKind>(
              initialValue: kind,
              items: [
                DropdownMenuItem(value: ItemKind.other, child: Text(tr('أخرى'))),
                DropdownMenuItem(value: ItemKind.locker, child: Text(tr('خزانة'))),
                DropdownMenuItem(value: ItemKind.classFee, child: Text(tr('حصة'))),
                DropdownMenuItem(value: ItemKind.pt, child: Text(tr('تدريب شخصي'))),
              ],
              onChanged: (v) => set(() => kind = v!),
              decoration: InputDecoration(labelText: tr('النوع')),
            ),
            const SizedBox(height: 12),
            TextField(controller: desc, decoration: InputDecoration(labelText: tr('الوصف'))),
            const SizedBox(height: 12),
            TextField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: tr('المبلغ'))),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(tr('مدفوعة نقداً الآن')), value: paidNow, onChanged: (v) => set(() => paidNow = v)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('إلغاء'))),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('حفظ'))),
          ],
        ),
      ),
    );
    final amount = parseAmount(price.text) ?? 0;
    if (ok != true || amount <= 0 || !context.mounted) return;
    final inv = await runAction(
        context,
        () => context.services.billing.customInvoice(
              memberId: m.id,
              items: [InvoiceItem(kind: kind, description: desc.text.trim().isEmpty ? tr('خدمة') : desc.text.trim(), unitPrice: amount)],
              payments: paidNow ? [PayInput(context.services.members.totalWithTax(amount), PayMethod.cash)] : const [],
            ));
    if (inv != null && context.mounted) context.push(InvoiceScreen(invoiceId: inv.id));
  }
}

class _TabsHeader extends SliverPersistentHeaderDelegate {
  final TabBar bar;
  final Color bg;
  _TabsHeader(this.bar, this.bg);
  @override
  double get minExtent => bar.preferredSize.height;
  @override
  double get maxExtent => bar.preferredSize.height;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) =>
      Container(color: Theme.of(context).scaffoldBackgroundColor, child: bar);
  @override
  bool shouldRebuild(covariant _TabsHeader old) => false;
}

class _SubCard extends StatelessWidget {
  final Member m;
  final Subscription? sub;
  final MemberState st;
  const _SubCard({required this.m, required this.sub, required this.st});

  @override
  Widget build(BuildContext context) {
    final g = context.gym;
    final s = sub;
    if (s == null) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text(tr('لا يوجد اشتراك')),
          trailing: g.can(Perm.sell) ? FilledButton(onPressed: () => context.push(SaleScreen(memberId: m.id)), child: Text(tr('اشترك الآن'))) : null,
        ),
      );
    }
    final today = g.today;
    final dl = s.daysLeft(today);
    final freeze = s.freezeOn(today);
    final next = context.services.members.nextSub(m.id, s);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(s.planName, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
            Text(
              s.visitsLeft != null
                  ? tr('{n} حصة متبقية', {'n': s.visitsLeft})
                  : (dl >= 0 ? (dl == 0 ? tr('آخر يوم') : tr('{n} يوم متبقٍ', {'n': dl})) : tr('انتهى منذ {n} يوم', {'n': -dl})),
              style: TextStyle(fontWeight: FontWeight.w800, color: memberStateStyle(st).color),
            ),
          ]),
          const SizedBox(height: 8),
          SubProgress(daysTotal: s.totalDays, daysLeft: dl < 0 ? -1 : dl, visitsTotal: s.visitsTotal, visitsLeft: s.visitsLeft),
          const SizedBox(height: 8),
          Wrap(alignment: WrapAlignment.spaceBetween, spacing: 12, runSpacing: 4, children: [
            Text('${fmtDay(s.start)} – ${fmtDay(s.end)}', style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 13)),
            if (s.freezeDaysAllowed > 0)
              Text(tr('تجميد متبقٍ: {n} يوم', {'n': s.freezeDaysLeft}), style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 12)),
          ]),
          if (freeze != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Pill(tr('مجمّد حتى {d}', {'d': fmtDay(freeze.end)}), StatusColors.frozen, icon: Icons.ac_unit),
            ),
          if (next != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Pill(tr('مُجدَّد: {p} يبدأ {d}', {'p': next.planName, 'd': fmtDay(next.start)}), StatusColors.active, icon: Icons.check),
            ),
          if (g.lastVisit(m.id) != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(tr('آخر زيارة: {d}', {'d': relativeDays(-daysBetween(g.lastVisit(m.id)!.time, today))}),
                  style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 12)),
            ),
        ]),
      ),
    );
  }
}

class _SubsTab extends StatelessWidget {
  final Member m;
  const _SubsTab({required this.m});
  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    final list = g.subsOf(m.id).reversed.toList();
    if (list.isEmpty) return EmptyState(icon: Icons.card_membership, title: tr('لا توجد اشتراكات'));
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: list.length,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (c, i) {
        final s = list[i];
        final st = s.statusOn(g.today);
        final color = switch (st) {
          SubStatus.active => StatusColors.active,
          SubStatus.pending => StatusColors.pending,
          SubStatus.frozen => StatusColors.frozen,
          SubStatus.cancelled => StatusColors.none,
          _ => StatusColors.expired,
        };
        final label = switch (st) {
          SubStatus.active => tr('فعّال'),
          SubStatus.pending => tr('لم يبدأ'),
          SubStatus.frozen => tr('مجمّد'),
          SubStatus.cancelled => tr('ملغي'),
          SubStatus.exhausted => tr('انتهت الحصص'),
          SubStatus.expired => tr('منتهي'),
        };
        return ListTile(
          leading: Icon(s.kind == PlanKind.pt ? Icons.sports : Icons.card_membership, color: color),
          title: Text(s.planName, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text([
            '${fmtDay(s.start)} – ${fmtDay(s.end)}',
            if (s.visitsTotal != null) tr('{u} من {t} حصة', {'u': s.visitsUsed, 't': s.visitsTotal}),
            if (s.freezes.isNotEmpty) tr('جُمّد {n} يوم', {'n': s.freezeDaysUsed}),
            if (s.imported) tr('مستورد'),
            if (s.cancelReason != null) s.cancelReason!,
          ].join(' • ')),
          trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Pill(label, color),
            if (s.total > 0) Text(fmtMoney(s.total), style: const TextStyle(fontSize: 12)),
          ]),
          onTap: s.invoiceId == null ? null : () => context.push(InvoiceScreen(invoiceId: s.invoiceId!)),
        );
      },
    );
  }
}

class _InvoicesTab extends StatelessWidget {
  final Member m;
  const _InvoicesTab({required this.m});
  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    final list = g.invoicesOf(m.id).toList()..sort((a, b) => b.date.compareTo(a.date));
    if (list.isEmpty) return EmptyState(icon: Icons.receipt_long, title: tr('لا توجد فواتير'));
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: list.length,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (c, i) => InvoiceTile(inv: list[i], showMember: false),
    );
  }
}

class _VisitsTab extends StatelessWidget {
  final Member m;
  const _VisitsTab({required this.m});
  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    final list = g.checkinsOf(m.id).toList()..sort((a, b) => b.time.compareTo(a.time));
    if (list.isEmpty) return EmptyState(icon: Icons.login, title: tr('لا توجد زيارات'));
    final last30 = list.where((c) => c.allowed && daysBetween(c.time, g.today) < 30).length;
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Text(tr('{n} زيارة في آخر 30 يوماً • الإجمالي {t}', {'n': last30, 't': list.where((c) => c.allowed).length}),
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      for (final c in list.take(200))
        ListTile(
          dense: true,
          leading: Icon(c.allowed ? (c.method == 'pt' ? Icons.sports : Icons.check_circle) : Icons.block,
              color: c.allowed ? StatusColors.active : StatusColors.expired, size: 20),
          title: Text('${dayKey(c.time)}  ${hhmm(minutesOfDay(c.time))}'),
          subtitle: Text([
            checkinResultText(c.result),
            if (c.method == 'pt') tr('تدريب شخصي'),
            if (c.method == 'class') c.note ?? tr('حصة'),
            if (c.by != null) c.by!,
          ].join(' • ')),
        ),
    ]);
  }
}

class _MeasurementsTab extends StatelessWidget {
  final Member m;
  const _MeasurementsTab({required this.m});
  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    final list = g.measurementsOf(m.id);
    if (!g.has(Feature.measurements)) {
      return EmptyState(
        icon: Icons.lock_outline,
        title: featureName(Feature.measurements),
        message: tr('متاحة في نسخة {t}', {'t': tierName(featureTier[Feature.measurements]!)}),
        action: FilledButton(onPressed: () => showUpgradeDialog(context, feature: Feature.measurements), child: Text(tr('عرض الباقات'))),
      );
    }
    if (list.isEmpty) {
      return EmptyState(
        icon: Icons.monitor_weight_outlined,
        title: tr('لا توجد قياسات'),
        message: tr('سجّل الوزن ونسبة الدهون لمتابعة تقدّم العضو'),
        action: FilledButton.icon(onPressed: () => showMeasurementDialog(context, m), icon: const Icon(Icons.add), label: Text(tr('إضافة قياسات'))),
      );
    }
    final weights = list.where((x) => x.weight != null).toList();
    final first = list.first, last = list.last;
    String diff(double? a, double? b, String unit) {
      if (a == null || b == null) return '—';
      final d = b - a;
      return '${d > 0 ? '+' : ''}${d.toStringAsFixed(1)} $unit';
    }

    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        Expanded(child: Kpi(label: tr('الوزن'), value: last.weight?.toStringAsFixed(1) ?? '—', sub: diff(first.weight, last.weight, tr('كجم')), icon: Icons.monitor_weight_outlined, color: brandSeed)),
        const SizedBox(width: 10),
        Expanded(child: Kpi(label: tr('نسبة الدهون'), value: last.bodyFat == null ? '—' : '${last.bodyFat!.toStringAsFixed(1)}%', sub: diff(first.bodyFat, last.bodyFat, '%'), icon: Icons.water_drop_outlined, color: StatusColors.expiring)),
        const SizedBox(width: 10),
        Expanded(child: Kpi(label: tr('مؤشر كتلة الجسم'), value: last.bmi?.toStringAsFixed(1) ?? '—', icon: Icons.straighten, color: const Color(0xFF6366F1))),
      ]),
      if (weights.length >= 2) ...[
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 20, 20, 8),
            child: SizedBox(
              height: 180,
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: LineChart(LineChartData(
                  gridData: FlGridData(drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: context.colors.outlineVariant.withValues(alpha: 0.4), strokeWidth: 1)),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36, getTitlesWidget: (v, _) => Text(v.toStringAsFixed(0), style: const TextStyle(fontSize: 10)))),
                  ),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (spots) => [
                        for (final s in spots) LineTooltipItem('${dayKey(weights[s.x.toInt()].date)}\n${s.y.toStringAsFixed(1)} ${tr('كجم')}', const TextStyle(color: Colors.white, fontSize: 12)),
                      ],
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: [for (var i = 0; i < weights.length; i++) FlSpot(i.toDouble(), weights[i].weight!)],
                      isCurved: true,
                      color: brandSeed,
                      barWidth: 2,
                      dotData: FlDotData(getDotPainter: (_, _, _, _) => FlDotCirclePainter(radius: 4, color: brandSeed, strokeWidth: 2, strokeColor: Colors.white)),
                    ),
                  ],
                )),
              ),
            ),
          ),
        ),
      ],
      const SizedBox(height: 12),
      Row(children: [
        Text(tr('السجل'), style: context.text.titleMedium),
        const Spacer(),
        TextButton.icon(onPressed: () => showMeasurementDialog(context, m), icon: const Icon(Icons.add), label: Text(tr('إضافة'))),
      ]),
      for (final x in list.reversed)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text(dayKey(x.date), style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text([
              if (x.weight != null) '${tr('وزن')} ${x.weight!.toStringAsFixed(1)}',
              if (x.bodyFat != null) '${tr('دهون')} ${x.bodyFat!.toStringAsFixed(1)}%',
              if (x.muscle != null) '${tr('عضل')} ${x.muscle!.toStringAsFixed(1)}',
              if (x.waist != null) '${tr('خصر')} ${x.waist!.toStringAsFixed(0)}',
              if (x.notes != null) x.notes!,
            ].join(' • ')),
            trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => g.remove(x)),
          ),
        ),
    ]);
  }
}

Future<void> showMeasurementDialog(BuildContext context, Member m) async {
  final g = context.gym;
  final prev = g.measurementsOf(m.id).lastOrNull;
  final fields = <String, TextEditingController>{
    tr('الوزن (كجم)'): TextEditingController(),
    tr('الطول (سم)'): TextEditingController(text: prev?.height?.toStringAsFixed(0) ?? ''),
    tr('نسبة الدهون %'): TextEditingController(),
    tr('الكتلة العضلية (كجم)'): TextEditingController(),
    tr('الخصر (سم)'): TextEditingController(),
    tr('الصدر (سم)'): TextEditingController(),
    tr('الذراع (سم)'): TextEditingController(),
    tr('الورك (سم)'): TextEditingController(),
    tr('الفخذ (سم)'): TextEditingController(),
  };
  final notes = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(tr('قياسات {n}', {'n': m.firstName})),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final e in fields.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(controller: e.value, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: e.key)),
              ),
            TextField(controller: notes, decoration: InputDecoration(labelText: tr('ملاحظات'))),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('إلغاء'))),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('حفظ'))),
      ],
    ),
  );
  if (ok != true) return;
  final v = fields.values.map((c) => parseAmount(c.text)).toList();
  await g.put(Measurement(
    id: newId(),
    memberId: m.id,
    date: g.today,
    weight: v[0],
    height: v[1],
    bodyFat: v[2],
    muscle: v[3],
    waist: v[4],
    chest: v[5],
    arm: v[6],
    hip: v[7],
    thigh: v[8],
    notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
  ));
}

class _MessagesTab extends StatelessWidget {
  final Member m;
  const _MessagesTab({required this.m});
  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    final list = g.messagesOf(m.id).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: OutlinedButton.icon(onPressed: () => showComposeDialog(context, m), icon: const Icon(Icons.edit), label: Text(tr('رسالة جديدة'))),
      ),
      if (list.isEmpty) EmptyState(icon: Icons.chat_bubble_outline, title: tr('لا توجد رسائل')),
      for (final x in list)
        ListTile(
          leading: Icon(x.channel == Channel.whatsapp ? Icons.chat : Icons.sms_outlined,
              color: x.status == MsgStatus.sent ? StatusColors.active : (x.status == MsgStatus.failed ? StatusColors.expired : StatusColors.expiring)),
          title: Text(x.body, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text('${dayKey(x.createdAt)} • ${msgStatusText(x.status)}'),
          onTap: () => showDialog(
            context: context,
            builder: (c) => AlertDialog(content: SelectableText(x.body), actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('إغلاق')))]),
          ),
        ),
    ]);
  }
}

String msgStatusText(MsgStatus s) => switch (s) {
      MsgStatus.queued => tr('في الانتظار'),
      MsgStatus.manual => tr('جاهزة للإرسال'),
      MsgStatus.sent => tr('أُرسلت'),
      MsgStatus.failed => tr('فشلت'),
      MsgStatus.cancelled => tr('أُلغيت'),
    };
