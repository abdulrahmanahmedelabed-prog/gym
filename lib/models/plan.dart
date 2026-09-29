import '../core/dates.dart';
import 'base.dart';
import 'member.dart';

/// نوع الباقة:
/// time   = مدة (شهر، 3 أشهر...) دخول غير محدود أو بحد أقصى للزيارات
/// visits = عدد حصص/زيارات خلال مدة صلاحية
/// pt     = تدريب شخصي: عدد جلسات مع مدرب محدد
enum PlanKind { time, visits, pt }

PlanKind planKindFrom(Object? v) =>
    PlanKind.values.firstWhere((k) => k.name == v, orElse: () => PlanKind.time);

class Plan implements Entity {
  @override
  final String id;
  String name;
  PlanKind kind;
  int durationValue;
  DurationUnit durationUnit;
  int? visits; // null = غير محدود
  double price;
  double registrationFee; // رسوم تسجيل تُضاف للعضو الجديد فقط
  int freezeDays; // مجموع أيام التجميد المسموح
  int freezeTimes; // عدد مرات التجميد المسموح
  Gender? gender; // باقة للرجال فقط أو للنساء فقط
  int? accessFrom; // بداية ساعات الدخول بالدقائق من منتصف الليل (باقات الأوقات الهادئة)
  int? accessTo;
  List<int> weekdays; // أيام الدخول المسموحة (فارغة = كل الأيام)
  int dailyLimit; // عدد مرات الدخول في اليوم (0 = بلا حد)
  bool includesClasses;
  int colorValue;
  bool active;
  String? description;
  int sort;

  Plan({
    required this.id,
    required this.name,
    this.kind = PlanKind.time,
    this.durationValue = 1,
    this.durationUnit = DurationUnit.month,
    this.visits,
    this.price = 0,
    this.registrationFee = 0,
    this.freezeDays = 0,
    this.freezeTimes = 0,
    this.gender,
    this.accessFrom,
    this.accessTo,
    List<int>? weekdays,
    this.dailyLimit = 1,
    this.includesClasses = false,
    this.colorValue = 0xFF1E88E5,
    this.active = true,
    this.description,
    this.sort = 0,
  }) : weekdays = weekdays ?? [];

  bool get hasTimeWindow => accessFrom != null && accessTo != null;

  bool allowsTime(DateTime t) {
    if (weekdays.isNotEmpty && !weekdays.contains(t.weekday)) return false;
    if (!hasTimeWindow) return true;
    final m = minutesOfDay(t);
    if (accessFrom! <= accessTo!) return m >= accessFrom! && m <= accessTo!;
    return m >= accessFrom! || m <= accessTo!; // نافذة تتجاوز منتصف الليل
  }

  @override
  Map<String, Object?> toMap() => compact({
        'id': id,
        'name': name,
        'kind': kind.name,
        'durationValue': durationValue,
        'durationUnit': durationUnit.name,
        'visits': visits,
        'price': price,
        'registrationFee': registrationFee == 0 ? null : registrationFee,
        'freezeDays': freezeDays,
        'freezeTimes': freezeTimes,
        'gender': genderCode(gender),
        'accessFrom': accessFrom,
        'accessTo': accessTo,
        'weekdays': weekdays.isEmpty ? null : weekdays,
        'dailyLimit': dailyLimit,
        'includesClasses': includesClasses ? true : null,
        'color': colorValue,
        'active': active,
        'description': description,
        'sort': sort,
      });

  factory Plan.fromMap(Map<String, Object?> m) => Plan(
        id: asStr(m['id']),
        name: asStr(m['name']),
        kind: planKindFrom(m['kind']),
        durationValue: asInt(m['durationValue'], 1),
        durationUnit: durationUnitFrom(asStrOrNull(m['durationUnit'])),
        visits: asIntOrNull(m['visits']),
        price: asDouble(m['price']),
        registrationFee: asDouble(m['registrationFee']),
        freezeDays: asInt(m['freezeDays']),
        freezeTimes: asInt(m['freezeTimes']),
        gender: genderFrom(m['gender']),
        accessFrom: asIntOrNull(m['accessFrom']),
        accessTo: asIntOrNull(m['accessTo']),
        weekdays: asIntList(m['weekdays']),
        dailyLimit: asInt(m['dailyLimit'], 1),
        includesClasses: asBool(m['includesClasses']),
        colorValue: asInt(m['color'], 0xFF1E88E5),
        active: asBool(m['active'], true),
        description: asStrOrNull(m['description']),
        sort: asInt(m['sort']),
      );
}
