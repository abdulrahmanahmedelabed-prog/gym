import '../core/dates.dart';
import 'base.dart';
import 'plan.dart';

/// فترة تجميد: العضو لا يدخل من [start] إلى [end] (شاملة)، وتُضاف أيامها لنهاية الاشتراك.
class Freeze {
  final String id;
  DateTime start;
  DateTime end;
  String? reason;
  final DateTime createdAt;

  Freeze({required this.id, required this.start, required this.end, this.reason, required this.createdAt});

  int get days => daysBetween(start, end) + 1;

  bool covers(DateTime day) => !day.isBefore(start) && !day.isAfter(end);

  Map<String, Object?> toMap() => compact({
        'id': id,
        'start': dayKey(start),
        'end': dayKey(end),
        'reason': reason,
        'createdAt': createdAt.toIso8601String(),
      });

  factory Freeze.fromMap(Map<String, Object?> m) => Freeze(
        id: asStr(m['id']),
        start: parseDay(asStr(m['start'])),
        end: parseDay(asStr(m['end'])),
        reason: asStrOrNull(m['reason']),
        createdAt: asTime(m['createdAt']) ?? DateTime.now(),
      );
}

enum SubStatus { active, pending, frozen, expired, exhausted, cancelled }

class Subscription implements Entity {
  @override
  final String id;
  final String memberId;
  String planId;
  String planName; // نسخة من اسم الباقة وقت البيع
  PlanKind kind;
  DateTime start;
  DateTime end; // آخر يوم مسموح (شامل)
  int? visitsTotal;
  int visitsUsed;
  double price;
  double discount;
  int freezeDaysAllowed;
  int freezeTimesAllowed;
  List<Freeze> freezes;
  String? invoiceId;
  String? trainerId; // للتدريب الشخصي
  bool cancelled;
  DateTime? cancelledAt;
  String? cancelReason;
  String? notes;
  bool imported; // مستورد من نظام قديم (بدون فاتورة)
  final DateTime createdAt;
  String? createdBy;

  Subscription({
    required this.id,
    required this.memberId,
    required this.planId,
    required this.planName,
    required this.kind,
    required this.start,
    required this.end,
    this.visitsTotal,
    this.visitsUsed = 0,
    this.price = 0,
    this.discount = 0,
    this.freezeDaysAllowed = 0,
    this.freezeTimesAllowed = 0,
    List<Freeze>? freezes,
    this.invoiceId,
    this.trainerId,
    this.cancelled = false,
    this.cancelledAt,
    this.cancelReason,
    this.notes,
    this.imported = false,
    required this.createdAt,
    this.createdBy,
  }) : freezes = freezes ?? [];

  double get total => price - discount;

  int? get visitsLeft => visitsTotal == null ? null : (visitsTotal! - visitsUsed).clamp(0, 1 << 30);

  int get freezeDaysUsed => freezes.fold(0, (s, f) => s + f.days);

  int get freezeDaysLeft => (freezeDaysAllowed - freezeDaysUsed).clamp(0, 1 << 30);

  int get freezeTimesLeft => (freezeTimesAllowed - freezes.length).clamp(0, 1 << 30);

  Freeze? freezeOn(DateTime day) {
    for (final f in freezes) {
      if (f.covers(day)) return f;
    }
    return null;
  }

  /// أول تجميد لم ينتهِ بعد (الحالي أو القادم)
  Freeze? upcomingFreeze(DateTime day) {
    Freeze? best;
    for (final f in freezes) {
      if (!f.end.isBefore(day) && (best == null || f.start.isBefore(best.start))) best = f;
    }
    return best;
  }

  SubStatus statusOn(DateTime day) {
    day = dateOnly(day);
    if (cancelled) return SubStatus.cancelled;
    if (day.isBefore(start)) return SubStatus.pending;
    if (freezeOn(day) != null) return SubStatus.frozen;
    if (day.isAfter(end)) return SubStatus.expired;
    if (visitsTotal != null && visitsUsed >= visitsTotal!) return SubStatus.exhausted;
    return SubStatus.active;
  }

  /// الأيام المتبقية بعد اليوم (0 = اليوم آخر يوم)
  int daysLeft(DateTime day) => daysBetween(dateOnly(day), end);

  int get totalDays => daysBetween(start, end) + 1;

  @override
  Map<String, Object?> toMap() => compact({
        'id': id,
        'memberId': memberId,
        'planId': planId,
        'planName': planName,
        'kind': kind.name,
        'start': dayKey(start),
        'end': dayKey(end),
        'visitsTotal': visitsTotal,
        'visitsUsed': visitsUsed,
        'price': price,
        'discount': discount == 0 ? null : discount,
        'freezeDaysAllowed': freezeDaysAllowed,
        'freezeTimesAllowed': freezeTimesAllowed,
        'freezes': freezes.isEmpty ? null : freezes.map((f) => f.toMap()).toList(),
        'invoiceId': invoiceId,
        'trainerId': trainerId,
        'cancelled': cancelled ? true : null,
        'cancelledAt': cancelledAt?.toIso8601String(),
        'cancelReason': cancelReason,
        'notes': notes,
        'imported': imported ? true : null,
        'createdAt': createdAt.toIso8601String(),
        'createdBy': createdBy,
      });

  factory Subscription.fromMap(Map<String, Object?> m) => Subscription(
        id: asStr(m['id']),
        memberId: asStr(m['memberId']),
        planId: asStr(m['planId']),
        planName: asStr(m['planName']),
        kind: planKindFrom(m['kind']),
        start: parseDay(asStr(m['start'])),
        end: parseDay(asStr(m['end'])),
        visitsTotal: asIntOrNull(m['visitsTotal']),
        visitsUsed: asInt(m['visitsUsed']),
        price: asDouble(m['price']),
        discount: asDouble(m['discount']),
        freezeDaysAllowed: asInt(m['freezeDaysAllowed']),
        freezeTimesAllowed: asInt(m['freezeTimesAllowed']),
        freezes: asMapList(m['freezes']).map(Freeze.fromMap).toList(),
        invoiceId: asStrOrNull(m['invoiceId']),
        trainerId: asStrOrNull(m['trainerId']),
        cancelled: asBool(m['cancelled']),
        cancelledAt: asTime(m['cancelledAt']),
        cancelReason: asStrOrNull(m['cancelReason']),
        notes: asStrOrNull(m['notes']),
        imported: asBool(m['imported']),
        createdAt: asTime(m['createdAt']) ?? DateTime.now(),
        createdBy: asStrOrNull(m['createdBy']),
      );
}
