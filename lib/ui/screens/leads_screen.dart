import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/ids.dart';
import '../../models/business.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'member_form_screen.dart';

String leadStatusName(LeadStatus s) => switch (s) {
      LeadStatus.fresh => tr('جديد'),
      LeadStatus.contacted => tr('تم التواصل'),
      LeadStatus.trial => tr('حصة تجربة'),
      LeadStatus.won => tr('اشترك'),
      LeadStatus.lost => tr('لم يشترك'),
    };

Color leadStatusColor(LeadStatus s) => switch (s) {
      LeadStatus.fresh => const Color(0xFF6366F1),
      LeadStatus.contacted => StatusColors.frozen,
      LeadStatus.trial => StatusColors.expiring,
      LeadStatus.won => StatusColors.active,
      LeadStatus.lost => StatusColors.none,
    };

/// العملاء المحتملون: من سأل عن الأسعار أو جرّب حصة، مع متابعة حتى الاشتراك
class LeadsScreen extends StatefulWidget {
  const LeadsScreen({super.key});
  @override
  State<LeadsScreen> createState() => _LeadsScreenState();
}

class _LeadsScreenState extends State<LeadsScreen> {
  LeadStatus? _filter;

  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    final all = g.leads.all.toList();
    final list = all.where((l) => _filter == null ? l.status != LeadStatus.won && l.status != LeadStatus.lost : l.status == _filter).toList()
      ..sort((a, b) => (a.followUp ?? DateTime(2100)).compareTo(b.followUp ?? DateTime(2100)));
    final won = all.where((l) => l.status == LeadStatus.won).length;
    final closed = won + all.where((l) => l.status == LeadStatus.lost).length;
    return Scaffold(
      appBar: AppBar(title: Text(tr('العملاء المحتملون'))),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _edit(context, null), icon: const Icon(Icons.add), label: Text(tr('عميل محتمل'))),
      body: Column(children: [
        if (closed > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(tr('نسبة التحويل: {p}% ({w} من {c})', {'p': (won * 100 / closed).round(), 'w': won, 'c': closed}), style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        SizedBox(
          height: 48,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), children: [
            Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: ChoiceChip(label: Text(tr('قيد المتابعة')), selected: _filter == null, onSelected: (_) => setState(() => _filter = null))),
            for (final s in LeadStatus.values)
              Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: ChoiceChip(label: Text(leadStatusName(s)), selected: _filter == s, onSelected: (_) => setState(() => _filter = s))),
          ]),
        ),
        Expanded(
          child: list.isEmpty
              ? EmptyState(icon: Icons.person_search, title: tr('لا يوجد'), message: tr('سجّل كل من يسأل عن الأسعار وتابعه بالواتساب حتى يشترك'))
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(indent: 16),
                  itemBuilder: (c, i) {
                    final l = list[i];
                    final due = l.followUp != null && !l.followUp!.isAfter(g.today);
                    return ListTile(
                      title: Text(l.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text([
                        l.phone,
                        if (l.source != null) tr(l.source!),
                        if (g.plans[l.interestPlanId] != null) g.plans[l.interestPlanId]!.name,
                        if (l.followUp != null) '${tr('متابعة')} ${relativeDays(daysBetween(g.today, l.followUp!))}',
                        if (l.notes != null) l.notes!,
                      ].join(' • '), maxLines: 2),
                      leading: CircleAvatar(backgroundColor: leadStatusColor(l.status).withValues(alpha: 0.15), child: Icon(due ? Icons.notifications_active : Icons.person_outline, color: due ? StatusColors.expired : leadStatusColor(l.status))),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(icon: const Icon(Icons.chat, color: Color(0xFF25D366)), onPressed: () => context.services.openWhatsApp(l.phone, tr('مرحباً {n} 👋 معك {g}', {'n': l.name.split(' ').first, 'g': g.settings.gymName}))),
                        IconButton(icon: const Icon(Icons.call_outlined), onPressed: () => context.services.call(l.phone)),
                      ]),
                      onTap: () => _edit(context, l),
                    );
                  },
                ),
        ),
      ]),
    );
  }

  Future<void> _edit(BuildContext context, Lead? l0) async {
    final g = context.gym;
    final l = l0 ?? Lead(id: newId(), name: '', phone: '', createdAt: g.now(), followUp: addDays(g.today, 1));
    final name = TextEditingController(text: l.name);
    final phone = TextEditingController(text: l.phone);
    final notes = TextEditingController(text: l.notes ?? '');
    final r = await showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(l0 == null ? tr('عميل محتمل') : l.name),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: name, decoration: InputDecoration(labelText: tr('الاسم'))),
                const SizedBox(height: 8),
                TextField(controller: phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: tr('الجوال'))),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  initialValue: l.interestPlanId,
                  decoration: InputDecoration(labelText: tr('مهتم بباقة')),
                  items: [DropdownMenuItem(value: null, child: Text(tr('غير محدد'))), for (final p in g.activePlans) DropdownMenuItem(value: p.id, child: Text(p.name))],
                  onChanged: (v) => l.interestPlanId = v,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  initialValue: leadSources.contains(l.source) ? l.source : null,
                  decoration: InputDecoration(labelText: tr('المصدر')),
                  items: [for (final s in leadSources) DropdownMenuItem(value: s, child: Text(tr(s)))],
                  onChanged: (v) => l.source = v,
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final s in LeadStatus.values) ChoiceChip(label: Text(leadStatusName(s)), selected: l.status == s, onSelected: (_) => set(() => l.status = s)),
                ]),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('موعد المتابعة')),
                  trailing: Text(l.followUp == null ? '—' : dayKey(l.followUp!)),
                  onTap: () async {
                    final d = await pickDay(c, l.followUp ?? g.today);
                    set(() => l.followUp = d);
                  },
                ),
                TextField(controller: notes, maxLines: 2, decoration: InputDecoration(labelText: tr('ملاحظات'))),
              ]),
            ),
          ),
          actions: [
            if (l0 != null && l.memberId == null) TextButton(onPressed: () => Navigator.pop(c, 'convert'), child: Text(tr('تحويل لعضو'))),
            if (l0 != null) TextButton(onPressed: () => Navigator.pop(c, 'delete'), child: Text(tr('حذف'))),
            FilledButton(onPressed: () => Navigator.pop(c, 'save'), child: Text(tr('حفظ'))),
          ],
        ),
      ),
    );
    if (r == null || !context.mounted) return;
    if (r == 'delete') {
      await g.remove(l);
      return;
    }
    if (name.text.trim().isEmpty) return;
    l
      ..name = name.text.trim()
      ..phone = phone.text.trim()
      ..notes = notes.text.trim().isEmpty ? null : notes.text.trim();
    if (r == 'convert') l.status = LeadStatus.won;
    await g.put(l);
    if (r == 'convert' && context.mounted) {
      await context.push(MemberFormScreen(presetName: l.name, presetPhone: l.phone, presetGender: l.gender));
      final m = context.mounted ? context.services.members.findByPhone(l.phone) : null;
      if (m != null) {
        l.memberId = m.id;
        await g.put(l);
      }
    }
  }
}

