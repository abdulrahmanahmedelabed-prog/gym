import 'base.dart';
import 'member.dart';

/// عمولة المدرب على التدريب الشخصي:
/// percent = نسبة من سعر الاشتراك، perSession = مبلغ ثابت عن كل جلسة منفذة
enum CommissionType { none, percent, perSession }

CommissionType commissionTypeFrom(Object? v) =>
    CommissionType.values.firstWhere((t) => t.name == v, orElse: () => CommissionType.none);

/// المدرب: ملف عام (يظهر للأعضاء) مرتبط اختيارياً بموظف في [staffId]
/// لأن بعض المدربين من خارج النادي (مستقلون) ولا يدخلون التطبيق.
class Trainer implements Entity {
  @override
  final String id;
  String? staffId;
  String name;
  String phone;
  Gender? gender;
  List<String> specialties; // كمال أجسام، لياقة، يوغا...
  String? bio;
  String? photo;
  CommissionType commissionType;
  double commissionValue; // 0.3 = 30% أو مبلغ الجلسة
  int colorValue; // لون المدرب في جدول الحصص
  bool active;
  final DateTime createdAt;

  Trainer({
    required this.id,
    required this.name,
    required this.phone,
    required this.createdAt,
    this.staffId,
    this.gender,
    List<String>? specialties,
    this.bio,
    this.photo,
    this.commissionType = CommissionType.none,
    this.commissionValue = 0,
    this.colorValue = 0xFF43A047,
    this.active = true,
  }) : specialties = specialties ?? [];

  @override
  Map<String, Object?> toMap() => compact({
        'id': id,
        'staffId': staffId,
        'name': name,
        'phone': phone,
        'gender': genderCode(gender),
        'specialties': specialties.isEmpty ? null : specialties,
        'bio': bio,
        'photo': photo,
        'commissionType': commissionType == CommissionType.none ? null : commissionType.name,
        'commissionValue': commissionValue == 0 ? null : commissionValue,
        'color': colorValue,
        'active': active,
        'createdAt': createdAt.toIso8601String(),
      });

  factory Trainer.fromMap(Map<String, Object?> m) => Trainer(
        id: asStr(m['id']),
        staffId: asStrOrNull(m['staffId']),
        name: asStr(m['name']),
        phone: asStr(m['phone']),
        gender: genderFrom(m['gender']),
        specialties: asStrList(m['specialties']),
        bio: asStrOrNull(m['bio']),
        photo: asStrOrNull(m['photo']),
        commissionType: commissionTypeFrom(m['commissionType']),
        commissionValue: asDouble(m['commissionValue']),
        colorValue: asInt(m['color'], 0xFF43A047),
        active: asBool(m['active'], true),
        createdAt: asTime(m['createdAt']) ?? DateTime.now(),
      );
}

enum PtStatus { scheduled, done, noShow, cancelled }

PtStatus ptStatusFrom(Object? v) =>
    PtStatus.values.firstWhere((s) => s.name == v, orElse: () => PtStatus.scheduled);

/// جلسة تدريب شخصي ضمن اشتراك من نوع pt.
/// الجلسة المنفذة أو التي غاب عنها العضو تُخصم من رصيد الاشتراك وتُحتسب عمولتها للمدرب.
class PtSession implements Entity {
  @override
  final String id;
  final String subscriptionId;
  final String memberId;
  String trainerId;
  DateTime time;
  int durationMinutes;
  PtStatus status;
  String? notes;
  String? by;

  PtSession({
    required this.id,
    required this.subscriptionId,
    required this.memberId,
    required this.trainerId,
    required this.time,
    this.durationMinutes = 60,
    this.status = PtStatus.scheduled,
    this.notes,
    this.by,
  });

  /// هل تُخصم من رصيد الجلسات
  bool get consumes => status == PtStatus.done || status == PtStatus.noShow;

  @override
  Map<String, Object?> toMap() => compact({
        'id': id,
        'subscriptionId': subscriptionId,
        'memberId': memberId,
        'trainerId': trainerId,
        'time': time.toIso8601String(),
        'durationMinutes': durationMinutes,
        'status': status.name,
        'notes': notes,
        'by': by,
      });

  factory PtSession.fromMap(Map<String, Object?> m) => PtSession(
        id: asStr(m['id']),
        subscriptionId: asStr(m['subscriptionId']),
        memberId: asStr(m['memberId']),
        trainerId: asStr(m['trainerId']),
        time: asTime(m['time']) ?? DateTime.now(),
        durationMinutes: asInt(m['durationMinutes'], 60),
        status: ptStatusFrom(m['status']),
        notes: asStrOrNull(m['notes']),
        by: asStrOrNull(m['by']),
      );
}
