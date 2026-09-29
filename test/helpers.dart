import 'package:nadi_gym/core/dates.dart';
import 'package:nadi_gym/core/ids.dart';
import 'package:nadi_gym/data/gym_data.dart';
import 'package:nadi_gym/models/member.dart';
import 'package:nadi_gym/models/plan.dart';
import 'package:nadi_gym/services/license.dart';
import 'package:sembast/sembast_memory.dart';

/// ساعة قابلة للتحكم في الاختبارات
class FakeClock {
  DateTime now;
  FakeClock(this.now);
  DateTime call() => now;
  void advance({int days = 0, int hours = 0, int minutes = 0}) =>
      now = now.add(Duration(days: days, hours: hours, minutes: minutes));
  void setDay(DateTime d, [int hour = 12]) => now = DateTime(d.year, d.month, d.day, hour);
}

var _dbCounter = 0;

/// نادٍ للاختبار. الباقة Pro افتراضياً حتى لا يتأثر اختبار المنطق بانتهاء التجربة؛ [realLicense] لاختبار الترخيص نفسه.
Future<(GymData, FakeClock)> newGym([DateTime? start, bool realLicense = false]) async {
  final clock = FakeClock(start ?? DateTime(2026, 9, 29, 12));
  final db = await databaseFactoryMemory.openDatabase('test_${_dbCounter++}.db');
  final g = await GymData.open(db, clock: clock.call);
  if (!realLicense) g.license.debugTier = Tier.pro;
  return (g, clock);
}

Future<Plan> addPlan(GymData g,
    {String name = 'شهري',
    PlanKind kind = PlanKind.time,
    int value = 1,
    DurationUnit unit = DurationUnit.month,
    double price = 600,
    int? visits,
    int freezeDays = 10,
    int freezeTimes = 2,
    double fee = 0,
    Gender? gender,
    int? from,
    int? to,
    int dailyLimit = 1}) async {
  final p = Plan(
    id: newId(),
    name: name,
    kind: kind,
    durationValue: value,
    durationUnit: unit,
    price: price,
    visits: visits,
    freezeDays: freezeDays,
    freezeTimes: freezeTimes,
    registrationFee: fee,
    gender: gender,
    accessFrom: from,
    accessTo: to,
    dailyLimit: dailyLimit,
  );
  await g.put(p);
  return p;
}
