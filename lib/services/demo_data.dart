import 'dart:math';

import '../core/dates.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../data/gym_data.dart';
import '../models/activity.dart';
import '../models/base.dart';
import '../models/billing.dart';
import '../models/business.dart';
import '../models/member.dart';
import '../models/plan.dart';
import '../models/settings.dart';
import '../models/subscription.dart';
import 'data_tools.dart';

/// بيانات تجريبية واقعية: نادٍ بعمر سنة (أعضاء، تجديدات، أقساط، حضور، حصص، متجر، مصروفات).
/// تُستخدم لتجربة التطبيق وللصور التوضيحية.
class DemoData {
  final GymData d;
  final Random rnd;
  DemoData(this.d, {int seed = 7}) : rnd = Random(seed);

  static const _male = [
    'أحمد', 'محمد', 'محمود', 'عمر', 'خالد', 'يوسف', 'علي', 'حسن', 'إبراهيم', 'مصطفى', 'كريم', 'طارق', 'سامي', 'ياسر',
    'عبدالله', 'فهد', 'سعد', 'ماجد', 'زياد', 'حمزة', 'أنس', 'مازن', 'باسل', 'رامي', 'وليد', 'هشام', 'نادر', 'سيف',
  ];
  static const _female = [
    'سارة', 'نور', 'مريم', 'فاطمة', 'ريم', 'هبة', 'دينا', 'ليلى', 'آية', 'منى', 'رنا', 'جنى', 'لمى', 'سلمى', 'هالة',
    'ياسمين', 'شهد', 'رغد', 'دانة', 'نهى',
  ];
  static const _family = [
    'السيد', 'عبدالرحمن', 'الشريف', 'المصري', 'حسين', 'العلي', 'سليمان', 'الخطيب', 'منصور', 'عثمان', 'الزهراني',
    'القحطاني', 'الحربي', 'فوزي', 'عادل', 'جمال', 'الأنصاري', 'رشيد', 'ناصر', 'البنا',
  ];

  T pick<T>(List<T> l) => l[rnd.nextInt(l.length)];

  String phone() => '010${(10000000 + rnd.nextInt(89999999))}';

  Future<void> generate({int members = 140}) async {
    final now = d.now();
    final today = dateOnly(now);
    final s = d.settings
      ..gymName = 'نادي القوة الرياضي'
      ..gymPhone = '01001234567'
      ..address = 'شارع التسعين، القاهرة الجديدة'
      ..currencyCode = 'EGP'
      ..currencySymbol = 'ج.م'
      ..countryCode = '20'
      ..walletInfo = 'للدفع: انستاباي power.gym@instapay أو فودافون كاش 01001234567'
      ..genderWindows = [GenderWindow(gender: 'f', weekdays: [6, 7, 1, 2, 3], from: 10 * 60, to: 14 * 60)]
      ..onboarded = true
      ..set('genderStrict', false);
    d.applySettings();

    final save = <Entity>[];
    Plan plan(String name, PlanKind k, int dv, DurationUnit u, double price,
        {int? visits, int freezeDays = 0, int freezeTimes = 0, int color = 0xFF1E88E5, int sort = 0, int? from, int? to, double fee = 0}) {
      final p = Plan(
          id: newId(),
          name: name,
          kind: k,
          durationValue: dv,
          durationUnit: u,
          price: price,
          visits: visits,
          freezeDays: freezeDays,
          freezeTimes: freezeTimes,
          colorValue: color,
          sort: sort,
          accessFrom: from,
          accessTo: to,
          registrationFee: fee);
      save.add(p);
      return p;
    }

    final monthly = plan('شهري', PlanKind.time, 1, DurationUnit.month, 600, freezeDays: 7, freezeTimes: 1, color: 0xFF1E88E5, sort: 1, fee: 100);
    final quarter = plan('3 أشهر', PlanKind.time, 3, DurationUnit.month, 1500, freezeDays: 15, freezeTimes: 2, color: 0xFF43A047, sort: 2, fee: 100);
    final half = plan('6 أشهر', PlanKind.time, 6, DurationUnit.month, 2700, freezeDays: 30, freezeTimes: 2, color: 0xFFFB8C00, sort: 3);
    final year = plan('سنوي', PlanKind.time, 1, DurationUnit.year, 4800, freezeDays: 60, freezeTimes: 3, color: 0xFFE53935, sort: 4);
    final twelve = plan('12 حصة', PlanKind.visits, 2, DurationUnit.month, 450, visits: 12, color: 0xFF8E24AA, sort: 5);
    final morning = plan('الصباحي (6ص-2م)', PlanKind.time, 1, DurationUnit.month, 400, color: 0xFF00ACC1, sort: 6, from: 6 * 60, to: 14 * 60);
    final pt8 = plan('تدريب شخصي 8 جلسات', PlanKind.pt, 1, DurationUnit.month, 1600, visits: 8, color: 0xFF6D4C41, sort: 7);
    plan('يوم واحد', PlanKind.time, 1, DurationUnit.day, 80, color: 0xFF757575, sort: 8);
    final plans = [monthly, monthly, monthly, quarter, quarter, half, year, twelve, morning];

    final owner = Staff(id: newId(), name: 'المدير العام', role: Role.owner);
    final rec = Staff(id: newId(), name: 'منى (استقبال)', role: Role.reception);
    rec.pinHash = hashPin('1234', rec.id);
    final t1 = Staff(id: newId(), name: 'كابتن كريم', role: Role.trainer, isTrainer: true, commissionPct: 30, sessionRate: 50, colorValue: 0xFF5E35B1);
    final t2 = Staff(id: newId(), name: 'كابتن هبة', role: Role.trainer, isTrainer: true, commissionPct: 30, sessionRate: 50, colorValue: 0xFFD81B60);
    owner.pinHash = hashPin('0000', owner.id);
    save.addAll([owner, rec, t1, t2]);

    final classes = [
      GymClass(id: newId(), name: 'زومبا (سيدات)', trainerId: t2.id, capacity: 15, gender: Gender.female, colorValue: 0xFFD81B60,
          slots: [ClassSlot(6, 11 * 60), ClassSlot(1, 11 * 60), ClassSlot(3, 11 * 60)]),
      GymClass(id: newId(), name: 'كروس فت', trainerId: t1.id, capacity: 12, colorValue: 0xFFEF6C00,
          slots: [ClassSlot(7, 19 * 60), ClassSlot(2, 19 * 60), ClassSlot(4, 19 * 60)]),
      GymClass(id: newId(), name: 'سبينينج', trainerId: t1.id, capacity: 10, colorValue: 0xFF1E88E5,
          slots: [ClassSlot(6, 20 * 60), ClassSlot(1, 20 * 60)]),
      GymClass(id: newId(), name: 'يوجا', trainerId: t2.id, capacity: 14, durationMin: 50, colorValue: 0xFF43A047,
          slots: [ClassSlot(5, 10 * 60), ClassSlot(3, 18 * 60)]),
    ];
    save.addAll(classes);

    final products = [
      Product(id: newId(), name: 'مياه معدنية', category: 'مشروبات', price: 10, cost: 5, stock: 180, minStock: 40),
      Product(id: newId(), name: 'مشروب طاقة', category: 'مشروبات', price: 35, cost: 22, stock: 60, minStock: 20),
      Product(id: newId(), name: 'بروتين بار', category: 'مكملات', price: 45, cost: 28, stock: 14, minStock: 15),
      Product(id: newId(), name: 'واي بروتين 2 كجم', category: 'مكملات', price: 2200, cost: 1800, stock: 6, minStock: 2),
      Product(id: newId(), name: 'منشفة النادي', category: 'ملابس', price: 120, cost: 60, stock: 25, minStock: 5),
      Product(id: newId(), name: 'قفازات تمرين', category: 'ملابس', price: 180, cost: 100, stock: 12, minStock: 4),
    ];
    save.addAll(products);
    save.add(Coupon(id: newId(), code: 'RAMADAN20', value: 20, validUntil: addDays(today, 20)));
    save.add(Coupon(id: newId(), code: 'STUDENT', percent: false, value: 100));

    final invoices = <Invoice>[];
    final payments = <Payment>[];
    final subs = <Subscription>[];
    final checkins = <Checkin>[];
    final mems = <Member>[];

    DateTime at(DateTime day, int hour, [int minute = 0]) => DateTime(day.year, day.month, day.day, hour, minute);

    Invoice newInv(Member m, DateTime date, List<InvoiceItem> items, {double discount = 0}) {
      final inv = Invoice(
          id: newId(), number: '', memberId: m.id, date: date, items: items, discount: discount, taxRate: 0, createdBy: rec.name);
      invoices.add(inv);
      return inv;
    }

    void pay(Invoice inv, double amount, DateTime date) {
      if (amount <= 0) return;
      final method = rnd.nextDouble() < 0.6
          ? PayMethod.cash
          : (rnd.nextDouble() < 0.5 ? PayMethod.card : (rnd.nextBool() ? PayMethod.wallet : PayMethod.transfer));
      payments.add(Payment(
          id: newId(),
          number: '',
          invoiceId: inv.id,
          memberId: inv.memberId,
          date: date,
          amount: roundMoney(amount),
          method: method,
          reference: method == PayMethod.cash ? null : '${100000 + rnd.nextInt(899999)}',
          by: rec.name));
      inv.paid = roundMoney(inv.paid + amount);
    }

    for (var i = 0; i < members; i++) {
      final female = rnd.nextDouble() < 0.38;
      final name = '${pick(female ? _female : _male)} ${pick(_male)} ${pick(_family)}';
      final joined = addDays(today, -rnd.nextInt(365));
      final m = Member(
        id: newId(),
        code: 1001 + i,
        name: name,
        phone: phone(),
        gender: female ? Gender.female : Gender.male,
        birthDate: DateTime(1975 + rnd.nextInt(30), 1 + rnd.nextInt(12), 1 + rnd.nextInt(28)),
        cardToken: newCardToken(),
        createdAt: at(joined, 9 + rnd.nextInt(12), rnd.nextInt(60)),
        source: pick(['فيسبوك', 'إنستجرام', 'صديق', 'مرّ من أمام النادي', 'جوجل', 'تيك توك']),
        medicalNotes: rnd.nextDouble() < 0.06 ? pick(['ضغط مرتفع', 'إصابة سابقة في الركبة', 'ربو خفيف', 'آلام أسفل الظهر']) : null,
        channel: rnd.nextDouble() < 0.9 ? Channel.whatsapp : Channel.sms,
      );
      if (i == 3 || i == 11) m.birthDate = DateTime(1995, today.month, today.day); // أعياد ميلاد اليوم
      if (i > 5 && rnd.nextDouble() < 0.15 && mems.isNotEmpty) m.referredBy = pick(mems).id;
      mems.add(m);

      // سلسلة اشتراكات منذ الانضمام
      var start = joined;
      var first = true;
      final loyal = rnd.nextDouble(); // احتمال التجديد
      while (!start.isAfter(today)) {
        var p = pick(plans);
        if (p == morning && female) p = monthly;
        if (i < 6 && start.isAfter(addDays(today, -60))) p = monthly;
        final end = periodEnd(start, p.durationValue, p.durationUnit);
        final sub = Subscription(
          id: newId(),
          memberId: m.id,
          planId: p.id,
          planName: p.name,
          kind: p.kind,
          start: start,
          end: end,
          visitsTotal: p.visits,
          price: p.price,
          freezeDaysAllowed: p.freezeDays,
          freezeTimesAllowed: p.freezeTimes,
          createdAt: at(start, 10 + rnd.nextInt(10), rnd.nextInt(60)),
          createdBy: rec.name,
        );
        final discount = rnd.nextDouble() < 0.15 ? roundMoney(p.price * 0.1) : 0.0;
        sub.discount = discount;
        final items = [
          InvoiceItem(kind: ItemKind.subscription, refId: sub.id, description: '${p.name} (${dayKey(start)} → ${dayKey(end)})', unitPrice: p.price),
          if (first && p.registrationFee > 0) InvoiceItem(kind: ItemKind.registration, description: 'رسوم التسجيل', unitPrice: p.registrationFee),
        ];
        final inv = newInv(m, sub.createdAt, items, discount: discount);
        sub.invoiceId = inv.id;
        // أقساط للباقات الطويلة أحياناً
        if (p.price >= 2700 && rnd.nextDouble() < 0.45) {
          final down = roundMoney(inv.total * 0.4);
          final rest = inv.total - down;
          inv.installments = [
            Installment(due: addDays(start, 30), amount: roundMoney(rest / 2)),
            Installment(due: addDays(start, 60), amount: roundMoney(rest - roundMoney(rest / 2))),
          ];
          pay(inv, down, sub.createdAt);
          for (final x in inv.installments) {
            if (x.due.isBefore(addDays(today, -3)) && rnd.nextDouble() < 0.85) {
              pay(inv, x.amount, at(x.due, 12 + rnd.nextInt(8)));
            }
          }
        } else if (rnd.nextDouble() < 0.08) {
          pay(inv, roundMoney(inv.total * 0.5), sub.createdAt); // دفع جزئي
        } else {
          pay(inv, inv.total, sub.createdAt);
        }
        // تجميد أحياناً
        if (p.freezeDays > 0 && rnd.nextDouble() < 0.12) {
          final fs = addDays(start, 10 + rnd.nextInt(15));
          final days = 5 + rnd.nextInt(min(p.freezeDays, 10) - 4);
          if (fs.isBefore(end)) {
            sub.freezes.add(Freeze(id: newId(), start: fs, end: addDays(fs, days - 1), reason: pick(['سفر', 'مرض', 'امتحانات']), createdAt: at(fs, 11)));
            sub.end = addDays(sub.end, days);
          }
        }
        subs.add(sub);
        // الحضور
        final freq = 0.25 + rnd.nextDouble() * 0.5;
        for (var dd = sub.start; !dd.isAfter(sub.end) && !dd.isAfter(today); dd = addDays(dd, 1)) {
          if (sub.freezeOn(dd) != null) continue;
          if (dd.weekday == DateTime.friday && rnd.nextDouble() < 0.6) continue;
          if (rnd.nextDouble() > freq) continue;
          if (sub.visitsTotal != null && sub.visitsUsed >= sub.visitsTotal!) break;
          int hour;
          if (female && rnd.nextDouble() < 0.7) {
            hour = 10 + rnd.nextInt(4);
          } else if (p == morning) {
            hour = 6 + rnd.nextInt(8);
          } else {
            hour = rnd.nextDouble() < 0.3 ? 6 + rnd.nextInt(3) : 16 + rnd.nextInt(7);
          }
          final t = at(dd, hour, rnd.nextInt(60));
          if (dd == today && t.isAfter(now)) continue;
          checkins.add(Checkin(id: newId(), memberId: m.id, subscriptionId: sub.id, time: t, result: CheckinResult.allowed, method: rnd.nextDouble() < 0.8 ? 'scan' : 'manual', by: rec.name));
          if (sub.visitsTotal != null) sub.visitsUsed++;
        }
        first = false;
        if (rnd.nextDouble() > loyal) break; // لم يجدد
        // يجدد بعد الانتهاء بأيام قليلة أحياناً
        start = addDays(sub.end, rnd.nextDouble() < 0.7 ? 1 : 1 + rnd.nextInt(10));
      }

      // تدريب شخصي لبعض الأعضاء
      if (rnd.nextDouble() < 0.12) {
        final ps = addDays(today, -rnd.nextInt(25));
        final coach = female ? t2 : t1;
        final sub = Subscription(
            id: newId(), memberId: m.id, planId: pt8.id, planName: pt8.name, kind: PlanKind.pt, start: ps,
            end: periodEnd(ps, 1, DurationUnit.month), visitsTotal: 8, price: pt8.price, trainerId: coach.id,
            createdAt: at(ps, 18), createdBy: rec.name);
        final inv = newInv(m, sub.createdAt, [InvoiceItem(kind: ItemKind.pt, refId: sub.id, description: pt8.name, unitPrice: pt8.price)]);
        sub.invoiceId = inv.id;
        pay(inv, inv.total, sub.createdAt);
        for (var k = 0; k < 1 + rnd.nextInt(6); k++) {
          final t = at(addDays(ps, k * 3), 19);
          if (t.isAfter(now)) break;
          checkins.add(Checkin(id: newId(), memberId: m.id, subscriptionId: sub.id, time: t, result: CheckinResult.allowed, method: 'pt', by: coach.name));
          sub.visitsUsed++;
        }
        subs.add(sub);
      }
    }

    // زائر يوم واحد + مبيعات المتجر
    for (var k = 0; k < 220; k++) {
      final dd = addDays(today, -rnd.nextInt(180));
      final m = pick(mems);
      final p = pick(products);
      final qty = p.price < 50 ? 1 + rnd.nextInt(3) : 1;
      final inv = newInv(m, at(dd, 17 + rnd.nextInt(5), rnd.nextInt(60)),
          [InvoiceItem(kind: ItemKind.product, refId: p.id, description: p.name, qty: qty.toDouble(), unitPrice: p.price)]);
      pay(inv, inv.total, inv.date);
    }
    // محاولات دخول مرفوضة (للتقارير)
    for (var k = 0; k < 25; k++) {
      final m = pick(mems);
      checkins.add(Checkin(id: newId(), memberId: m.id, time: at(addDays(today, -rnd.nextInt(60)), 18), result: CheckinResult.expired, method: 'scan'));
    }

    // ترقيم الفواتير والإيصالات بالترتيب الزمني
    invoices.sort((a, b) => a.date.compareTo(b.date));
    final numbered = <Invoice>[];
    for (final inv in invoices) {
      numbered.add(Invoice.fromMap({...inv.toMap(), 'number': d.nextNumber('invoice', s.invoicePrefix)}));
    }
    final invIdMap = {for (final i in numbered) i.id: i};
    payments.sort((a, b) => a.date.compareTo(b.date));
    final numberedPays = [for (final p in payments) Payment.fromMap({...p.toMap(), 'number': d.nextNumber('receipt', 'RC')})];
    for (var i = 0; i < members; i++) {
      d.nextCounter('member', start: 1001);
    }

    // المصروفات الشهرية
    final expenses = <Expense>[];
    for (var mo = 0; mo < 12; mo++) {
      final base = DateTime(today.year, today.month - mo, 1);
      final day0 = DateTime(base.year, base.month, 5);
      if (day0.isAfter(today)) continue;
      expenses.addAll([
        Expense(id: newId(), date: day0, category: 'إيجار', amount: 25000, by: owner.name),
        Expense(id: newId(), date: DateTime(base.year, base.month, 28).isAfter(today) ? today : DateTime(base.year, base.month, 28), category: 'رواتب', amount: 32000, by: owner.name),
        Expense(id: newId(), date: DateTime(base.year, base.month, 12), category: 'كهرباء ومياه', amount: 4000 + rnd.nextInt(2500).toDouble(), by: owner.name),
        if (rnd.nextBool()) Expense(id: newId(), date: DateTime(base.year, base.month, 18), category: 'صيانة الأجهزة', amount: 800 + rnd.nextInt(3000).toDouble(), by: owner.name),
        if (rnd.nextBool()) Expense(id: newId(), date: DateTime(base.year, base.month, 20), category: 'إعلانات', amount: 1500 + rnd.nextInt(2000).toDouble(), by: owner.name),
      ].where((e) => !e.date.isAfter(today)));
    }

    // حجوزات الحصص لهذا الأسبوع
    final bookings = <Booking>[];
    for (var dd = addDays(today, -3); !dd.isAfter(addDays(today, 3)); dd = addDays(dd, 1)) {
      for (final c in classes) {
        for (final sl in c.slots.where((x) => x.weekday == dd.weekday)) {
          final st = DateTime(dd.year, dd.month, dd.day, sl.start ~/ 60, sl.start % 60);
          final pool = mems.where((m) => c.gender == null || m.gender == c.gender).toList()..shuffle(rnd);
          final n = min(pool.length, (c.capacity * (0.5 + rnd.nextDouble() * 0.6)).round());
          for (var k = 0; k < n; k++) {
            final past = st.isBefore(now);
            bookings.add(Booking(
              id: newId(),
              classId: c.id,
              sessionStart: st,
              memberId: pool[k].id,
              status: k >= c.capacity ? BookingStatus.waitlist : (past ? (rnd.nextDouble() < 0.85 ? BookingStatus.attended : BookingStatus.noShow) : BookingStatus.booked),
              createdAt: st.subtract(Duration(hours: 5 + rnd.nextInt(40))),
            ));
          }
        }
      }
    }

    // عملاء محتملون
    final leads = <Lead>[
      for (var k = 0; k < 14; k++)
        Lead(
          id: newId(),
          name: '${pick(rnd.nextBool() ? _male : _female)} ${pick(_family)}',
          phone: phone(),
          source: pick(['فيسبوك', 'إنستجرام', 'اتصال هاتفي', 'زيارة']),
          interestPlanId: pick([monthly, quarter, year]).id,
          status: pick(LeadStatus.values.take(4).toList()),
          followUp: addDays(today, rnd.nextInt(7) - 2),
          createdAt: at(addDays(today, -rnd.nextInt(20)), 13),
          notes: pick(['سأل عن السعر', 'يريد تجربة يوم', 'مهتم بالتدريب الشخصي', 'سيأتي مع صديقه']),
        ),
    ];

    // قياسات لبعض الأعضاء
    final meas = <Measurement>[];
    for (final m in mems.take(25)) {
      var w = 70 + rnd.nextInt(35).toDouble();
      var fat = 18 + rnd.nextInt(15).toDouble();
      final h = (m.gender == Gender.female ? 155 : 168) + rnd.nextInt(18).toDouble();
      for (var k = 0; k < 5; k++) {
        final dd = addDays(today, -(4 - k) * 30);
        if (dd.isBefore(dateOnly(m.createdAt))) continue;
        meas.add(Measurement(id: newId(), memberId: m.id, date: dd, weight: roundMoney(w), height: h, bodyFat: roundMoney(fat), waist: 80 + fat));
        w -= rnd.nextDouble() * 2;
        fat -= rnd.nextDouble() * 1.2;
      }
    }

    // رسائل سابقة (صندوق الصادر)
    final msgs = <Message>[];
    for (var k = 0; k < 40; k++) {
      final m = pick(mems);
      final t = at(addDays(today, -rnd.nextInt(20)), 10 + rnd.nextInt(8));
      msgs.add(Message(
        id: newId(),
        memberId: m.id,
        name: m.name,
        phone: m.phone,
        channel: m.channel,
        kind: pick([Rk.expirySoon, Rk.receipt, Rk.birthday, Rk.inactive, Rk.expired]),
        body: 'مرحباً ${m.firstName} 👋 ...',
        status: MsgStatus.sent,
        provider: 'whatsapp_app',
        createdAt: t,
        sentAt: t,
      ));
    }

    save
      ..addAll(mems)
      ..addAll(subs)
      ..addAll(numbered)
      ..addAll(numberedPays)
      ..addAll(checkins)
      ..addAll(expenses)
      ..addAll(bookings)
      ..addAll(leads)
      ..addAll(meas)
      ..addAll(msgs);
    // تأكد أن كل دفعة تشير لفاتورة مرقّمة
    assert(numberedPays.every((p) => invIdMap.containsKey(p.invoiceId)));
    await d.putAll(save, withSettings: true);
  }
}
