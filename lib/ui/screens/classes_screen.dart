import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/phone.dart';
import '../../core/ids.dart';
import '../../models/business.dart';
import '../../models/member.dart';
import '../../services/classes.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'members_screen.dart';

class ClassesScreen extends StatefulWidget {
  const ClassesScreen({super.key});
  @override
  State<ClassesScreen> createState() => _ClassesScreenState();
}

class _ClassesScreenState extends State<ClassesScreen> {
  late DateTime _day = context.gym.today;

  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    final sv = context.services.classes;
    final sessions = sv.sessionsOn(_day);
    final days = [for (var i = -1; i < 13; i++) addDays(g.today, i)];
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('الحصص والحجوزات')),
        actions: [
          IconButton(tooltip: tr('إدارة الحصص'), icon: const Icon(Icons.edit_calendar), onPressed: () => context.push(const ClassListScreen())),
        ],
      ),
      body: Column(children: [
        SizedBox(
          height: 76,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), children: [
            for (final d in days)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  selected: d == _day,
                  onSelected: (_) => setState(() => _day = d),
                  label: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(I18n.isAr ? weekdayNamesAr[d.weekday]! : weekdayNamesEn[d.weekday]!, style: const TextStyle(fontSize: 11)),
                    Text('${d.day}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  ]),
                ),
              ),
          ]),
        ),
        Expanded(
          child: sessions.isEmpty
              ? EmptyState(
                  icon: Icons.event_busy,
                  title: g.classes.items.isEmpty ? tr('لا توجد حصص بعد') : tr('لا حصص في هذا اليوم'),
                  action: g.classes.items.isEmpty
                      ? FilledButton.icon(onPressed: () => context.push(const ClassFormScreen()), icon: const Icon(Icons.add), label: Text(tr('إضافة حصة')))
                      : null,
                )
              : ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
                  for (final s in sessions) _SessionCard(s: s),
                ]),
        ),
      ]),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final ClassSession s;
  const _SessionCard({required this.s});

  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    final sv = context.services.classes;
    final booked = sv.booked(s);
    final wait = sv.bookingsOf(s).where((b) => b.status == BookingStatus.waitlist).length;
    final color = Color(s.cls.colorValue);
    final trainer = g.staff[s.cls.trainerId];
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showModalBottomSheet(context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => _SessionSheet(s: s)),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 6, color: color),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Column(children: [
                    Text(hhmm(minutesOfDay(s.start)), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                    Text('${s.cls.durationMin} ${tr('د')}', style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 12)),
                  ]),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s.cls.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      Text([if (trainer != null) trainer.name, if (s.cls.room != null) s.cls.room!].join(' • '), style: TextStyle(color: context.colors.onSurfaceVariant)),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(value: s.cls.capacity == 0 ? 0 : booked / s.cls.capacity, minHeight: 6, color: color, backgroundColor: context.colors.surfaceContainerHighest),
                      ),
                    ]),
                  ),
                  const SizedBox(width: 12),
                  Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('$booked/${s.cls.capacity}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    if (wait > 0) Text(tr('+{n} انتظار', {'n': wait}), style: const TextStyle(fontSize: 11, color: StatusColors.expiring)),
                  ]),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _SessionSheet extends StatelessWidget {
  final ClassSession s;
  const _SessionSheet({required this.s});

  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    final sv = context.services.classes;
    final list = sv.bookingsOf(s);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (c, scroll) => ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
        Text('${s.cls.name} • ${hhmm(minutesOfDay(s.start))}', style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        Text(dayKey(s.start)),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () async {
            final m = await context.push<Member>(const MembersScreen(pickOnly: true));
            if (m == null || !context.mounted) return;
            final b = await runAction(context, () => sv.book(s, m));
            if (b != null && context.mounted) {
              context.toast(b.status == BookingStatus.waitlist ? tr('الحصة ممتلئة — أُضيف لقائمة الانتظار') : tr('تم الحجز ✓'));
            }
          },
          icon: const Icon(Icons.person_add_alt),
          label: Text(tr('حجز لعضو')),
        ),
        const SizedBox(height: 12),
        if (list.isEmpty) Text(tr('لا حجوزات'), textAlign: TextAlign.center),
        for (final b in list)
          if (g.members[b.memberId] case final m?)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: MemberAvatar(m, radius: 18),
              title: Text(m.name),
              subtitle: Text(switch (b.status) {
                BookingStatus.booked => tr('محجوز'),
                BookingStatus.waitlist => tr('قائمة الانتظار'),
                BookingStatus.attended => tr('حضر ✓'),
                BookingStatus.noShow => tr('لم يحضر'),
                BookingStatus.cancelled => tr('ملغي'),
              }),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (b.status == BookingStatus.booked || b.status == BookingStatus.noShow)
                  IconButton(tooltip: tr('حضر'), icon: const Icon(Icons.check_circle_outline, color: StatusColors.active), onPressed: () => sv.mark(b, BookingStatus.attended)),
                if (b.status == BookingStatus.booked)
                  IconButton(tooltip: tr('لم يحضر'), icon: const Icon(Icons.person_off_outlined), onPressed: () => sv.mark(b, BookingStatus.noShow)),
                IconButton(
                  tooltip: tr('إلغاء الحجز'),
                  icon: const Icon(Icons.close),
                  onPressed: () async {
                    final p = await sv.cancel(b);
                    if (p != null && context.mounted) context.toast(tr('انتقل {n} من الانتظار إلى الحجز', {'n': g.members[p.memberId]?.name}));
                  },
                ),
              ]),
            ),
      ]),
    );
  }
}

class ClassListScreen extends StatelessWidget {
  const ClassListScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    return Scaffold(
      appBar: AppBar(title: Text(tr('إدارة الحصص'))),
      floatingActionButton: FloatingActionButton(onPressed: () => context.push(const ClassFormScreen()), child: const Icon(Icons.add)),
      body: ListView(children: [
        for (final c in g.classes.all)
          ListTile(
            leading: CircleAvatar(backgroundColor: Color(c.colorValue), child: const Icon(Icons.event, color: Colors.white)),
            title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(c.slots.map((s) => '${I18n.isAr ? weekdayNamesAr[s.weekday] : weekdayNamesEn[s.weekday]} ${hhmm(s.start)}').join('، ')),
            trailing: c.active ? null : Pill(tr('موقوفة'), StatusColors.none),
            onTap: () => context.push(ClassFormScreen(classId: c.id)),
          ),
      ]),
    );
  }
}

class ClassFormScreen extends StatefulWidget {
  final String? classId;
  const ClassFormScreen({super.key, this.classId});
  @override
  State<ClassFormScreen> createState() => _ClassFormScreenState();
}

class _ClassFormScreenState extends State<ClassFormScreen> {
  late final GymClass c = switch (context.gym.classes[widget.classId]) {
    final GymClass ex => GymClass.fromMap(ex.toMap()),
    null => GymClass(id: newId(), name: ''),
  };
  late final _name = TextEditingController(text: c.name);
  late final _cap = TextEditingController(text: '${c.capacity}');
  late final _dur = TextEditingController(text: '${c.durationMin}');
  late final _room = TextEditingController(text: c.room ?? '');

  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.classId == null ? tr('حصة جديدة') : tr('تعديل الحصة')),
        actions: [
          if (widget.classId != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (!await confirm(context, tr('حذف الحصة؟'), danger: true, ok: tr('حذف'))) return;
                await g.remove(c);
                if (context.mounted) Navigator.pop(context);
              },
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            onPressed: () async {
              final cap = parseIntInput(_cap.text);
              final dur = parseIntInput(_dur.text);
              final e = _name.text.trim().isEmpty
                  ? tr('اكتب اسم الحصة')
                  : (cap == null || cap < 1)
                      ? tr('السعة يجب أن تكون 1 أو أكثر')
                      : (dur == null || dur < 5 || dur > 600)
                          ? tr('مدة الحصة بين 5 و600 دقيقة')
                          : null;
              if (e != null) {
                context.toast(e, error: true);
                return;
              }
              c
                ..name = _name.text.trim()
                ..capacity = cap!
                ..durationMin = dur!
                ..room = _room.text.trim().isEmpty ? null : _room.text.trim();
              await g.put(c);
              if (context.mounted) Navigator.pop(context);
            },
            child: Text(tr('حفظ')),
          ),
        ),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: _name, decoration: InputDecoration(labelText: tr('اسم الحصة'))),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(controller: _cap, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('السعة')))),
          const SizedBox(width: 10),
          Expanded(child: TextField(controller: _dur, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('المدة (دقيقة)')))),
        ]),
        const SizedBox(height: 12),
        TextField(controller: _room, decoration: InputDecoration(labelText: tr('القاعة'))),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          initialValue: c.trainerId,
          decoration: InputDecoration(labelText: tr('المدرب')),
          items: [DropdownMenuItem(value: null, child: Text(tr('بدون'))), for (final t in g.trainers) DropdownMenuItem(value: t.id, child: Text(t.name))],
          onChanged: (v) => c.trainerId = v,
        ),
        const SizedBox(height: 12),
        SegmentedButton<Gender?>(
          segments: [ButtonSegment(value: null, label: Text(tr('الجميع'))), ButtonSegment(value: Gender.male, label: Text(tr('رجال'))), ButtonSegment(value: Gender.female, label: Text(tr('سيدات')))],
          selected: {c.gender},
          onSelectionChanged: (v) => setState(() => c.gender = v.first),
        ),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(tr('للمشتركين فقط')), value: c.membersOnly, onChanged: (v) => setState(() => c.membersOnly = v)),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(tr('فعّالة')), value: c.active, onChanged: (v) => setState(() => c.active = v)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Text(tr('المواعيد الأسبوعية'), style: context.text.titleMedium)),
          TextButton.icon(
            onPressed: () async {
              final day = await pickFromSheet<int>(context, tr('اليوم'), [for (final d in weekOrder) (d, I18n.isAr ? weekdayNamesAr[d]! : weekdayNamesEn[d]!, null)]);
              if (day == null || !context.mounted) return;
              final t = await pickTime(context, 18 * 60);
              if (t == null) return;
              setState(() => c.slots.add(ClassSlot(day, t.hour * 60 + t.minute)));
            },
            icon: const Icon(Icons.add),
            label: Text(tr('موعد')),
          ),
        ]),
        for (final s in c.slots)
          ListTile(
            leading: const Icon(Icons.schedule),
            title: Text('${I18n.isAr ? weekdayNamesAr[s.weekday] : weekdayNamesEn[s.weekday]} ${hhmm(s.start)}'),
            trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => c.slots.remove(s))),
          ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          for (final col in [0xFFEF6C00, 0xFFD81B60, 0xFF1E88E5, 0xFF43A047, 0xFF8E24AA, 0xFF00ACC1])
            GestureDetector(
              onTap: () => setState(() => c.colorValue = col),
              child: CircleAvatar(radius: 15, backgroundColor: Color(col), child: c.colorValue == col ? const Icon(Icons.check, color: Colors.white, size: 16) : null),
            ),
        ]),
      ]),
    );
  }
}
