import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/money.dart';
import '../../models/activity.dart';
import '../../models/billing.dart';
import '../../models/member.dart';
import '../../models/plan.dart';
import '../../services/membership.dart';
import '../../services/reports.dart';
import '../widgets/common.dart';
import 'invoice_screen.dart';
import 'member_card.dart';

String planSummary(Plan p) {
  final unit = switch (p.durationUnit) {
    DurationUnit.day => tr('يوم'),
    DurationUnit.week => tr('أسبوع'),
    DurationUnit.month => tr('شهر'),
    DurationUnit.year => tr('سنة'),
  };
  final dur = '${p.durationValue} $unit';
  final parts = <String>[
    if (p.kind == PlanKind.pt) tr('تدريب شخصي'),
    if (p.visits != null) tr('{n} حصة', {'n': p.visits}) else tr('دخول غير محدود'),
    dur,
    if (p.hasTimeWindow) '${hhmm(p.accessFrom!)}-${hhmm(p.accessTo!)}',
  ];
  return parts.join(' • ');
}

class SaleScreen extends StatefulWidget {
  final String memberId;
  final String? planId;
  final bool isNewMember;
  const SaleScreen({super.key, required this.memberId, this.planId, this.isNewMember = false});

  @override
  State<SaleScreen> createState() => _SaleScreenState();
}

class _SaleScreenState extends State<SaleScreen> {
  Plan? _plan;
  DateTime? _start;
  bool _fee = false;
  String? _trainer;
  final _discount = TextEditingController();
  final _coupon = TextEditingController();
  final _paid = TextEditingController();
  final _ref = TextEditingController();
  final _notes = TextEditingController();
  PayMethod _method = PayMethod.cash;
  bool _installments = false;
  int _instCount = 2;
  List<Installment> _schedule = [];
  bool _saving = false;
  String? _quoteError;

  @override
  void initState() {
    super.initState();
    final g = context.gym;
    final plans = g.activePlans;
    // اقتراح نفس باقة آخر اشتراك عند التجديد
    final last = context.services.members.currentSub(widget.memberId);
    _plan = g.plans[widget.planId] ?? (last != null && g.plans[last.planId]?.active == true ? g.plans[last.planId] : null) ?? (plans.isEmpty ? null : plans.first);
    _selectPlan(_plan);
  }

  void _selectPlan(Plan? p) {
    _plan = p;
    if (p == null) return;
    final ms = context.services.members;
    _start = p.kind == PlanKind.pt ? context.gym.today : ms.suggestedStart(widget.memberId);
    _fee = p.registrationFee > 0 && ms.isNewMember(widget.memberId);
    _paid.text = '';
    _rebuildSchedule();
  }

  SaleRequest _request({bool withPayments = true}) => SaleRequest(
        memberId: widget.memberId,
        planId: _plan!.id,
        start: _start,
        discount: parseAmount(_discount.text) ?? 0,
        couponCode: _coupon.text.trim().isEmpty ? null : _coupon.text.trim(),
        registrationFee: _fee,
        trainerId: _plan!.kind == PlanKind.pt ? _trainer : null,
        payments: withPayments && _paidNow > 0 ? [PayInput(_paidNow, _method, _ref.text.trim().isEmpty ? null : _ref.text.trim())] : const [],
        installments: _installments ? _schedule : const [],
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      );

  ({double price, double fee, double couponDiscount, double total})? _quote() {
    if (_plan == null) return null;
    try {
      _quoteError = null;
      return context.services.members.quote(_request(withPayments: false));
    } on GymException catch (e) {
      _quoteError = e.message;
      return null;
    }
  }

  double get _total => _quote()?.total ?? 0;

  double get _paidNow {
    final v = parseAmount(_paid.text);
    if (v != null) return v;
    return _installments ? roundMoney(_total / (_instCount + 1)) : _total;
  }

  void _rebuildSchedule() {
    if (!_installments) {
      _schedule = [];
      return;
    }
    final rest = roundMoney(_total - _paidNow);
    final each = roundMoney(rest / _instCount);
    final base = _start ?? context.gym.today;
    _schedule = [
      for (var i = 0; i < _instCount; i++)
        Installment(
          due: addMonthsClamped(base, i + 1).$1,
          amount: i == _instCount - 1 ? roundMoney(rest - each * (_instCount - 1)) : each,
        ),
    ];
  }

  Future<void> _confirm() async {
    if (_plan == null) return;
    if (_installments) _rebuildSchedule();
    setState(() => _saving = true);
    final sv = context.services;
    final res = await runAction(context, () => sv.members.sell(_request()));
    if (!mounted) return;
    setState(() => _saving = false);
    if (res == null) return;
    final g = context.gym;
    final m = g.members[widget.memberId]!;
    // الرسائل التلقائية: ترحيب للعضو الجديد + إيصال الدفع (تُرسل آلياً إن كان هناك مزوّد)
    final auto = sv.dispatcher.isAuto(m.channel);
    final msgs = [
      if (widget.isNewMember) sv.reminders.welcome(m, res.subscription),
      if (res.payments.isNotEmpty) sv.reminders.receipt(res.invoice, res.payments.first),
    ].whereType<Message>().toList();
    if (auto) {
      for (final msg in msgs) {
        await g.put(msg);
        sv.dispatcher.sendOne(msg);
      }
    }
    if (!mounted) return;
    final next = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => SaleDoneSheet(invoiceId: res.invoice.id, welcome: widget.isNewMember && !auto ? sv.reminders.welcome(m, res.subscription)?.body : null, autoSent: auto && msgs.isNotEmpty),
    );
    if (!mounted) return;
    if (next == 'invoice') {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => InvoiceScreen(invoiceId: res.invoice.id)));
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    final m = g.members[widget.memberId];
    if (m == null) return const Scaffold();
    final plans = g.activePlans.where((p) => p.gender == null || m.gender == null || p.gender == m.gender).toList();
    final q = _quote();
    final ms = context.services.members;
    final current = ms.currentSub(m.id);
    final end = _plan == null || _start == null ? null : periodEnd(_start!, _plan!.durationValue, _plan!.durationUnit);
    final trainers = g.trainers;

    return Scaffold(
      appBar: AppBar(title: Text(widget.isNewMember || current == null ? tr('اشتراك جديد') : tr('تجديد الاشتراك'))),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: _saving || q == null || _plan == null ? null : _confirm,
            icon: const Icon(Icons.check_circle_outline),
            label: Text(q == null
                ? tr('اختر الباقة')
                : _paidNow > 0
                    ? tr('تأكيد واستلام {a}', {'a': fmtMoney(_paidNow)})
                    : tr('تأكيد بدون دفع (آجل)')),
          ),
        ),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: ListTile(
            leading: MemberAvatar(m),
            title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(current == null
                ? '#${m.code}'
                : '${current.planName} • ${tr('ينتهي')} ${fmtDay(current.end)}'),
            trailing: StatePill(ms.stateOf(m.id)),
          ),
        ),
        const SizedBox(height: 16),
        Text(tr('الباقة'), style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        if (plans.isEmpty)
          EmptyState(icon: Icons.inventory_outlined, title: tr('لا توجد باقات'), message: tr('أضف الباقات من «المزيد ← الباقات»')),
        ResponsiveGrid(minWidth: 150, children: [
          for (final p in plans)
            _PlanCard(
              plan: p,
              selected: _plan?.id == p.id,
              onTap: () => setState(() => _selectPlan(p)),
            ),
        ]),
        if (_plan?.kind == PlanKind.pt) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _trainer,
            decoration: InputDecoration(labelText: tr('المدرب'), prefixIcon: const Icon(Icons.sports)),
            items: [for (final t in trainers) DropdownMenuItem(value: t.id, child: Text(t.name))],
            onChanged: (v) => setState(() => _trainer = v),
          ),
          if (trainers.isEmpty)
            Padding(padding: const EdgeInsets.only(top: 6), child: Text(tr('أضف المدربين من «المزيد ← الموظفون والمدربون»'), style: TextStyle(color: context.colors.error))),
        ],
        const SizedBox(height: 16),
        if (_plan != null)
          Card(
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.event),
                title: Text(tr('يبدأ من')),
                subtitle: end == null ? null : Text('${tr('ينتهي')} ${fmtDay(end)}'),
                trailing: Text(_start == null ? '' : fmtDay(_start!), style: const TextStyle(fontWeight: FontWeight.w700)),
                onTap: () async {
                  final d = await pickDay(context, _start ?? g.today);
                  if (d != null) setState(() => _start = d);
                },
              ),
              if (_plan!.registrationFee > 0)
                SwitchListTile(
                  secondary: const Icon(Icons.app_registration),
                  title: Text(tr('رسوم التسجيل')),
                  subtitle: Text(fmtMoney(_plan!.registrationFee)),
                  value: _fee,
                  onChanged: (v) => setState(() => _fee = v),
                ),
            ]),
          ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _discount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: tr('خصم (مبلغ)'), prefixIcon: const Icon(Icons.percent)),
              onChanged: (_) => setState(() => _rebuildSchedule()),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _coupon,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(labelText: tr('كوبون'), prefixIcon: const Icon(Icons.local_offer_outlined)),
              onChanged: (_) => setState(() => _rebuildSchedule()),
            ),
          ),
        ]),
        if (_quoteError != null)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text(_quoteError!, style: TextStyle(color: context.colors.error))),
        const SizedBox(height: 16),
        if (q != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                InfoRow(_plan!.name, fmtMoney(q.price)),
                if (q.fee > 0) InfoRow(tr('رسوم التسجيل'), fmtMoney(q.fee)),
                if (q.couponDiscount > 0) InfoRow(tr('خصم الكوبون'), '- ${fmtMoney(q.couponDiscount)}', color: Colors.green),
                if ((parseAmount(_discount.text) ?? 0) > 0) InfoRow(tr('الخصم'), '- ${fmtMoney(parseAmount(_discount.text)!)}', color: Colors.green),
                if (g.settings.taxEnabled)
                  InfoRow(tr('الضريبة'), '${fmtNum(g.settings.taxRate)}% ${g.settings.taxInclusive ? tr('(شاملة)') : tr('(تضاف)')}'),
                const Divider(height: 20),
                InfoRow(tr('الإجمالي'), fmtMoney(q.total), bold: true),
              ]),
            ),
          ),
        const SizedBox(height: 16),
        Text(tr('الدفع'), style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final pm in PayMethod.values.where((x) => x != PayMethod.online))
            ChoiceChip(
              avatar: Icon(payMethodIcon(pm), size: 18),
              label: Text(payMethodName(pm)),
              selected: _method == pm,
              onSelected: (_) => setState(() => _method = pm),
            ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _paid,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: tr('المدفوع الآن'), hintText: fmtMoney(_paidNow, symbol: false), prefixIcon: const Icon(Icons.payments_outlined)),
              onChanged: (_) => setState(() => _rebuildSchedule()),
            ),
          ),
          if (_method != PayMethod.cash) ...[
            const SizedBox(width: 10),
            Expanded(
              child: TextField(controller: _ref, decoration: InputDecoration(labelText: tr('رقم العملية'), prefixIcon: const Icon(Icons.tag))),
            ),
          ],
        ]),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tr('تقسيط الباقي')),
          subtitle: Text(tr('مع تذكير تلقائي قبل كل قسط')),
          value: _installments,
          onChanged: (v) => setState(() {
            _installments = v;
            _paid.text = '';
            _rebuildSchedule();
          }),
        ),
        if (_installments) ...[
          Row(children: [
            Text(tr('عدد الأقساط')),
            const Spacer(),
            IconButton(onPressed: _instCount > 1 ? () => setState(() {
              _instCount--;
              _rebuildSchedule();
            }) : null, icon: const Icon(Icons.remove_circle_outline)),
            Text('$_instCount', style: context.text.titleMedium),
            IconButton(onPressed: _instCount < 12 ? () => setState(() {
              _instCount++;
              _rebuildSchedule();
            }) : null, icon: const Icon(Icons.add_circle_outline)),
          ]),
          Card(
            child: Column(children: [
              for (var i = 0; i < _schedule.length; i++)
                ListTile(
                  dense: true,
                  leading: CircleAvatar(radius: 14, child: Text('${i + 1}', style: const TextStyle(fontSize: 12))),
                  title: Text(fmtDay(_schedule[i].due)),
                  trailing: Text(fmtMoney(_schedule[i].amount), style: const TextStyle(fontWeight: FontWeight.w700)),
                  onTap: () async {
                    final d = await pickDay(context, _schedule[i].due);
                    if (d != null) setState(() => _schedule[i].due = d);
                  },
                ),
            ]),
          ),
        ] else if (q != null && _paidNow < q.total - 0.001)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(tr('المتبقي {a} يُسجل ديناً على العضو', {'a': fmtMoney(q.total - _paidNow)}), style: TextStyle(color: context.colors.error)),
          ),
        const SizedBox(height: 12),
        TextField(controller: _notes, decoration: InputDecoration(labelText: tr('ملاحظات'), prefixIcon: const Icon(Icons.notes))),
        const SizedBox(height: 24),
      ]),
    );
  }
}

IconData payMethodIcon(PayMethod m) => switch (m) {
      PayMethod.cash => Icons.payments_outlined,
      PayMethod.card => Icons.credit_card,
      PayMethod.transfer => Icons.account_balance_outlined,
      PayMethod.wallet => Icons.phone_iphone,
      PayMethod.online => Icons.language,
    };

class _PlanCard extends StatelessWidget {
  final Plan plan;
  final bool selected;
  final VoidCallback onTap;
  const _PlanCard({required this.plan, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = Color(plan.colorValue);
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: selected ? color : context.colors.outlineVariant.withValues(alpha: 0.5), width: selected ? 2.5 : 1),
      ),
      color: selected ? color.withValues(alpha: 0.08) : null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Expanded(child: Text(plan.name, style: const TextStyle(fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (selected) Icon(Icons.check_circle, color: color, size: 18),
            ]),
            const SizedBox(height: 6),
            Text(fmtMoney(plan.price), style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            Text(planSummary(plan), style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant), maxLines: 2),
          ]),
        ),
      ),
    );
  }
}

/// بعد البيع: إرسال الفاتورة/الترحيب، الطباعة، بطاقة العضو
class SaleDoneSheet extends StatelessWidget {
  final String invoiceId;
  final String? welcome;
  final bool autoSent;
  const SaleDoneSheet({super.key, required this.invoiceId, this.welcome, this.autoSent = false});

  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    final sv = context.services;
    final inv = g.invoices[invoiceId]!;
    final m = g.members[inv.memberId];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 56),
          const SizedBox(height: 8),
          Text(tr('تم بنجاح'), textAlign: TextAlign.center, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          Text('${inv.number} • ${fmtMoney(inv.total)}${inv.balance > 0 ? ' • ${tr('المتبقي')} ${fmtMoney(inv.balance)}' : ''}', textAlign: TextAlign.center),
          if (autoSent) Padding(padding: const EdgeInsets.only(top: 4), child: Text(tr('أُرسل الإيصال للعضو تلقائياً ✓'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.green))),
          const SizedBox(height: 16),
          if (m != null) ...[
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
              onPressed: () => runAction(context, () => sv.sendInvoice(inv, channel: Channel.whatsapp)),
              icon: const Icon(Icons.chat),
              label: Text(tr('إرسال الفاتورة بواتساب')),
            ),
            const SizedBox(height: 8),
            if (welcome != null) ...[
              OutlinedButton.icon(
                onPressed: () => runAction(context, () async {
                  final msg = sv.reminders.welcome(m, g.subs.all.firstWhere((s) => s.invoiceId == inv.id));
                  if (msg == null) return '';
                  return sv.send(msg);
                }),
                icon: const Icon(Icons.waving_hand_outlined),
                label: Text(tr('إرسال رسالة الترحيب')),
              ),
              const SizedBox(height: 8),
            ],
          ],
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => runAction(context, () => sv.shareInvoicePdf(inv)),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: Text(tr('PDF')),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => runAction(context, () => sv.printInvoice(inv)),
                icon: const Icon(Icons.print_outlined),
                label: Text(tr('طباعة')),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            if (m != null)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => showMemberCard(context, m),
                  icon: const Icon(Icons.qr_code_2),
                  label: Text(tr('بطاقة العضو')),
                ),
              ),
            if (m != null) const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.pop(context, 'invoice'),
                icon: const Icon(Icons.receipt_long_outlined),
                label: Text(tr('الفاتورة')),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('تم'))),
        ]),
      ),
    );
  }
}
