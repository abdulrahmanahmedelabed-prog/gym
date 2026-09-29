import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/money.dart';
import '../../models/member.dart';
import '../../models/subscription.dart';
import '../../services/membership.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'member_detail_screen.dart';
import 'member_form_screen.dart';
import 'sale_screen.dart';

enum MemberFilter { all, active, expiring, expired, frozen, debt, none, archived }

String memberFilterName(MemberFilter f) => switch (f) {
      MemberFilter.all => tr('الكل'),
      MemberFilter.active => tr('فعّال'),
      MemberFilter.expiring => tr('ينتهي قريباً'),
      MemberFilter.expired => tr('منتهي'),
      MemberFilter.frozen => tr('مجمّد'),
      MemberFilter.debt => tr('عليه دين'),
      MemberFilter.none => tr('بدون اشتراك'),
      MemberFilter.archived => tr('مؤرشف'),
    };

enum MemberSort { name, recent, endDate, code }

class MembersScreen extends StatefulWidget {
  final MemberFilter initialFilter;
  final bool standalone;
  final bool pickForRenew;
  final bool pickOnly; // لاختيار عضو وإرجاعه
  const MembersScreen({super.key, this.initialFilter = MemberFilter.all, this.standalone = false, this.pickForRenew = false, this.pickOnly = false});

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  final _q = TextEditingController();
  late MemberFilter _filter = widget.initialFilter;
  MemberSort _sort = MemberSort.recent;
  Gender? _gender;

  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    final ms = context.services.members;
    final today = g.today;
    final rows = <({Member m, MemberState st, Subscription? sub, double bal})>[];
    for (final m in ms.search(_q.text, includeArchived: _filter == MemberFilter.archived)) {
      if (_filter == MemberFilter.archived && !m.archived) continue;
      if (_gender != null && m.gender != _gender) continue;
      final st = ms.stateOf(m.id, today);
      final bal = g.balanceOf(m.id);
      final ok = switch (_filter) {
        MemberFilter.all || MemberFilter.archived => true,
        MemberFilter.active => st == MemberState.active || st == MemberState.expiring,
        MemberFilter.expiring => st == MemberState.expiring,
        MemberFilter.expired => st == MemberState.expired,
        MemberFilter.frozen => st == MemberState.frozen,
        MemberFilter.debt => bal > 0.001,
        MemberFilter.none => st == MemberState.none,
      };
      if (ok) rows.add((m: m, st: st, sub: ms.currentSub(m.id, today), bal: bal));
    }
    rows.sort((a, b) => switch (_sort) {
          MemberSort.name => a.m.name.compareTo(b.m.name),
          MemberSort.recent => b.m.createdAt.compareTo(a.m.createdAt),
          MemberSort.code => a.m.code.compareTo(b.m.code),
          MemberSort.endDate => (a.sub?.end ?? DateTime(1900)).compareTo(b.sub?.end ?? DateTime(1900)),
        });
    if (_filter == MemberFilter.debt) rows.sort((a, b) => b.bal.compareTo(a.bal));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pickForRenew
            ? tr('اختر العضو للتجديد')
            : widget.pickOnly
                ? tr('اختر عضواً')
                : tr('الأعضاء ({n})', {'n': rows.length})),
        automaticallyImplyLeading: widget.standalone || widget.pickOnly || widget.pickForRenew,
        actions: [
          PopupMenuButton<Object>(
            icon: const Icon(Icons.sort),
            tooltip: tr('الترتيب والتصفية'),
            onSelected: (v) => setState(() {
              if (v is MemberSort) _sort = v;
              if (v == 'm') _gender = _gender == Gender.male ? null : Gender.male;
              if (v == 'f') _gender = _gender == Gender.female ? null : Gender.female;
            }),
            itemBuilder: (_) => [
              CheckedPopupMenuItem(value: MemberSort.recent, checked: _sort == MemberSort.recent, child: Text(tr('الأحدث'))),
              CheckedPopupMenuItem(value: MemberSort.name, checked: _sort == MemberSort.name, child: Text(tr('الاسم'))),
              CheckedPopupMenuItem(value: MemberSort.endDate, checked: _sort == MemberSort.endDate, child: Text(tr('تاريخ الانتهاء'))),
              CheckedPopupMenuItem(value: MemberSort.code, checked: _sort == MemberSort.code, child: Text(tr('رقم العضوية'))),
              const PopupMenuDivider(),
              CheckedPopupMenuItem(value: 'm', checked: _gender == Gender.male, child: Text(tr('الرجال فقط'))),
              CheckedPopupMenuItem(value: 'f', checked: _gender == Gender.female, child: Text(tr('السيدات فقط'))),
            ],
          ),
        ],
      ),
      floatingActionButton: widget.pickOnly || widget.pickForRenew
          ? null
          : FloatingActionButton(
              heroTag: 'addMember',
              tooltip: tr('عضو جديد'),
              onPressed: () => context.push(const MemberFormScreen()),
              child: const Icon(Icons.person_add_alt_1),
            ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: SearchField(
            controller: _q,
            hint: tr('ابحث بالاسم أو الجوال أو رقم العضوية'),
            onChanged: (_) => setState(() {}),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final f in MemberFilter.values)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(memberFilterName(f)),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: rows.isEmpty
              ? EmptyState(
                  icon: Icons.person_search,
                  title: g.members.items.isEmpty ? tr('لا يوجد أعضاء بعد') : tr('لا نتائج'),
                  message: g.members.items.isEmpty ? tr('أضف أول عضو أو استورد قائمتك من Excel من الإعدادات') : null,
                  action: g.members.items.isEmpty
                      ? FilledButton.icon(
                          onPressed: () => context.push(const MemberFormScreen()), icon: const Icon(Icons.add), label: Text(tr('عضو جديد')))
                      : null,
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(indent: 72),
                  itemBuilder: (c, i) {
                    final r = rows[i];
                    return _MemberTile(
                      m: r.m,
                      st: r.st,
                      sub: r.sub,
                      bal: r.bal,
                      onTap: () {
                        if (widget.pickOnly) {
                          Navigator.pop(context, r.m);
                        } else if (widget.pickForRenew) {
                          context.push(SaleScreen(memberId: r.m.id));
                        } else {
                          context.push(MemberDetailScreen(memberId: r.m.id));
                        }
                      },
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

class _MemberTile extends StatelessWidget {
  final Member m;
  final MemberState st;
  final Subscription? sub;
  final double bal;
  final VoidCallback onTap;
  const _MemberTile({required this.m, required this.st, required this.sub, required this.bal, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final today = context.gym.today;
    final style = memberStateStyle(st);
    String? line;
    final s = sub;
    if (s != null) {
      final left = s.visitsLeft;
      line = switch (st) {
        MemberState.active || MemberState.expiring =>
          '${s.planName} • ${left != null ? tr('{n} حصة', {'n': left}) : relativeDays(s.daysLeft(today))}',
        MemberState.expired => '${s.planName} • ${tr('انتهى')} ${fmtDay(s.end)}',
        MemberState.frozen => '${s.planName} • ${tr('مجمّد')}',
        MemberState.pending => '${s.planName} • ${tr('يبدأ')} ${fmtDay(s.start)}',
        MemberState.none => null,
      };
    }
    return ListTile(
      onTap: onTap,
      leading: MemberAvatar(m, ring: style.color),
      title: Row(children: [
        Flexible(child: Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
        const SizedBox(width: 6),
        Flexible(child: Text('#${m.code}', maxLines: 1, overflow: TextOverflow.clip, softWrap: false, style: TextStyle(fontSize: 12, color: context.colors.outline))),
      ]),
      subtitle: Text(line ?? m.phone, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
        StatePill(st),
        if (bal > 0.001) ...[
          const SizedBox(height: 4),
          Text(fmtMoney(bal), style: const TextStyle(color: StatusColors.expired, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ]),
    );
  }
}
