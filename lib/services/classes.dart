import '../core/dates.dart';
import '../core/i18n.dart';
import '../core/ids.dart';
import '../data/gym_data.dart';
import '../models/activity.dart';
import '../models/base.dart';
import '../models/business.dart';
import '../models/member.dart';
import '../models/subscription.dart';
import 'license.dart';
import 'membership.dart';

/// موعد فعلي لحصة في يوم محدد
class ClassSession {
  final GymClass cls;
  final DateTime start;
  ClassSession(this.cls, this.start);

  DateTime get end => start.add(Duration(minutes: cls.durationMin));
  String get key => Booking.sessionKeyOf(cls.id, start);
}

class ClassService {
  final GymData d;
  final MembershipService ms;
  ClassService(this.d) : ms = MembershipService(d);

  List<ClassSession> sessionsOn(DateTime day) {
    day = dateOnly(day);
    final out = <ClassSession>[];
    for (final c in d.classes.all.where((c) => c.active)) {
      for (final s in c.slots) {
        if (s.weekday == day.weekday) {
          out.add(ClassSession(c, DateTime(day.year, day.month, day.day, s.start ~/ 60, s.start % 60)));
        }
      }
    }
    out.sort((a, b) => a.start.compareTo(b.start));
    return out;
  }

  List<Booking> bookingsOf(ClassSession s) {
    final l = d.bookings.all.where((b) => b.sessionKey == s.key && b.status != BookingStatus.cancelled).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return l;
  }

  int booked(ClassSession s) => bookingsOf(s).where((b) => b.status != BookingStatus.waitlist).length;

  /// حجز: إن امتلأت الحصة يدخل قائمة الانتظار
  Future<Booking> book(ClassSession s, Member m) async {
    d.require(Feature.classes);
    if (s.start.isBefore(d.now().subtract(const Duration(minutes: 15)))) throw GymException(tr('الحصة بدأت أو انتهت'));
    if (s.cls.gender != null && m.gender != null && s.cls.gender != m.gender) {
      throw GymException(tr('الحصة غير مخصصة لهذا العضو'));
    }
    if (s.cls.membersOnly) {
      final sub = ms.currentSub(m.id, s.start);
      final st = sub?.statusOn(s.start);
      if (st != SubStatus.active) throw GymException(tr('الحصة للأعضاء ذوي الاشتراك الفعّال فقط'));
    }
    if (bookingsOf(s).any((b) => b.memberId == m.id)) throw GymException(tr('العضو محجوز في هذه الحصة'));
    final full = booked(s) >= s.cls.capacity;
    final b = Booking(
      id: newId(),
      classId: s.cls.id,
      sessionStart: s.start,
      memberId: m.id,
      status: full ? BookingStatus.waitlist : BookingStatus.booked,
      createdAt: d.now(),
    );
    await d.put(b);
    return b;
  }

  /// إلغاء الحجز: أول من في قائمة الانتظار يأخذ المكان
  Future<Booking?> cancel(Booking b) async {
    final wasBooked = b.status == BookingStatus.booked;
    b.status = BookingStatus.cancelled;
    final save = <Entity>[b];
    Booking? promoted;
    if (wasBooked) {
      final cls = d.classes[b.classId];
      if (cls != null) {
        final s = ClassSession(cls, b.sessionStart);
        for (final x in bookingsOf(s)) {
          if (x.status == BookingStatus.waitlist && x.id != b.id) {
            x.status = BookingStatus.booked;
            promoted = x;
            save.add(x);
            break;
          }
        }
      }
    }
    await d.putAll(save);
    return promoted;
  }

  Future<void> mark(Booking b, BookingStatus st) async {
    b.status = st;
    final save = <Entity>[b];
    if (st == BookingStatus.attended) {
      // الحضور يُسجل كزيارة للنادي أيضاً إن لم يدخل اليوم
      final today = dateOnly(b.sessionStart);
      final visited = d.checkinsOf(b.memberId).any((c) => c.allowed && dateOnly(c.time) == today);
      if (!visited) {
        save.add(Checkin(
            id: newId(),
            memberId: b.memberId,
            time: b.sessionStart,
            result: CheckinResult.allowed,
            method: 'class',
            by: d.userName,
            note: d.classes[b.classId]?.name));
      }
    }
    await d.putAll(save);
  }
}
