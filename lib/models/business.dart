import '../core/dates.dart';
import 'base.dart';
import 'member.dart';

enum Role { owner, manager, reception, trainer }

Role roleFrom(Object? v) => Role.values.firstWhere((r) => r.name == v, orElse: () => Role.reception);

/// صلاحيات كل دور
enum Perm {
  members, // إضافة وتعديل الأعضاء
  checkin,
  sell, // بيع اشتراكات ومنتجات وتحصيل
  discount, // خصم أعلى من الحد المسموح
  refund, // استرداد وإلغاء فواتير
  reports,
  expenses,
  messages,
  campaigns, // رسائل جماعية
  plans, // الباقات والأسعار
  classes,
  staff,
  settings,
  override, // السماح بالدخول رغم المانع
  deleteData,
}

const rolePerms = <Role, Set<Perm>>{
  Role.owner: {...Perm.values},
  Role.manager: {
    Perm.members, Perm.checkin, Perm.sell, Perm.discount, Perm.refund, Perm.reports, Perm.expenses,
    Perm.messages, Perm.campaigns, Perm.plans, Perm.classes, Perm.override,
  },
  Role.reception: {Perm.members, Perm.checkin, Perm.sell, Perm.messages, Perm.classes},
  Role.trainer: {Perm.checkin, Perm.classes},
};

/// الموظفون: المستخدمون (بالرقم السري) والمدربون
class Staff implements Entity {
  @override
  final String id;
  String name;
  Role role;
  String? phone;
  String? pinHash; // الرقم السري مشفّراً (SHA-256 مع ملح)
  double commissionPct; // عمولة المدرب من مبيعات التدريب الشخصي
  double sessionRate; // أجر المدرب عن كل جلسة تدريب شخصي
  bool isTrainer;
  bool active;
  int colorValue;

  Staff({
    required this.id,
    required this.name,
    this.role = Role.reception,
    this.phone,
    this.pinHash,
    this.commissionPct = 0,
    this.sessionRate = 0,
    this.isTrainer = false,
    this.active = true,
    this.colorValue = 0xFF7E57C2,
  });

  bool can(Perm p) => rolePerms[role]!.contains(p);

  @override
  Map<String, Object?> toMap() => compact({
        'id': id,
        'name': name,
        'role': role.name,
        'phone': phone,
        'pinHash': pinHash,
        'commissionPct': commissionPct == 0 ? null : commissionPct,
        'sessionRate': sessionRate == 0 ? null : sessionRate,
        'isTrainer': isTrainer ? true : null,
        'active': active,
        'color': colorValue,
      });

  factory Staff.fromMap(Map<String, Object?> m) => Staff(
        id: asStr(m['id']),
        name: asStr(m['name']),
        role: roleFrom(m['role']),
        phone: asStrOrNull(m['phone']),
        pinHash: asStrOrNull(m['pinHash']),
        commissionPct: asDouble(m['commissionPct']),
        sessionRate: asDouble(m['sessionRate']),
        isTrainer: asBool(m['isTrainer']),
        active: asBool(m['active'], true),
        colorValue: asInt(m['color'], 0xFF7E57C2),
      );
}

/// موعد أسبوعي ثابت للحصة
class ClassSlot {
  int weekday; // 1..7 كما في DateTime
  int start; // بالدقائق من منتصف الليل

  ClassSlot(this.weekday, this.start);

  Map<String, Object?> toMap() => {'weekday': weekday, 'start': start};

  factory ClassSlot.fromMap(Map<String, Object?> m) => ClassSlot(asInt(m['weekday']), asInt(m['start']));
}

/// حصة جماعية (زومبا، كروس فت، سباحة...) بمواعيد أسبوعية ثابتة
class GymClass implements Entity {
  @override
  final String id;
  String name;
  String? trainerId;
  int capacity;
  int durationMin;
  Gender? gender;
  String? room;
  List<ClassSlot> slots;
  int colorValue;
  bool active;
  bool membersOnly; // لمن لديه اشتراك فعّال فقط

  GymClass({
    required this.id,
    required this.name,
    this.trainerId,
    this.capacity = 20,
    this.durationMin = 60,
    this.gender,
    this.room,
    List<ClassSlot>? slots,
    this.colorValue = 0xFFEF6C00,
    this.active = true,
    this.membersOnly = true,
  }) : slots = slots ?? [];

  @override
  Map<String, Object?> toMap() => compact({
        'id': id,
        'name': name,
        'trainerId': trainerId,
        'capacity': capacity,
        'durationMin': durationMin,
        'gender': genderCode(gender),
        'room': room,
        'slots': slots.map((s) => s.toMap()).toList(),
        'color': colorValue,
        'active': active,
        'membersOnly': membersOnly,
      });

  factory GymClass.fromMap(Map<String, Object?> m) => GymClass(
        id: asStr(m['id']),
        name: asStr(m['name']),
        trainerId: asStrOrNull(m['trainerId']),
        capacity: asInt(m['capacity'], 20),
        durationMin: asInt(m['durationMin'], 60),
        gender: genderFrom(m['gender']),
        room: asStrOrNull(m['room']),
        slots: asMapList(m['slots']).map(ClassSlot.fromMap).toList(),
        colorValue: asInt(m['color'], 0xFFEF6C00),
        active: asBool(m['active'], true),
        membersOnly: asBool(m['membersOnly'], true),
      );
}

enum BookingStatus { booked, waitlist, attended, noShow, cancelled }

/// حجز عضو في موعد حصة محدد
class Booking implements Entity {
  @override
  final String id;
  final String classId;
  final DateTime sessionStart; // تاريخ ووقت الموعد
  final String memberId;
  BookingStatus status;
  final DateTime createdAt;

  Booking({
    required this.id,
    required this.classId,
    required this.sessionStart,
    required this.memberId,
    this.status = BookingStatus.booked,
    required this.createdAt,
  });

  String get sessionKey => sessionKeyOf(classId, sessionStart);

  static String sessionKeyOf(String classId, DateTime start) => '$classId|${timeKey(start)}';

  @override
  Map<String, Object?> toMap() => {
        'id': id,
        'classId': classId,
        'sessionStart': sessionStart.toIso8601String(),
        'memberId': memberId,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Booking.fromMap(Map<String, Object?> m) => Booking(
        id: asStr(m['id']),
        classId: asStr(m['classId']),
        sessionStart: asTime(m['sessionStart']) ?? DateTime.now(),
        memberId: asStr(m['memberId']),
        status: BookingStatus.values.firstWhere((s) => s.name == m['status'], orElse: () => BookingStatus.booked),
        createdAt: asTime(m['createdAt']) ?? DateTime.now(),
      );
}

enum LeadStatus { fresh, contacted, trial, won, lost }

/// عميل محتمل: سأل عن الأسعار أو جاء لحصة تجربة
class Lead implements Entity {
  @override
  final String id;
  String name;
  String phone;
  Gender? gender;
  String? source;
  String? interestPlanId;
  LeadStatus status;
  DateTime? followUp;
  DateTime? trialDate;
  String? notes;
  String? memberId; // بعد التحويل لعضو
  String? assignedTo;
  final DateTime createdAt;

  Lead({
    required this.id,
    required this.name,
    required this.phone,
    this.gender,
    this.source,
    this.interestPlanId,
    this.status = LeadStatus.fresh,
    this.followUp,
    this.trialDate,
    this.notes,
    this.memberId,
    this.assignedTo,
    required this.createdAt,
  });

  @override
  Map<String, Object?> toMap() => compact({
        'id': id,
        'name': name,
        'phone': phone,
        'gender': genderCode(gender),
        'source': source,
        'interestPlanId': interestPlanId,
        'status': status.name,
        'followUp': followUp == null ? null : dayKey(followUp!),
        'trialDate': trialDate == null ? null : dayKey(trialDate!),
        'notes': notes,
        'memberId': memberId,
        'assignedTo': assignedTo,
        'createdAt': createdAt.toIso8601String(),
      });

  factory Lead.fromMap(Map<String, Object?> m) => Lead(
        id: asStr(m['id']),
        name: asStr(m['name']),
        phone: asStr(m['phone']),
        gender: genderFrom(m['gender']),
        source: asStrOrNull(m['source']),
        interestPlanId: asStrOrNull(m['interestPlanId']),
        status: LeadStatus.values.firstWhere((s) => s.name == m['status'], orElse: () => LeadStatus.fresh),
        followUp: tryParseDay(asStrOrNull(m['followUp'])),
        trialDate: tryParseDay(asStrOrNull(m['trialDate'])),
        notes: asStrOrNull(m['notes']),
        memberId: asStrOrNull(m['memberId']),
        assignedTo: asStrOrNull(m['assignedTo']),
        createdAt: asTime(m['createdAt']) ?? DateTime.now(),
      );
}

/// منتج في متجر النادي (مياه، مكملات، ملابس...)
class Product implements Entity {
  @override
  final String id;
  String name;
  String? barcode;
  String? category;
  double price;
  double cost;
  double stock;
  double minStock;
  bool trackStock;
  bool active;

  Product({
    required this.id,
    required this.name,
    this.barcode,
    this.category,
    this.price = 0,
    this.cost = 0,
    this.stock = 0,
    this.minStock = 0,
    this.trackStock = true,
    this.active = true,
  });

  bool get lowStock => trackStock && stock <= minStock;

  @override
  Map<String, Object?> toMap() => compact({
        'id': id,
        'name': name,
        'barcode': barcode,
        'category': category,
        'price': price,
        'cost': cost,
        'stock': stock,
        'minStock': minStock,
        'trackStock': trackStock,
        'active': active,
      });

  factory Product.fromMap(Map<String, Object?> m) => Product(
        id: asStr(m['id']),
        name: asStr(m['name']),
        barcode: asStrOrNull(m['barcode']),
        category: asStrOrNull(m['category']),
        price: asDouble(m['price']),
        cost: asDouble(m['cost']),
        stock: asDouble(m['stock']),
        minStock: asDouble(m['minStock']),
        trackStock: asBool(m['trackStock'], true),
        active: asBool(m['active'], true),
      );
}

class Expense implements Entity {
  @override
  final String id;
  DateTime date;
  String category;
  double amount;
  String? note;
  String? by;

  Expense({required this.id, required this.date, required this.category, required this.amount, this.note, this.by});

  @override
  Map<String, Object?> toMap() => compact({
        'id': id,
        'date': dayKey(date),
        'category': category,
        'amount': amount,
        'note': note,
        'by': by,
      });

  factory Expense.fromMap(Map<String, Object?> m) => Expense(
        id: asStr(m['id']),
        date: parseDay(asStr(m['date'])),
        category: asStr(m['category']),
        amount: asDouble(m['amount']),
        note: asStrOrNull(m['note']),
        by: asStrOrNull(m['by']),
      );
}

/// كوبون خصم (عروض رمضان، الطلاب، الشركات...)
class Coupon implements Entity {
  @override
  final String id;
  String code;
  bool percent;
  double value;
  DateTime? validUntil;
  int maxUses; // 0 = بلا حد
  int uses;
  List<String> planIds; // فارغ = كل الباقات
  bool active;

  Coupon({
    required this.id,
    required this.code,
    this.percent = true,
    required this.value,
    this.validUntil,
    this.maxUses = 0,
    this.uses = 0,
    List<String>? planIds,
    this.active = true,
  }) : planIds = planIds ?? [];

  bool usableOn(DateTime day, String planId) =>
      active &&
      (validUntil == null || !dateOnly(day).isAfter(validUntil!)) &&
      (maxUses == 0 || uses < maxUses) &&
      (planIds.isEmpty || planIds.contains(planId));

  double discountFor(double price) {
    final d = percent ? price * value / 100 : value;
    return d > price ? price : d;
  }

  @override
  Map<String, Object?> toMap() => compact({
        'id': id,
        'code': code,
        'percent': percent,
        'value': value,
        'validUntil': validUntil == null ? null : dayKey(validUntil!),
        'maxUses': maxUses,
        'uses': uses,
        'planIds': planIds.isEmpty ? null : planIds,
        'active': active,
      });

  factory Coupon.fromMap(Map<String, Object?> m) => Coupon(
        id: asStr(m['id']),
        code: asStr(m['code']),
        percent: asBool(m['percent'], true),
        value: asDouble(m['value']),
        validUntil: tryParseDay(asStrOrNull(m['validUntil'])),
        maxUses: asInt(m['maxUses']),
        uses: asInt(m['uses']),
        planIds: asStrList(m['planIds']),
        active: asBool(m['active'], true),
      );
}

/// عرض على الباقات: يُطبق تلقائياً عند البيع خلال مدته (بدون كوبون)
/// type: percent (خصم %) / fixed (خصم مبلغ) / price (سعر خاص)؛ ويمكن إضافة أيام مجانية.
class Offer implements Entity {
  @override
  final String id;
  String name;
  String type;
  double value;
  int bonusDays;
  List<String> planIds; // فارغ = كل الباقات
  DateTime? start;
  DateTime? end;
  bool newMembersOnly;
  bool active;

  Offer({
    required this.id,
    required this.name,
    this.type = 'percent',
    this.value = 0,
    this.bonusDays = 0,
    List<String>? planIds,
    this.start,
    this.end,
    this.newMembersOnly = false,
    this.active = true,
  }) : planIds = planIds ?? [];

  bool validOn(DateTime day, String planId, {required bool newMember}) =>
      active &&
      (start == null || !dateOnly(day).isBefore(start!)) &&
      (end == null || !dateOnly(day).isAfter(end!)) &&
      (planIds.isEmpty || planIds.contains(planId)) &&
      (!newMembersOnly || newMember);

  /// قيمة الخصم على سعر الباقة
  double discountFor(double price) {
    final d = switch (type) {
      'percent' => price * value / 100,
      'fixed' => value,
      'price' => price - value,
      _ => 0.0,
    };
    return d < 0 ? 0 : (d > price ? price : d);
  }

  @override
  Map<String, Object?> toMap() => compact({
        'id': id,
        'name': name,
        'type': type,
        'value': value,
        'bonusDays': bonusDays == 0 ? null : bonusDays,
        'planIds': planIds.isEmpty ? null : planIds,
        'start': start == null ? null : dayKey(start!),
        'end': end == null ? null : dayKey(end!),
        'newMembersOnly': newMembersOnly ? true : null,
        'active': active,
      });

  factory Offer.fromMap(Map<String, Object?> m) => Offer(
        id: asStr(m['id']),
        name: asStr(m['name']),
        type: asStr(m['type'], 'percent'),
        value: asDouble(m['value']),
        bonusDays: asInt(m['bonusDays']),
        planIds: asStrList(m['planIds']),
        start: tryParseDay(asStrOrNull(m['start'])),
        end: tryParseDay(asStrOrNull(m['end'])),
        newMembersOnly: asBool(m['newMembersOnly']),
        active: asBool(m['active'], true),
      );
}
