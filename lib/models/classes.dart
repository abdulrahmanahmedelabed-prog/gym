import '../core/dates.dart';
import 'base.dart';
import 'member.dart';

/// نوع حصة جماعية (زومبا، سبينينج، كروس فت...) وإعداداتها الافتراضية
class GymClass implements Entity {
  @override
  final String id;
  String name;
  String? trainerId;
  int capacity; // 0 = بلا حد
  int durationMinutes;
  String? room;
  Gender? gender;
  double dropInPrice; // سعر الحصة لغير المشترك أو لمن لا تشمل باقته الحصص (0 = غير متاح)
  int colorValue;
  String? description;
  bool active;

  GymClass({
    required this.id,
    required this.name,
    this.trainerId,
    this.capacity = 20,
    this.durationMinutes = 60,
    this.room,
    this.gender,
    this.dropInPrice = 0,
    this.colorValue = 0xFF8E24AA,
    this.description,
    this.active = true,
  });

  @override
  Map<String, Object?> toMap() => compact({
        'id': id,
        'name': name,
        'trainerId': trainerId,
        'capacity': capacity,
        'durationMinutes': durationMinutes,
        'room': room,
        'gender': genderCode(gender),
        'dropInPrice': dropInPrice == 0 ? null : dropInPrice,
        'color': colorValue,
        'description': description,
        'active': active,
      });

  factory GymClass.fromMap(Map<String, Object?> m) => GymClass(
        id: asStr(m['id']),
        name: asStr(m['name']),
        trainerId: asStrOrNull(m['trainerId']),
        capacity: asInt(m['capacity'], 20),
        durationMinutes: asInt(m['durationMinutes'], 60),
        room: asStrOrNull(m['room']),
        gender: genderFrom(m['gender']),
        dropInPrice: asDouble(m['dropInPrice']),
        colorValue: asInt(m['color'], 0xFF8E24AA),
        description: asStrOrNull(m['description']),
        active: asBool(m['active'], true),
      );
}

/// موعد أسبوعي ثابت: الحصة [classId] كل [weekday] الساعة [startMinute].
/// تُولَّد منه مواعيد ClassSession للأسابيع القادمة.
class ClassSlot implements Entity {
  @override
  final String id;
  final String classId;
  int weekday; // 1 = الاثنين ... 7 = الأحد
  int startMinute; // بالدقائق من منتصف الليل
  String? trainerId; // يتجاوز مدرب الحصة الافتراضي
  DateTime? validFrom;
  DateTime? validTo;
  bool active;

  ClassSlot({
    required this.id,
    required this.classId,
    required this.weekday,
    required this.startMinute,
    this.trainerId,
    this.validFrom,
    this.validTo,
    this.active = true,
  });

  bool appliesOn(DateTime day) =>
      active &&
      day.weekday == weekday &&
      (validFrom == null || !dateOnly(day).isBefore(validFrom!)) &&
      (validTo == null || !dateOnly(day).isAfter(validTo!));

  @override
  Map<String, Object?> toMap() => compact({
        'id': id,
        'classId': classId,
        'weekday': weekday,
        'startMinute': startMinute,
        'trainerId': trainerId,
        'validFrom': validFrom == null ? null : dayKey(validFrom!),
        'validTo': validTo == null ? null : dayKey(validTo!),
        'active': active,
      });

  factory ClassSlot.fromMap(Map<String, Object?> m) => ClassSlot(
        id: asStr(m['id']),
        classId: asStr(m['classId']),
        weekday: asInt(m['weekday'], 1),
        startMinute: asInt(m['startMinute']),
        trainerId: asStrOrNull(m['trainerId']),
        validFrom: tryParseDay(asStrOrNull(m['validFrom'])),
        validTo: tryParseDay(asStrOrNull(m['validTo'])),
        active: asBool(m['active'], true),
      );
}

/// موعد فعلي لحصة في يوم محدد (من جدول أسبوعي أو حصة منفردة)
class ClassSession implements Entity {
  @override
  final String id;
  final String classId;
  final String? slotId;
  DateTime start;
  int durationMinutes;
  String? trainerId;
  int capacity;
  String? room;
  bool cancelled;
  String? cancelReason;

  ClassSession({
    required this.id,
    required this.classId,
    this.slotId,
    required this.start,
    required this.durationMinutes,
    this.trainerId,
    required this.capacity,
    this.room,
    this.cancelled = false,
    this.cancelReason,
  });

  DateTime get end => start.add(Duration(minutes: durationMinutes));

  @override
  Map<String, Object?> toMap() => compact({
        'id': id,
        'classId': classId,
        'slotId': slotId,
        'start': start.toIso8601String(),
        'durationMinutes': durationMinutes,
        'trainerId': trainerId,
        'capacity': capacity,
        'room': room,
        'cancelled': cancelled ? true : null,
        'cancelReason': cancelReason,
      });

  factory ClassSession.fromMap(Map<String, Object?> m) => ClassSession(
        id: asStr(m['id']),
        classId: asStr(m['classId']),
        slotId: asStrOrNull(m['slotId']),
        start: asTime(m['start']) ?? DateTime.now(),
        durationMinutes: asInt(m['durationMinutes'], 60),
        trainerId: asStrOrNull(m['trainerId']),
        capacity: asInt(m['capacity']),
        room: asStrOrNull(m['room']),
        cancelled: asBool(m['cancelled']),
        cancelReason: asStrOrNull(m['cancelReason']),
      );
}

/// waitlist = الحصة ممتلئة، يُرقّى تلقائياً عند إلغاء حجز
enum BookingStatus { booked, waitlist, attended, noShow, cancelled }

BookingStatus bookingStatusFrom(Object? v) =>
    BookingStatus.values.firstWhere((s) => s.name == v, orElse: () => BookingStatus.booked);

class Booking implements Entity {
  @override
  final String id;
  final String sessionId;
  final String memberId;
  String? subscriptionId; // الاشتراك الذي غطّى الحصة
  String? invoiceId; // فاتورة الحصة المنفردة
  BookingStatus status;
  final DateTime createdAt;
  DateTime? cancelledAt;
  String? by;

  Booking({
    required this.id,
    required this.sessionId,
    required this.memberId,
    this.subscriptionId,
    this.invoiceId,
    this.status = BookingStatus.booked,
    required this.createdAt,
    this.cancelledAt,
    this.by,
  });

  /// يشغل مقعداً في الحصة
  bool get holdsSeat => status == BookingStatus.booked || status == BookingStatus.attended;

  @override
  Map<String, Object?> toMap() => compact({
        'id': id,
        'sessionId': sessionId,
        'memberId': memberId,
        'subscriptionId': subscriptionId,
        'invoiceId': invoiceId,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        'cancelledAt': cancelledAt?.toIso8601String(),
        'by': by,
      });

  factory Booking.fromMap(Map<String, Object?> m) => Booking(
        id: asStr(m['id']),
        sessionId: asStr(m['sessionId']),
        memberId: asStr(m['memberId']),
        subscriptionId: asStrOrNull(m['subscriptionId']),
        invoiceId: asStrOrNull(m['invoiceId']),
        status: bookingStatusFrom(m['status']),
        createdAt: asTime(m['createdAt']) ?? DateTime.now(),
        cancelledAt: asTime(m['cancelledAt']),
        by: asStrOrNull(m['by']),
      );
}
