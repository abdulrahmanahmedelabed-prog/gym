import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/money.dart';
import '../../models/activity.dart';
import '../../models/business.dart';
import '../../services/membership.dart';
import '../../services/reports.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../../services/license.dart';
import '../widgets/upgrade.dart';
import '../widgets/common.dart';
import 'leads_screen.dart';
import 'lock_screen.dart';
import 'member_detail_screen.dart';
import 'member_form_screen.dart';
import 'members_screen.dart';
import 'messages_screen.dart';
import 'reports_screen.dart';
import 'shell.dart';
import 'shop_screen.dart';
import 'sync_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    final sv = context.services;
    final rep = sv.reports;
    final now = g.now();
    final today = Range.today(now);
    final month = Range.thisMonth(now);
    final states = rep.memberStates();
    final active = states[MemberState.active]! + states[MemberState.expiring]!;
    final inGym = sv.checkin.inGymNow().length;
    final visitsToday = sv.checkin.today().where((c) => c.allowed).length;
    final expiring = rep.expiringSoon();
    final debtors = sv.billing.debtors();
    final debtTotal = debtors.fold(0.0, (s, x) => s + x.balance);
    final overdueInst = sv.billing.dueInstallments(until: g.today);
    final pending = sv.pendingManual;
    final birthdays = g.members.all.where((m) => !m.archived && m.isBirthday(g.today)).toList();
    final followUps = g.leads.all
        .where((l) => l.followUp != null && !l.followUp!.isAfter(g.today) && l.status != LeadStatus.won && l.status != LeadStatus.lost)
        .toList();
    final lowStock = g.products.all.where((p) => p.active && p.lowStock).toList();
    final canMoney = g.can(Perm.reports);
    final series = rep.dailyCollections(Range.lastDays(now, 14));

    final hour = now.hour;
    final greet = hour < 12 ? tr('صباح الخير') : tr('مساء الخير');

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(g.settings.gymName, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          Text('$greet${g.user != null ? '، ${g.user!.name}' : ''} • ${dayKey(now)}',
              style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
        ]),
        toolbarHeight: 64,
        actions: [
          const SyncStatusButton(),
          IconButton(
            tooltip: tr('الرسائل'),
            onPressed: () => context.push(const MessagesScreen()),
            icon: Badge(isLabelVisible: pending > 0, label: Text('$pending'), child: const Icon(Icons.chat_outlined)),
          ),
          if (g.user != null)
            IconButton(
              tooltip: tr('تبديل المستخدم'),
              onPressed: () {
                g.user = null;
                g.touch();
              },
              icon: const Icon(Icons.logout),
            ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(const MemberFormScreen()),
        icon: const Icon(Icons.person_add_alt_1),
        label: Text(tr('عضو جديد')),
      ),
      body: RefreshIndicator(
        onRefresh: () => sv.tick(),
        child: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: ResponsiveGrid(minWidth: 160, children: [
              Kpi(
                label: tr('أعضاء فعّالون'),
                value: '$active',
                icon: Icons.groups,
                color: StatusColors.active,
                sub: tr('{n} ينتهي قريباً', {'n': states[MemberState.expiring]}),
                onTap: () => context.push(const MembersScreen(initialFilter: MemberFilter.active, standalone: true)),
              ),
              Kpi(
                label: tr('في النادي الآن'),
                value: '$inGym',
                icon: Icons.directions_run,
                color: const Color(0xFF0EA5E9),
                sub: tr('{n} زيارة اليوم', {'n': visitsToday}),
                onTap: () => Shell.goTo(context, 2),
              ),
              if (canMoney)
                Kpi(
                  label: tr('تحصيل اليوم'),
                  value: fmtMoney(rep.collected(today)),
                  icon: Icons.payments_outlined,
                  color: brandSeed,
                  sub: '${tr('الشهر')}: ${fmtMoney(rep.collected(month))}',
                  onTap: () async {
                    if (await ensureFeature(context, Feature.fullReports) && context.mounted) context.push(const ReportsScreen());
                  },
                ),
              Kpi(
                label: tr('ينتهي خلال 7 أيام'),
                value: '${expiring.length}',
                icon: Icons.hourglass_bottom,
                color: StatusColors.expiring,
                onTap: () => context.push(const MembersScreen(initialFilter: MemberFilter.expiring, standalone: true)),
              ),
              if (g.can(Perm.sell))
                Kpi(
                  label: tr('ديون مستحقة'),
                  value: fmtMoney(debtTotal),
                  icon: Icons.account_balance_wallet_outlined,
                  color: StatusColors.expired,
                  sub: tr('{n} عضو', {'n': debtors.length}),
                  onTap: () => context.push(const MembersScreen(initialFilter: MemberFilter.debt, standalone: true)),
                ),
              Kpi(
                label: tr('منتهي الاشتراك'),
                value: '${states[MemberState.expired]}',
                icon: Icons.person_off_outlined,
                color: StatusColors.none,
                sub: tr('فرص للاسترجاع'),
                onTap: () => context.push(const MembersScreen(initialFilter: MemberFilter.expired, standalone: true)),
              ),
            ]),
          ),
          Section(
            title: tr('إجراءات سريعة'),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                ActionCircle(icon: Icons.qr_code_scanner, label: tr('تسجيل دخول'), color: brandSeed, onTap: () => Shell.goTo(context, 2)),
                ActionCircle(
                    icon: Icons.autorenew,
                    label: tr('تجديد'),
                    color: StatusColors.active,
                    onTap: () => context.push(const MembersScreen(standalone: true, pickForRenew: true))),
                ActionCircle(icon: Icons.person_add_alt, label: tr('عضو جديد'), color: const Color(0xFF6366F1), onTap: () => context.push(const MemberFormScreen())),
                if (g.can(Perm.sell))
                  ActionCircle(icon: Icons.shopping_bag_outlined, label: tr('المتجر'), color: const Color(0xFFEA580C), onTap: () async {
                    if (await ensureFeature(context, Feature.shop) && context.mounted) context.push(const ShopScreen());
                  }),
                ActionCircle(icon: Icons.campaign_outlined, label: tr('الرسائل'), color: const Color(0xFF16A34A), onTap: () => context.push(const MessagesScreen())),
                ActionCircle(icon: Icons.person_search_outlined, label: tr('عملاء محتملون'), color: const Color(0xFFDB2777), onTap: () async {
                  if (await ensureFeature(context, Feature.leads) && context.mounted) context.push(const LeadsScreen());
                }),
              ]),
            ),
          ),
          if (pending > 0 || overdueInst.isNotEmpty || birthdays.isNotEmpty || followUps.isNotEmpty || lowStock.isNotEmpty)
            Section(
              title: tr('يحتاج انتباهك'),
              child: Card(
                child: Column(children: [
                  if (pending > 0)
                    _AlertTile(
                      icon: Icons.send,
                      color: const Color(0xFF16A34A),
                      title: tr('{n} رسالة تذكير جاهزة للإرسال', {'n': pending}),
                      subtitle: tr('أرسلها بلمسة من واتساب أو الرسائل'),
                      onTap: () => context.push(const MessagesScreen()),
                    ),
                  if (overdueInst.isNotEmpty)
                    _AlertTile(
                      icon: Icons.event_busy,
                      color: StatusColors.expired,
                      title: tr('{n} قسط مستحق أو متأخر', {'n': overdueInst.length}),
                      subtitle: fmtMoney(overdueInst.fold(0.0, (s, x) => s + x.left)),
                      onTap: () => Shell.goTo(context, 3),
                    ),
                  for (final m in birthdays)
                    _AlertTile(
                      icon: Icons.cake_outlined,
                      color: const Color(0xFFDB2777),
                      title: tr('عيد ميلاد {n} اليوم 🎂', {'n': m.name}),
                      onTap: () => context.push(MemberDetailScreen(memberId: m.id)),
                    ),
                  if (followUps.isNotEmpty)
                    _AlertTile(
                      icon: Icons.phone_callback_outlined,
                      color: const Color(0xFF6366F1),
                      title: tr('{n} متابعة لعملاء محتملين', {'n': followUps.length}),
                      onTap: () => context.push(const LeadsScreen()),
                    ),
                  if (lowStock.isNotEmpty)
                    _AlertTile(
                      icon: Icons.inventory_2_outlined,
                      color: StatusColors.expiring,
                      title: tr('{n} منتج قارب على النفاد', {'n': lowStock.length}),
                      subtitle: lowStock.map((p) => p.name).take(3).join('، '),
                      onTap: () => context.push(const ShopScreen()),
                    ),
                ]),
              ),
            ),
          if (canMoney)
            Section(
              title: tr('التحصيل آخر 14 يوماً'),
              trailing: TextButton(
                  onPressed: () async {
                    if (await ensureFeature(context, Feature.fullReports) && context.mounted) context.push(const ReportsScreen());
                  },
                  child: Text(tr('التقارير'))),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
                  child: SimpleBarChart(
                    values: [for (final x in series) x.value],
                    labels: [for (var i = 0; i < series.length; i++) i.isEven ? '${series[i].day.day}' : ''],
                    tooltipTitles: [for (final x in series) dayKey(x.day)],
                    format: (v) => fmtMoney(v),
                  ),
                ),
              ),
            ),
          if (expiring.isNotEmpty)
            Section(
              title: tr('تنتهي اشتراكاتهم قريباً'),
              trailing: TextButton(
                  onPressed: () => context.push(const MembersScreen(initialFilter: MemberFilter.expiring, standalone: true)),
                  child: Text(tr('الكل'))),
              child: Card(
                child: Column(children: [
                  for (final s in expiring.take(5))
                    if (g.members[s.memberId] case final m?)
                      ListTile(
                        leading: MemberAvatar(m, radius: 18),
                        title: Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${s.planName} • ${relativeDays(s.daysLeft(g.today))}'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push(MemberDetailScreen(memberId: m.id)),
                      ),
                ]),
              ),
            ),
          _TodayVisits(),
        ]),
      ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  const _AlertTile({required this.icon, required this.color, required this.title, this.subtitle, this.onTap});

  @override
  Widget build(BuildContext context) => ListTile(
        leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.12), child: Icon(icon, color: color, size: 20)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: subtitle == null ? null : Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      );
}

class _TodayVisits extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    final list = context.services.checkin.today().take(8).toList();
    if (list.isEmpty) return const SizedBox();
    return Section(
      title: tr('آخر الزيارات اليوم'),
      child: Card(
        child: Column(children: [
          for (final c in list)
            if (g.members[c.memberId] case final m?)
              ListTile(
                dense: true,
                leading: MemberAvatar(m, radius: 16),
                title: Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: c.allowed ? null : Text(checkinResultText(c.result), style: TextStyle(color: context.colors.error)),
                trailing: Text(hhmm(minutesOfDay(c.time)), style: const TextStyle(fontWeight: FontWeight.w700)),
                onTap: () => context.push(MemberDetailScreen(memberId: m.id)),
              ),
        ]),
      ),
    );
  }
}

String checkinResultText(CheckinResult r) => switch (r) {
      CheckinResult.allowed => tr('دخل'),
      CheckinResult.override => tr('سماح استثنائي'),
      CheckinResult.notFound => tr('غير معروف'),
      CheckinResult.archived => tr('مؤرشف'),
      CheckinResult.noSubscription => tr('بدون اشتراك'),
      CheckinResult.expired => tr('منتهي'),
      CheckinResult.exhausted => tr('انتهت الحصص'),
      CheckinResult.frozen => tr('مجمّد'),
      CheckinResult.notStarted => tr('لم يبدأ'),
      CheckinResult.outsideHours => tr('خارج ساعات الباقة'),
      CheckinResult.wrongDay => tr('يوم غير مسموح'),
      CheckinResult.genderHours => tr('خارج أوقاته'),
      CheckinResult.genderPlan => tr('باقة غير مناسبة'),
      CheckinResult.dailyLimit => tr('دخل اليوم'),
      CheckinResult.debt => tr('مديونية'),
    };

// ضروري لإعادة استخدام اسم الدور في الشاشات الأخرى
String roleLabel(Role r) => roleName(r);
