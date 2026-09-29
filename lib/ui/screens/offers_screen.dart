import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/phone.dart';
import '../../core/ids.dart';
import '../../core/money.dart';
import '../../models/business.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'settings_screen.dart';

String offerSummary(Offer o) => [
      switch (o.type) {
        'percent' => tr('خصم {v}%', {'v': fmtNum(o.value)}),
        'fixed' => tr('خصم {v}', {'v': fmtMoney(o.value)}),
        'price' => tr('بسعر {v}', {'v': fmtMoney(o.value)}),
        _ => '',
      },
      if (o.bonusDays > 0) tr('+{n} يوم مجاناً', {'n': o.bonusDays}),
      if (o.newMembersOnly) tr('للأعضاء الجدد'),
      if (o.start != null || o.end != null) '${o.start == null ? '' : dayKey(o.start!)} – ${o.end == null ? tr('مفتوح') : dayKey(o.end!)}',
    ].where((x) => x.isNotEmpty).join(' • ');

/// العروض: تُطبق تلقائياً على الباقات خلال مدتها (عروض رمضان، الصيف، الافتتاح، الطلاب...)
class OffersScreen extends StatelessWidget {
  const OffersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    final list = g.offers.all.toList()..sort((a, b) => (b.active ? 1 : 0).compareTo(a.active ? 1 : 0));
    final today = g.today;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('العروض')),
        actions: [
          TextButton.icon(onPressed: () => context.push(const CouponsScreen()), icon: const Icon(Icons.local_offer_outlined), label: Text(tr('الكوبونات'))),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => editOffer(context, null), icon: const Icon(Icons.add), label: Text(tr('عرض'))),
      body: list.isEmpty
          ? EmptyState(
              icon: Icons.local_fire_department_outlined,
              title: tr('لا توجد عروض'),
              message: tr('مثال: «عرض الصيف» خصم 20% على 3 و6 أشهر حتى نهاية أغسطس، أو «3 أشهر + 15 يوماً هدية». يظهر العرض تلقائياً للموظف عند البيع والتجديد.'),
            )
          : ListView(padding: const EdgeInsets.only(bottom: 88), children: [
              for (final o in list)
                ListTile(
                  leading: Icon(Icons.local_fire_department,
                      color: o.active && (o.end == null || !o.end!.isBefore(today)) ? const Color(0xFFEA580C) : StatusColors.none),
                  title: Text(o.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text([
                    offerSummary(o),
                    o.planIds.isEmpty ? tr('كل الباقات') : o.planIds.map((id) => g.plans[id]?.name ?? '').join('، '),
                  ].join('\n')),
                  isThreeLine: true,
                  trailing: Switch(
                    value: o.active,
                    onChanged: (v) {
                      o.active = v;
                      g.put(o);
                    },
                  ),
                  onTap: () => editOffer(context, o),
                ),
            ]),
    );
  }
}

Future<void> editOffer(BuildContext context, Offer? o0) async {
  final g = context.gym;
  // نعدّل نسخة: الإلغاء لا يغيّر العرض الأصلي
  final o = o0 == null ? Offer(id: newId(), name: '', start: g.today, end: addDays(g.today, 30), value: 10) : Offer.fromMap(o0.toMap());
  String? err;
  final name = TextEditingController(text: o.name);
  final value = TextEditingController(text: o.value == 0 ? '' : fmtNum(o.value));
  final bonus = TextEditingController(text: o.bonusDays == 0 ? '' : '${o.bonusDays}');
  final ok = await showDialog<String>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: Text(o0 == null ? tr('عرض جديد') : tr('تعديل العرض')),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(controller: name, decoration: InputDecoration(labelText: tr('اسم العرض'), hintText: tr('عرض رمضان'))),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 'percent', label: Text(tr('خصم %'))),
                  ButtonSegment(value: 'fixed', label: Text(tr('خصم مبلغ'))),
                  ButtonSegment(value: 'price', label: Text(tr('سعر خاص'))),
                ],
                selected: {o.type},
                onSelectionChanged: (v) => set(() => o.type = v.first),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: value,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: o.type == 'percent' ? tr('النسبة %') : (o.type == 'price' ? tr('السعر الخاص') : tr('المبلغ'))),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(controller: bonus, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('أيام مجانية إضافية'))),
                ),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final d = await pickDay(c, o.start ?? g.today);
                      if (d != null) set(() => o.start = d);
                    },
                    child: Text('${tr('من')} ${o.start == null ? '—' : dayKey(o.start!)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final d = await pickDay(c, o.end ?? addDays(g.today, 30), first: o.start);
                      if (d != null) set(() => o.end = d);
                    },
                    child: Text('${tr('إلى')} ${o.end == null ? tr('مفتوح') : dayKey(o.end!)}'),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              Text(tr('الباقات المشمولة (بدون اختيار = كل الباقات)')),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final p in g.activePlans)
                  FilterChip(
                    label: Text(p.name),
                    selected: o.planIds.contains(p.id),
                    onSelected: (v) => set(() => v ? o.planIds.add(p.id) : o.planIds.remove(p.id)),
                  ),
              ]),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('للأعضاء الجدد فقط')),
                value: o.newMembersOnly,
                onChanged: (v) => set(() => o.newMembersOnly = v),
              ),
              if (err != null) Text(err!, style: TextStyle(color: Theme.of(c).colorScheme.error, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
        actions: [
          if (o0 != null) TextButton(onPressed: () => Navigator.pop(c, 'delete'), child: Text(tr('حذف'))),
          TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('إلغاء'))),
          FilledButton(
            onPressed: () {
              final v = parseAmount(value.text) ?? 0;
              final b = parseIntInput(bonus.text) ?? 0;
              final e = name.text.trim().isEmpty
                  ? tr('اكتب اسم العرض')
                  : (v < 0 || b < 0)
                      ? tr('القيم لا تكون سالبة')
                      : (o.type == 'percent' && v > 100)
                          ? tr('النسبة لا تزيد عن 100%')
                          : (o.type == 'price' && v <= 0)
                              ? tr('اكتب السعر الخاص')
                              : (v == 0 && b == 0)
                                  ? tr('حدّد خصماً أو أياماً مجانية')
                                  : (o.start != null && o.end != null && o.end!.isBefore(o.start!))
                                      ? tr('تاريخ النهاية قبل البداية')
                                      : null;
              if (e != null) {
                set(() => err = e);
                return;
              }
              Navigator.pop(c, 'save');
            },
            child: Text(tr('حفظ')),
          ),
        ],
      ),
    ),
  );
  if (ok == 'delete') {
    await g.remove(o0!);
    return;
  }
  if (ok != 'save') return;
  o
    ..name = name.text.trim()
    ..value = parseAmount(value.text) ?? 0
    ..bonusDays = parseIntInput(bonus.text) ?? 0;
  await g.putAll([o, g.auditEntry('offer', '${o.name}: ${offerSummary(o)}')]);
}
