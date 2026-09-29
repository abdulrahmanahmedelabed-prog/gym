import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/ids.dart';
import '../../core/money.dart';
import '../../models/business.dart';
import '../../models/member.dart';
import '../../models/plan.dart';
import '../../services/license.dart';
import '../widgets/upgrade.dart';
import '../widgets/common.dart';
import 'offers_screen.dart';
import 'sale_screen.dart';

const planColors = [0xFF1E88E5, 0xFF43A047, 0xFFFB8C00, 0xFFE53935, 0xFF8E24AA, 0xFF00ACC1, 0xFF6D4C41, 0xFF757575, 0xFFD81B60, 0xFF3949AB];

class PlansScreen extends StatelessWidget {
  const PlansScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    final plans = g.plans.all.toList()..sort((a, b) => a.active == b.active ? a.sort.compareTo(b.sort) : (a.active ? -1 : 1));
    final canEdit = g.can(Perm.plans);
    final sold = <String, int>{};
    for (final s in g.subs.all) {
      sold[s.planId] = (sold[s.planId] ?? 0) + 1;
    }
    return Scaffold(
      appBar: AppBar(title: Text(tr('الباقات والأسعار')), actions: [
        TextButton.icon(
          onPressed: () async {
            if (await ensureFeature(context, Feature.offers) && context.mounted) context.push(const OffersScreen());
          },
          icon: const Icon(Icons.local_fire_department_outlined),
          label: Text(tr('العروض')),
        ),
      ]),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(onPressed: () => context.push(const PlanFormScreen()), icon: const Icon(Icons.add), label: Text(tr('باقة')))
          : null,
      body: plans.isEmpty
          ? EmptyState(icon: Icons.card_membership, title: tr('لا توجد باقات'))
          : ListView.separated(
              padding: const EdgeInsets.only(bottom: 88, top: 8),
              itemCount: plans.length,
              separatorBuilder: (_, _) => const Divider(indent: 72),
              itemBuilder: (c, i) {
                final p = plans[i];
                return Opacity(
                  opacity: p.active ? 1 : 0.5,
                  child: ListTile(
                    leading: CircleAvatar(backgroundColor: Color(p.colorValue).withValues(alpha: 0.15), child: Icon(p.kind == PlanKind.pt ? Icons.sports : (p.kind == PlanKind.visits ? Icons.confirmation_number_outlined : Icons.card_membership), color: Color(p.colorValue))),
                    title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${planSummary(p)}${p.active ? '' : ' • ${tr('موقوفة')}'}\n${tr('بيعت {n} مرة', {'n': sold[p.id] ?? 0})}'),
                    isThreeLine: true,
                    trailing: Text(fmtMoney(p.price), style: const TextStyle(fontWeight: FontWeight.w800)),
                    onTap: canEdit ? () => context.push(PlanFormScreen(planId: p.id)) : null,
                  ),
                );
              },
            ),
    );
  }
}

class PlanFormScreen extends StatefulWidget {
  final String? planId;
  const PlanFormScreen({super.key, this.planId});
  @override
  State<PlanFormScreen> createState() => _PlanFormScreenState();
}

class _PlanFormScreenState extends State<PlanFormScreen> {
  late final Plan p;
  late final bool isNew;
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _fee = TextEditingController();
  final _dur = TextEditingController();
  final _visits = TextEditingController();
  final _freezeDays = TextEditingController();
  final _freezeTimes = TextEditingController();
  final _desc = TextEditingController();

  @override
  void initState() {
    super.initState();
    final g = context.gym;
    final ex = g.plans[widget.planId];
    isNew = ex == null;
    p = ex ?? Plan(id: newId(), name: '', sort: g.plans.items.length + 1, colorValue: planColors[g.plans.items.length % planColors.length]);
    _name.text = p.name;
    _price.text = p.price == 0 ? '' : fmtNum(p.price);
    _fee.text = p.registrationFee == 0 ? '' : fmtNum(p.registrationFee);
    _dur.text = '${p.durationValue}';
    _visits.text = p.visits?.toString() ?? '';
    _freezeDays.text = '${p.freezeDays}';
    _freezeTimes.text = '${p.freezeTimes}';
    _desc.text = p.description ?? '';
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      context.toast(tr('اكتب اسم الباقة'), error: true);
      return;
    }
    final g = context.gym;
    final oldPrice = p.price;
    p
      ..name = _name.text.trim()
      ..price = parseAmount(_price.text) ?? 0
      ..registrationFee = parseAmount(_fee.text) ?? 0
      ..durationValue = int.tryParse(_dur.text) ?? 1
      ..visits = int.tryParse(_visits.text)
      ..freezeDays = int.tryParse(_freezeDays.text) ?? 0
      ..freezeTimes = int.tryParse(_freezeTimes.text) ?? 0
      ..description = _desc.text.trim().isEmpty ? null : _desc.text.trim();
    if (p.kind == PlanKind.visits && p.visits == null) p.visits = 12;
    if (p.kind == PlanKind.pt && p.visits == null) p.visits = 8;
    await g.putAll([
      p,
      if (!isNew && oldPrice != p.price) g.auditEntry('price', '${p.name}: ${fmtMoney(oldPrice)} – ${fmtMoney(p.price)}'),
    ]);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isNew ? tr('باقة جديدة') : tr('تعديل الباقة'))),
      bottomNavigationBar: SafeArea(child: Padding(padding: const EdgeInsets.all(12), child: FilledButton(onPressed: _save, child: Text(tr('حفظ'))))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: _name, decoration: InputDecoration(labelText: tr('اسم الباقة'))),
        const SizedBox(height: 12),
        SegmentedButton<PlanKind>(
          segments: [
            ButtonSegment(value: PlanKind.time, label: Text(tr('مدة')), icon: const Icon(Icons.date_range)),
            ButtonSegment(value: PlanKind.visits, label: Text(tr('حصص')), icon: const Icon(Icons.confirmation_number_outlined)),
            ButtonSegment(value: PlanKind.pt, label: Text(tr('تدريب شخصي')), icon: const Icon(Icons.sports)),
          ],
          selected: {p.kind},
          onSelectionChanged: (v) async {
            if (v.first == PlanKind.pt && !await ensureFeature(context, Feature.personalTraining)) return;
            setState(() => p.kind = v.first);
          },
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(controller: _price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: tr('السعر')))),
          const SizedBox(width: 10),
          Expanded(child: TextField(controller: _fee, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: tr('رسوم تسجيل (للجدد)')))),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(controller: _dur, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: p.kind == PlanKind.time ? tr('المدة') : tr('الصلاحية')))),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonFormField<DurationUnit>(
              initialValue: p.durationUnit,
              items: [
                DropdownMenuItem(value: DurationUnit.day, child: Text(tr('يوم'))),
                DropdownMenuItem(value: DurationUnit.week, child: Text(tr('أسبوع'))),
                DropdownMenuItem(value: DurationUnit.month, child: Text(tr('شهر'))),
                DropdownMenuItem(value: DurationUnit.year, child: Text(tr('سنة'))),
              ],
              onChanged: (v) => setState(() => p.durationUnit = v!),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _visits,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: p.kind == PlanKind.time ? tr('حد أقصى للزيارات (اتركه فارغاً = غير محدود)') : tr('عدد الحصص/الجلسات'),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(controller: _freezeDays, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('أيام التجميد المسموحة')))),
          const SizedBox(width: 10),
          Expanded(child: TextField(controller: _freezeTimes, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('مرات التجميد')))),
        ]),
        const SizedBox(height: 16),
        Text(tr('قيود الدخول'), style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        SegmentedButton<Gender?>(
          segments: [
            ButtonSegment(value: null, label: Text(tr('الجميع'))),
            ButtonSegment(value: Gender.male, label: Text(tr('رجال'))),
            ButtonSegment(value: Gender.female, label: Text(tr('سيدات'))),
          ],
          selected: {p.gender},
          onSelectionChanged: (v) => setState(() => p.gender = v.first),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tr('ساعات محددة (باقة صباحية/اقتصادية)')),
          subtitle: p.hasTimeWindow ? Text(hhmmRange(p.accessFrom!, p.accessTo!)) : null,
          value: p.hasTimeWindow,
          onChanged: (v) => setState(() {
            p.accessFrom = v ? 6 * 60 : null;
            p.accessTo = v ? 14 * 60 : null;
          }),
        ),
        if (p.hasTimeWindow)
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () async {
                  final t = await pickTime(context, p.accessFrom!);
                  if (t != null) setState(() => p.accessFrom = t.hour * 60 + t.minute);
                },
                child: Text('${tr('من')} ${hhmm(p.accessFrom!)}'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: () async {
                  final t = await pickTime(context, p.accessTo!);
                  if (t != null) setState(() => p.accessTo = t.hour * 60 + t.minute);
                },
                child: Text('${tr('إلى')} ${hhmm(p.accessTo!)}'),
              ),
            ),
          ]),
        const SizedBox(height: 8),
        Text(tr('أيام الدخول (بدون اختيار = كل الأيام)')),
        const SizedBox(height: 6),
        Wrap(spacing: 6, children: [
          for (final d in weekOrder)
            FilterChip(
              label: Text(I18n.isAr ? weekdayNamesAr[d]! : weekdayNamesEn[d]!),
              selected: p.weekdays.contains(d),
              onSelected: (v) => setState(() => v ? p.weekdays.add(d) : p.weekdays.remove(d)),
            ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Text(tr('مرات الدخول في اليوم'))),
          IconButton(onPressed: p.dailyLimit > 0 ? () => setState(() => p.dailyLimit--) : null, icon: const Icon(Icons.remove_circle_outline)),
          Text(p.dailyLimit == 0 ? tr('بلا حد') : '${p.dailyLimit}'),
          IconButton(onPressed: () => setState(() => p.dailyLimit++), icon: const Icon(Icons.add_circle_outline)),
        ]),
        const SizedBox(height: 8),
        Text(tr('اللون')),
        const SizedBox(height: 6),
        Wrap(spacing: 8, children: [
          for (final c in planColors)
            GestureDetector(
              onTap: () => setState(() => p.colorValue = c),
              child: CircleAvatar(radius: 16, backgroundColor: Color(c), child: p.colorValue == c ? const Icon(Icons.check, color: Colors.white, size: 18) : null),
            ),
        ]),
        const SizedBox(height: 12),
        TextField(controller: _desc, decoration: InputDecoration(labelText: tr('وصف (اختياري)'))),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(tr('الباقة متاحة للبيع')), value: p.active, onChanged: (v) => setState(() => p.active = v)),
        const SizedBox(height: 24),
      ]),
    );
  }
}
