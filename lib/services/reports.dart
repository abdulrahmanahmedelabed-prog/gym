import '../core/dates.dart';
import '../core/i18n.dart';
import '../core/money.dart';
import '../data/gym_data.dart';
import '../models/activity.dart';
import '../models/billing.dart';
import '../models/plan.dart';
import '../models/subscription.dart';
import 'membership.dart';

class Range {
  final DateTime from; // شامل
  final DateTime to; // شامل
  Range(DateTime f, DateTime t)
      : from = dateOnly(f),
        to = dateOnly(t);

  bool has(DateTime t) {
    final d = dateOnly(t);
    return !d.isBefore(from) && !d.isAfter(to);
  }

  int get days => daysBetween(from, to) + 1;

  List<DateTime> get dayList => [for (var i = 0; i < days; i++) addDays(from, i)];

  static Range today(DateTime now) => Range(now, now);
  static Range thisMonth(DateTime now) => Range(DateTime(now.year, now.month, 1), now);
  static Range lastDays(DateTime now, int n) => Range(addDays(now, -(n - 1)), now);
  static Range thisYear(DateTime now) => Range(DateTime(now.year, 1, 1), now);
}

class Reports {
  final GymData d;
  final MembershipService ms;
  Reports(this.d) : ms = MembershipService(d);

  Iterable<Payment> paymentsIn(Range r) => d.payments.all.where((p) => r.has(p.date));

  /// المبالغ المحصّلة (نقدية فعلية) بعد الاستردادات
  double collected(Range r) => roundMoney(paymentsIn(r).fold(0.0, (s, p) => s + p.amount));

  /// التحصيل حسب الحساب/المحفظة (للمطابقة مع كشف كل حساب)
  Map<String, ({double total, int count, int unverified})> collectedByAccount(Range r) {
    final m = <String, ({double total, int count, int unverified})>{};
    for (final p in paymentsIn(r)) {
      final k = p.account ?? payMethodName(p.method);
      final x = m[k] ?? (total: 0.0, count: 0, unverified: 0);
      m[k] = (total: roundMoney(x.total + p.amount), count: x.count + 1, unverified: x.unverified + (p.needsCheck ? 1 : 0));
    }
    return m;
  }

  Map<PayMethod, double> collectedByMethod(Range r) {
    final m = <PayMethod, double>{};
    for (final p in paymentsIn(r)) {
      m[p.method] = roundMoney((m[p.method] ?? 0) + p.amount);
    }
    return m;
  }

  /// المبيعات (قيمة الفواتير) حسب النوع: اشتراكات، تدريب شخصي، متجر...
  Map<ItemKind, double> salesByKind(Range r) {
    final m = <ItemKind, double>{};
    for (final inv in d.invoices.all) {
      if (inv.voided || !r.has(inv.date)) continue;
      final sub = inv.subtotal;
      final factor = sub == 0 ? 0 : inv.total / sub; // توزيع خصم الفاتورة والضريبة على البنود
      for (final i in inv.items) {
        final k = i.total < 0 ? ItemKind.subscription : i.kind; // بنود الإلغاء تُخصم من الاشتراكات
        m[k] = roundMoney((m[k] ?? 0) + i.total * factor);
      }
    }
    return m;
  }

  double sales(Range r) =>
      roundMoney(d.invoices.all.where((i) => !i.voided && r.has(i.date)).fold(0.0, (s, i) => s + i.total));

  double taxCollected(Range r) =>
      roundMoney(d.invoices.all.where((i) => !i.voided && r.has(i.date)).fold(0.0, (s, i) => s + i.tax));

  double expenses(Range r) => roundMoney(d.expenses.all.where((e) => r.has(e.date)).fold(0.0, (s, e) => s + e.amount));

  Map<String, double> expensesByCategory(Range r) {
    final m = <String, double>{};
    for (final e in d.expenses.all.where((e) => r.has(e.date))) {
      m[e.category] = roundMoney((m[e.category] ?? 0) + e.amount);
    }
    return m;
  }

  /// صافي الربح النقدي = المحصّل − المصروفات
  double net(Range r) => roundMoney(collected(r) - expenses(r));

  /// التحصيل اليومي للرسم البياني
  List<({DateTime day, double value})> dailyCollections(Range r) {
    final m = <String, double>{};
    for (final p in paymentsIn(r)) {
      final k = dayKey(p.date);
      m[k] = (m[k] ?? 0) + p.amount;
    }
    return [for (final day in r.dayList) (day: day, value: roundMoney(m[dayKey(day)] ?? 0))];
  }

  // ---------------------------------------------------------------------------
  // الأعضاء
  // ---------------------------------------------------------------------------

  Map<MemberState, int> memberStates([DateTime? day]) {
    final m = <MemberState, int>{for (final s in MemberState.values) s: 0};
    for (final x in d.members.all) {
      if (x.archived) continue;
      final st = ms.stateOf(x.id, day);
      m[st] = m[st]! + 1;
    }
    return m;
  }

  int activeCount([DateTime? day]) {
    final s = memberStates(day);
    return s[MemberState.active]! + s[MemberState.expiring]!;
  }

  /// الاشتراكات المنتهية خلال [days] يوماً ولم تُجدَّد
  List<Subscription> expiringSoon({int days = 7}) {
    final today = d.today;
    final out = <Subscription>[];
    for (final m in d.members.all) {
      if (m.archived) continue;
      final s = ms.currentSub(m.id);
      if (s == null || s.statusOn(today) != SubStatus.active) continue;
      final dl = s.daysLeft(today);
      if (dl <= days && !ms.renewedAfter(s)) out.add(s);
    }
    out.sort((a, b) => a.end.compareTo(b.end));
    return out;
  }

  /// منتهية مؤخراً ولم تُجدَّد (فرص استرجاع)
  List<Subscription> recentlyExpired({int days = 30}) {
    final today = d.today;
    final out = <Subscription>[];
    for (final m in d.members.all) {
      if (m.archived) continue;
      final s = ms.currentSub(m.id);
      if (s == null) continue;
      final st = s.statusOn(today);
      if (st != SubStatus.expired && st != SubStatus.exhausted) continue;
      if (daysBetween(s.end, today) <= days) out.add(s);
    }
    out.sort((a, b) => b.end.compareTo(a.end));
    return out;
  }

  int newMembers(Range r) => d.members.all.where((m) => r.has(m.createdAt)).length;

  /// اشتراكات بيعت في الفترة: جديدة أو تجديد
  ({int fresh, int renewals}) subsSold(Range r) {
    var fresh = 0, renewals = 0;
    for (final s in d.subs.all) {
      if (s.imported || s.kind == PlanKind.pt || !r.has(s.createdAt)) continue;
      final earlier = d.subsOf(s.memberId).any((o) => o.id != s.id && o.kind != PlanKind.pt && o.createdAt.isBefore(s.createdAt));
      if (earlier) {
        renewals++;
      } else {
        fresh++;
      }
    }
    return (fresh: fresh, renewals: renewals);
  }

  /// نسبة التجديد: من الاشتراكات التي انتهت في الفترة، كم جُدِّد؟
  ({int ended, int renewed, double rate}) renewalRate(Range r) {
    var ended = 0, renewed = 0;
    for (final s in d.subs.all) {
      if (s.cancelled || s.kind == PlanKind.pt || !r.has(s.end)) continue;
      ended++;
      if (ms.renewedAfter(s)) renewed++;
    }
    return (ended: ended, renewed: renewed, rate: ended == 0 ? 0 : renewed / ended);
  }

  List<({String plan, int count, double revenue})> planPopularity(Range r) {
    final m = <String, ({int count, double revenue})>{};
    for (final s in d.subs.all) {
      if (s.imported || s.cancelled || !r.has(s.createdAt)) continue;
      final x = m[s.planName] ?? (count: 0, revenue: 0.0);
      m[s.planName] = (count: x.count + 1, revenue: roundMoney(x.revenue + s.total));
    }
    final out = [for (final e in m.entries) (plan: e.key, count: e.value.count, revenue: e.value.revenue)];
    out.sort((a, b) => b.count.compareTo(a.count));
    return out;
  }

  // ---------------------------------------------------------------------------
  // الحضور
  // ---------------------------------------------------------------------------

  Iterable<Checkin> get _visitsBase => d.checkins.all.where((c) => c.allowed && c.method != 'pt');

  List<({DateTime day, int count})> dailyVisits(Range r) {
    final m = <String, int>{};
    for (final c in _visitsBase) {
      if (!r.has(c.time)) continue;
      final k = dayKey(c.time);
      m[k] = (m[k] ?? 0) + 1;
    }
    return [for (final day in r.dayList) (day: day, count: m[dayKey(day)] ?? 0)];
  }

  /// أوقات الذروة: عدد الزيارات حسب الساعة
  List<int> visitsByHour(Range r) {
    final h = List.filled(24, 0);
    for (final c in _visitsBase) {
      if (r.has(c.time)) h[c.time.hour]++;
    }
    return h;
  }

  /// الزيارات حسب يوم الأسبوع (1..7)
  Map<int, int> visitsByWeekday(Range r) {
    final m = {for (var i = 1; i <= 7; i++) i: 0};
    for (final c in _visitsBase) {
      if (r.has(c.time)) m[c.time.weekday] = m[c.time.weekday]! + 1;
    }
    return m;
  }

  List<({String memberId, int visits})> topAttendees(Range r, {int limit = 10}) {
    final m = <String, int>{};
    for (final c in _visitsBase) {
      if (r.has(c.time)) m[c.memberId] = (m[c.memberId] ?? 0) + 1;
    }
    final out = [for (final e in m.entries) (memberId: e.key, visits: e.value)];
    out.sort((a, b) => b.visits.compareTo(a.visits));
    return out.take(limit).toList();
  }

  // ---------------------------------------------------------------------------
  // المدربون
  // ---------------------------------------------------------------------------

  List<({String trainerId, double ptSales, int sessions, double commission, double sessionPay})> trainers(Range r) {
    final out = <({String trainerId, double ptSales, int sessions, double commission, double sessionPay})>[];
    for (final t in d.staff.all.where((s) => s.isTrainer)) {
      var sales = 0.0;
      for (final s in d.subs.all) {
        if (s.trainerId == t.id && !s.cancelled && r.has(s.createdAt)) sales += s.total;
      }
      var sessions = 0;
      for (final c in d.checkins.all) {
        if (c.method != 'pt' || !r.has(c.time)) continue;
        if (d.subs[c.subscriptionId]?.trainerId == t.id) sessions++;
      }
      out.add((
        trainerId: t.id,
        ptSales: roundMoney(sales),
        sessions: sessions,
        commission: roundMoney(sales * t.commissionPct / 100),
        sessionPay: roundMoney(sessions * t.sessionRate),
      ));
    }
    return out;
  }

  /// ملخص يوم بنص قصير (لرسالة صاحب النادي وإغلاق اليوم)
  String dailySummaryText(DateTime day) {
    final r = Range(day, day);
    final byMethod = collectedByMethod(r);
    final sold = subsSold(r);
    final b = StringBuffer()
      ..writeln(tr('💰 المحصّل: {a}', {'a': fmtMoney(collected(r))}));
    for (final e in byMethod.entries) {
      b.writeln('   • ${payMethodName(e.key)}: ${fmtMoney(e.value)}');
    }
    final exp = expenses(r);
    if (exp > 0) b.writeln(tr('📉 المصروفات: {a}', {'a': fmtMoney(exp)}));
    b
      ..writeln(tr('🆕 اشتراكات جديدة: {n} — تجديد: {r}', {'n': sold.fresh, 'r': sold.renewals}))
      ..writeln(tr('🚶 الزيارات: {n}', {'n': dailyVisits(r).first.count}))
      ..writeln(tr('⏳ تنتهي خلال 7 أيام: {n}', {'n': expiringSoon().length}))
      ..writeln(tr('👥 الأعضاء الفعّالون: {n}', {'n': activeCount(day)}));
    return b.toString().trim();
  }
}

String payMethodName(PayMethod m) => switch (m) {
      PayMethod.cash => tr('نقداً'),
      PayMethod.card => tr('بطاقة'),
      PayMethod.transfer => tr('تحويل بنكي'),
      PayMethod.wallet => tr('محفظة إلكترونية'),
      PayMethod.online => tr('دفع أونلاين'),
    };

String itemKindName(ItemKind k) => switch (k) {
      ItemKind.subscription => tr('اشتراكات'),
      ItemKind.registration => tr('رسوم تسجيل'),
      ItemKind.pt => tr('تدريب شخصي'),
      ItemKind.product => tr('المتجر'),
      ItemKind.locker => tr('خزائن'),
      ItemKind.classFee => tr('حصص'),
      ItemKind.other => tr('أخرى'),
    };
