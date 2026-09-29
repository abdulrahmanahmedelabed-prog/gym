import '../core/dates.dart';
import '../core/i18n.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../data/gym_data.dart';
import '../models/activity.dart';
import '../models/base.dart';
import '../models/business.dart';
import '../models/member.dart';
import '../models/plan.dart';
import '../models/settings.dart';
import '../models/subscription.dart';
import 'membership.dart';

/// نتيجة فحص الدخول قبل التسجيل: يُعرض لموظف الاستقبال (أو على شاشة الدخول الذاتي)
class CheckinDecision {
  final Member? member;
  final Subscription? sub;
  final CheckinResult result;
  final String message;
  final List<String> warnings;
  final int? daysLeft;
  final int? visitsLeft;
  final double balance;
  final bool birthday;

  CheckinDecision({
    this.member,
    this.sub,
    required this.result,
    required this.message,
    this.warnings = const [],
    this.daysLeft,
    this.visitsLeft,
    this.balance = 0,
    this.birthday = false,
  });

  bool get allowed => result == CheckinResult.allowed;

  /// هل يمكن للمدير السماح بالدخول رغم المانع؟
  bool get overridable => member != null && !allowed && result != CheckinResult.notFound && result != CheckinResult.archived;
}

class CheckinService {
  final GymData d;
  final MembershipService ms;
  CheckinService(this.d) : ms = MembershipService(d);

  /// الأعضاء الموجودون الآن تقريباً (دخلوا خلال متوسط مدة التمرين)
  List<Checkin> inGymNow() {
    final since = d.now().subtract(Duration(minutes: d.settings.sessionMinutes));
    final seen = <String>{};
    final out = <Checkin>[];
    final list = d.checkins.all.where((c) => c.allowed && c.time.isAfter(since)).toList()
      ..sort((a, b) => b.time.compareTo(a.time));
    for (final c in list) {
      if (seen.add(c.memberId)) out.add(c);
    }
    return out;
  }

  List<Checkin> today() {
    final t = d.today;
    return d.checkins.all.where((c) => dateOnly(c.time) == t).toList()..sort((a, b) => b.time.compareTo(a.time));
  }

  int _entriesToday(String memberId, DateTime day) =>
      d.checkinsOf(memberId).where((c) => c.allowed && dateOnly(c.time) == day && c.method != 'pt').length;

  String _genderWord(String g) => g == 'f' ? tr('السيدات') : tr('الرجال');

  CheckinDecision evaluate(Member? m, [DateTime? at]) {
    final now = at ?? d.now();
    final day = dateOnly(now);
    if (m == null) {
      return CheckinDecision(result: CheckinResult.notFound, message: tr('البطاقة غير معروفة'));
    }
    CheckinDecision deny(CheckinResult r, String msg, {Subscription? sub}) => CheckinDecision(
          member: m,
          sub: sub,
          result: r,
          message: msg,
          balance: d.balanceOf(m.id),
          daysLeft: sub?.daysLeft(day),
          visitsLeft: sub?.visitsLeft,
          birthday: m.isBirthday(day),
        );

    if (m.archived) return deny(CheckinResult.archived, tr('العضوية مؤرشفة'));
    final sub = ms.currentSub(m.id, day);
    if (sub == null) return deny(CheckinResult.noSubscription, tr('لا يوجد اشتراك'));

    final warnings = <String>[];
    switch (sub.statusOn(day)) {
      case SubStatus.pending:
        return deny(CheckinResult.notStarted, tr('الاشتراك يبدأ في {d}', {'d': dayKey(sub.start)}), sub: sub);
      case SubStatus.frozen:
        final f = sub.freezeOn(day)!;
        return deny(CheckinResult.frozen, tr('الاشتراك مجمّد حتى {d}', {'d': dayKey(f.end)}), sub: sub);
      case SubStatus.exhausted:
        return deny(CheckinResult.exhausted, tr('انتهت الحصص ({n} من {t})', {'n': sub.visitsUsed, 't': sub.visitsTotal}),
            sub: sub);
      case SubStatus.expired:
        final since = daysBetween(sub.end, day);
        if (since <= d.settings.graceDays) {
          warnings.add(tr('انتهى الاشتراك منذ {n} يوم (فترة سماح)', {'n': since}));
        } else {
          return deny(CheckinResult.expired, tr('انتهى الاشتراك في {d}', {'d': dayKey(sub.end)}), sub: sub);
        }
      case SubStatus.cancelled:
        return deny(CheckinResult.noSubscription, tr('الاشتراك ملغي'), sub: sub);
      case SubStatus.active:
        break;
    }

    final plan = d.plans[sub.planId];
    // ساعات الرجال/السيدات
    final g = genderCode(m.gender);
    if (g != null) {
      final windows = d.settings.genderWindows;
      final m0 = minutesOfDay(now);
      bool covers(GenderWindow w) {
        if (w.weekdays.isNotEmpty && !w.weekdays.contains(now.weekday)) return false;
        // نافذة تتجاوز منتصف الليل (مثل 20:00 – 01:00)
        return w.from <= w.to ? (m0 >= w.from && m0 <= w.to) : (m0 >= w.from || m0 <= w.to);
      }
      final otherActive = windows.where((w) => w.gender != g && covers(w)).toList();
      if (otherActive.isNotEmpty) {
        final w = otherActive.first;
        return deny(CheckinResult.genderHours,
            tr('الوقت الآن مخصص لـ {g} ({r})', {'g': _genderWord(w.gender), 'r': hhmmRange(w.from, w.to)}),
            sub: sub);
      }
      final own = windows.where((w) => w.gender == g).toList();
      if (own.isNotEmpty && d.settings.data['genderStrict'] != false && !own.any(covers)) {
        final times = own.map((w) => hhmmRange(w.from, w.to)).toSet().join('، ');
        return deny(CheckinResult.genderHours, tr('أوقات {g}: {t}', {'g': _genderWord(g), 't': times}), sub: sub);
      }
    }
    if (plan != null) {
      if (plan.gender != null && m.gender != null && plan.gender != m.gender) {
        return deny(CheckinResult.genderPlan, tr('الباقة لا تناسب هذا العضو'), sub: sub);
      }
      if (plan.weekdays.isNotEmpty && !plan.weekdays.contains(now.weekday)) {
        return deny(CheckinResult.wrongDay, tr('الباقة لا تسمح بالدخول اليوم'), sub: sub);
      }
      if (!plan.allowsTime(now)) {
        return deny(CheckinResult.outsideHours,
            tr('الباقة تسمح بالدخول من {f} إلى {t}', {'f': hhmm(plan.accessFrom!), 't': hhmm(plan.accessTo!)}), sub: sub);
      }
      if (plan.dailyLimit > 0 && _entriesToday(m.id, day) >= plan.dailyLimit) {
        return deny(CheckinResult.dailyLimit, tr('دخل اليوم بالفعل'), sub: sub);
      }
    }

    final balance = d.balanceOf(m.id);
    final overdue = d.overdueOf(m.id, day);
    if (overdue > 0.001) {
      if (d.settings.blockOnDebt && overdue > d.settings.debtLimit) {
        return deny(CheckinResult.debt, tr('عليه مبلغ متأخر {a}', {'a': fmtMoney(overdue)}), sub: sub);
      }
      warnings.add(tr('عليه مبلغ متأخر {a}', {'a': fmtMoney(overdue)}));
    } else if (balance > 0.001) {
      warnings.add(tr('عليه أقساط قادمة {a}', {'a': fmtMoney(balance)}));
    }
    final daysLeft = sub.daysLeft(day);
    if (daysLeft >= 0 && daysLeft <= 3 && !ms.renewedAfter(sub)) {
      warnings.add(daysLeft == 0 ? tr('اليوم آخر يوم في الاشتراك') : tr('ينتهي الاشتراك بعد {n} يوم', {'n': daysLeft}));
    }
    final vl = sub.visitsLeft;
    if (vl != null && vl - 1 <= 2) warnings.add(tr('تبقى {n} حصة بعد هذه', {'n': vl - 1}));
    if (m.medicalNotes != null) warnings.add('⚕ ${m.medicalNotes}');
    if (d.checkinsOf(m.id).where((c) => c.allowed).isEmpty) warnings.add(tr('أول زيارة — رحّب به!'));
    final bd = m.isBirthday(day);
    if (bd) warnings.add(tr('عيد ميلاده اليوم 🎂'));

    return CheckinDecision(
      member: m,
      sub: sub,
      result: CheckinResult.allowed,
      message: tr('أهلاً {n}', {'n': m.firstName}),
      warnings: warnings,
      daysLeft: daysLeft,
      visitsLeft: vl == null ? null : vl - 1,
      balance: balance,
      birthday: bd,
    );
  }

  /// تسجيل محاولة الدخول. عند السماح تُخصم حصة من الباقات المحدودة.
  Future<Checkin> commit(CheckinDecision dec, {String method = 'manual', bool override = false, String? note}) async {
    final m = dec.member;
    if (m == null) throw GymException(dec.message);
    if (override && !d.can(Perm.override)) throw GymException(tr('يحتاج صلاحية المدير'));
    final result = dec.allowed ? CheckinResult.allowed : (override ? CheckinResult.override : dec.result);
    final c = Checkin(
      id: newId(),
      memberId: m.id,
      subscriptionId: dec.sub?.id,
      time: d.now(),
      result: result,
      method: method,
      by: d.userName,
      note: note ?? (override ? dec.message : null),
    );
    final save = <Entity>[c];
    final sub = dec.sub;
    if (c.allowed && sub != null && sub.visitsTotal != null && sub.visitsUsed < sub.visitsTotal!) {
      sub.visitsUsed++;
      save.add(sub);
    }
    if (override) save.add(d.auditEntry('override', '${m.name}: ${dec.message}'));
    await d.putAll(save);
    return c;
  }

  /// تسجيل جلسة تدريب شخصي (تُخصم من باقة التدريب)
  Future<Checkin> recordPtSession(Subscription pt, {String? note}) async {
    if (pt.kind != PlanKind.pt) throw GymException(tr('ليست باقة تدريب شخصي'));
    final st = pt.statusOn(d.today);
    if (st != SubStatus.active) throw GymException(tr('باقة التدريب غير فعالة'));
    pt.visitsUsed++;
    final c = Checkin(
      id: newId(),
      memberId: pt.memberId,
      subscriptionId: pt.id,
      time: d.now(),
      result: CheckinResult.allowed,
      method: 'pt',
      by: d.userName,
      note: note,
    );
    await d.putAll([c, pt]);
    return c;
  }
}
