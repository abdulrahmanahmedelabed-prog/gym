import '../core/dates.dart';
import 'base.dart';

/// دور الموظف يحدد الصلاحيات الافتراضية، ويمكن تعديلها لكل موظف.
enum StaffRole { owner, manager, reception, trainer, accountant, cleaner, other }

StaffRole staffRoleFrom(Object? v) =>
    StaffRole.values.firstWhere((r) => r.name == v, orElse: () => StaffRole.reception);

/// الصلاحيات: كل عملية حساسة تتحقق من صلاحية واحدة من هذه.
enum Perm {
  members,
  sell, // بيع اشتراك أو منتج وتحصيل دفعة
  discount,
  voidInvoice,
  refund,
  overrideCheckin, // السماح بالدخول رغم وجود مانع
  plans,
  classes,
  leads,
  shop,
  expenses,
  reports,
  messages,
  staff,
  settings,
}

/// الصلاحيات الافتراضية لكل دور
const Map<StaffRole, Set<Perm>> defaultPerms = {
  StaffRole.owner: {...Perm.values},
  StaffRole.manager: {
    Perm.members, Perm.sell, Perm.discount, Perm.voidInvoice, Perm.refund, Perm.overrideCheckin,
    Perm.plans, Perm.classes, Perm.leads, Perm.shop, Perm.expenses, Perm.reports, Perm.messages,
  },
  StaffRole.reception: {Perm.members, Perm.sell, Perm.leads, Perm.shop, Perm.messages},
  StaffRole.trainer: {Perm.classes},
  StaffRole.accountant: {Perm.expenses, Perm.reports},
  StaffRole.cleaner: {},
  StaffRole.other: {},
};

/// طريقة حساب الراتب
enum PayType { monthly, daily, hourly, none }

PayType payTypeFrom(Object? v) =>
    PayType.values.firstWhere((t) => t.name == v, orElse: () => PayType.monthly);

class Staff implements Entity {
  @override
  final String id;
  String name;
  String phone;
  StaffRole role;
  String? pinHash; // رمز الدخول للتطبيق (مُشفّر، لا يُخزن الرقم نفسه)
  Set<Perm>? perms; // null = صلاحيات الدور الافتراضية
  PayType payType;
  double salary; // شهري أو يومي أو بالساعة حسب payType
  double commissionRate; // نسبة من مبيعات الموظف (0.05 = 5%)
  DateTime? hireDate;
  String? nationalId;
  String? photo;
  String? notes;
  bool active;
  final DateTime createdAt;

  Staff({
    required this.id,
    required this.name,
    required this.phone,
    required this.role,
    required this.createdAt,
    this.pinHash,
    this.perms,
    this.payType = PayType.monthly,
    this.salary = 0,
    this.commissionRate = 0,
    this.hireDate,
    this.nationalId,
    this.photo,
    this.notes,
    this.active = true,
  });

  Set<Perm> get effectivePerms => perms ?? defaultPerms[role] ?? const {};

  bool can(Perm p) => active && (role == StaffRole.owner || effectivePerms.contains(p));

  @override
  Map<String, Object?> toMap() => compact({
        'id': id,
        'name': name,
        'phone': phone,
        'role': role.name,
        'pinHash': pinHash,
        'perms': perms?.map((p) => p.name).toList(),
        'payType': payType.name,
        'salary': salary == 0 ? null : salary,
        'commissionRate': commissionRate == 0 ? null : commissionRate,
        'hireDate': hireDate == null ? null : dayKey(hireDate!),
        'nationalId': nationalId,
        'photo': photo,
        'notes': notes,
        'active': active,
        'createdAt': createdAt.toIso8601String(),
      });

  factory Staff.fromMap(Map<String, Object?> m) => Staff(
        id: asStr(m['id']),
        name: asStr(m['name']),
        phone: asStr(m['phone']),
        role: staffRoleFrom(m['role']),
        pinHash: asStrOrNull(m['pinHash']),
        perms: m['perms'] is List
            ? asStrList(m['perms'])
                .map((s) => Perm.values.where((p) => p.name == s).firstOrNull)
                .whereType<Perm>()
                .toSet()
            : null,
        payType: payTypeFrom(m['payType']),
        salary: asDouble(m['salary']),
        commissionRate: asDouble(m['commissionRate']),
        hireDate: tryParseDay(asStrOrNull(m['hireDate'])),
        nationalId: asStrOrNull(m['nationalId']),
        photo: asStrOrNull(m['photo']),
        notes: asStrOrNull(m['notes']),
        active: asBool(m['active'], true),
        createdAt: asTime(m['createdAt']) ?? DateTime.now(),
      );
}

/// حضور وانصراف الموظف (وردية)
class StaffShift implements Entity {
  @override
  final String id;
  final String staffId;
  DateTime clockIn;
  DateTime? clockOut;
  String? note;

  StaffShift({required this.id, required this.staffId, required this.clockIn, this.clockOut, this.note});

  bool get open => clockOut == null;

  /// مدة الوردية بالدقائق (المفتوحة تُحسب حتى [now])
  int minutes([DateTime? now]) => (clockOut ?? now ?? DateTime.now()).difference(clockIn).inMinutes;

  @override
  Map<String, Object?> toMap() => compact({
        'id': id,
        'staffId': staffId,
        'clockIn': clockIn.toIso8601String(),
        'clockOut': clockOut?.toIso8601String(),
        'note': note,
      });

  factory StaffShift.fromMap(Map<String, Object?> m) => StaffShift(
        id: asStr(m['id']),
        staffId: asStr(m['staffId']),
        clockIn: asTime(m['clockIn']) ?? DateTime.now(),
        clockOut: asTime(m['clockOut']),
        note: asStrOrNull(m['note']),
      );
}
