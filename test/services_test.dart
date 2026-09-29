import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nadi_gym/core/dates.dart';
import 'package:nadi_gym/core/money.dart';
import 'package:nadi_gym/core/phone.dart';
import 'package:nadi_gym/models/activity.dart';
import 'package:nadi_gym/models/billing.dart';
import 'package:nadi_gym/models/business.dart';
import 'package:nadi_gym/models/member.dart';
import 'package:nadi_gym/models/plan.dart';
import 'package:nadi_gym/models/settings.dart';
import 'package:nadi_gym/models/subscription.dart';
import 'package:nadi_gym/services/billing.dart';
import 'package:nadi_gym/services/checkin.dart';
import 'package:nadi_gym/services/classes.dart';
import 'package:nadi_gym/services/data_tools.dart';
import 'package:nadi_gym/services/demo_data.dart';
import 'package:nadi_gym/services/membership.dart';
import 'package:nadi_gym/services/messaging.dart';
import 'package:nadi_gym/services/payments.dart';
import 'package:nadi_gym/services/pdf_service.dart';
import 'package:nadi_gym/services/reminders.dart';
import 'package:nadi_gym/services/reports.dart';
import 'package:nadi_gym/services/templates.dart';

import 'helpers.dart';

void main() {
  group('التواريخ والأرقام', () {
    test('نهاية الاشتراك الشهري', () {
      expect(periodEnd(DateTime(2026, 9, 29), 1, DurationUnit.month), DateTime(2026, 10, 28));
      expect(periodEnd(DateTime(2026, 1, 31), 1, DurationUnit.month), DateTime(2026, 2, 28));
      expect(periodEnd(DateTime(2026, 1, 15), 3, DurationUnit.month), DateTime(2026, 4, 14));
      expect(periodEnd(DateTime(2026, 11, 1), 3, DurationUnit.month), DateTime(2027, 1, 31));
      expect(periodEnd(DateTime(2026, 3, 1), 1, DurationUnit.year), DateTime(2027, 2, 28));
      expect(periodEnd(DateTime(2026, 3, 1), 1, DurationUnit.day), DateTime(2026, 3, 1));
      expect(periodEnd(DateTime(2026, 3, 1), 2, DurationUnit.week), DateTime(2026, 3, 14));
    });

    test('توحيد أرقام الجوال', () {
      expect(normalizePhone('01001234567', '20'), '201001234567');
      expect(normalizePhone('+966 50 123 4567', '20'), '966501234567');
      expect(normalizePhone('00971501234567', '20'), '971501234567');
      expect(normalizePhone('٠١٠٠١٢٣٤٥٦٧', '20'), '201001234567');
      expect(normalizePhone('201001234567', '20'), '201001234567');
      expect(normalizePhone('', '20'), isNull);
    });

    test('المبالغ', () {
      Money.configure(code: 'EGP', symbol: 'ج.م');
      expect(fmtMoney(1250), '1,250 ج.م');
      expect(fmtMoney(10.5), '10.50 ج.م');
      expect(parseAmount('١٬٢٥٠٫٥'), isNull); // الفاصل ٬ غير مدعوم عمداً
      expect(parseAmount('١٢٥٠٫٥'), 1250.5);
      expect(parseAmount('1,250'), 1250);
      Money.configure(code: 'KWD', symbol: 'د.ك');
      expect(Money.decimals, 3);
      expect(minorAmount(12.345, 'KWD'), 12345);
      Money.configure(code: 'EGP', symbol: 'ج.م');
    });
  });

  group('الاشتراكات', () {
    test('بيع اشتراك جديد مع رسوم تسجيل ودفع جزئي وأقساط', () async {
      final (g, _) = await newGym();
      final ms = MembershipService(g);
      final plan = await addPlan(g, price: 1500, value: 3, fee: 100);
      final m = await ms.addMember(ms.newMember(name: 'أحمد علي', phone: '01001234567'));
      expect(m.code, 1001);
      final r = await ms.sell(SaleRequest(
        memberId: m.id,
        planId: plan.id,
        registrationFee: true,
        discount: 100,
        payments: const [PayInput(500, PayMethod.cash)],
        installments: [
          Installment(due: DateTime(2026, 10, 29), amount: 500),
          Installment(due: DateTime(2026, 11, 29), amount: 500),
        ],
      ));
      expect(r.invoice.total, 1500);
      expect(r.invoice.paid, 500);
      expect(r.invoice.balance, 1000);
      expect(r.subscription.start, DateTime(2026, 9, 29));
      expect(r.subscription.end, DateTime(2026, 12, 28));
      expect(r.invoice.number, 'INV-000001');
      expect(r.payments.single.number, 'RC-000001');
      expect(g.balanceOf(m.id), 1000);
      expect(g.overdueOf(m.id), 0); // لم يحن موعد أي قسط
      expect(g.overdueOf(m.id, DateTime(2026, 11, 1)), 500);
      final st = r.invoice.installmentStatus();
      expect(st[0].left, 500);
      // سداد جزئي يوزع على الأقدم
      await BillingService(g).collect(r.invoice, 700, PayMethod.card);
      final st2 = r.invoice.installmentStatus();
      expect(st2[0].left, 0);
      expect(st2[1].left, 300);
      expect(ms.stateOf(m.id), MemberState.active);
    });

    test('مجموع الأقساط يجب أن يساوي الإجمالي', () async {
      final (g, _) = await newGym();
      final ms = MembershipService(g);
      final plan = await addPlan(g, price: 1000);
      final m = await ms.addMember(ms.newMember(name: 'x', phone: '0100000001'));
      expect(
          () => ms.sell(SaleRequest(
              memberId: m.id,
              planId: plan.id,
              payments: const [PayInput(200, PayMethod.cash)],
              installments: [Installment(due: DateTime(2026, 11, 1), amount: 500)])),
          throwsA(isA<GymException>()));
    });

    test('التجديد يبدأ من نهاية الاشتراك الحالي، ويمنع تذكير الانتهاء', () async {
      final (g, clock) = await newGym();
      final ms = MembershipService(g);
      final plan = await addPlan(g);
      final m = await ms.addMember(ms.newMember(name: 'سارة', phone: '0100000002', gender: Gender.female));
      final first = (await ms.sell(SaleRequest(memberId: m.id, planId: plan.id, payments: const [PayInput(600, PayMethod.cash)])))
          .subscription;
      clock.setDay(DateTime(2026, 10, 25));
      expect(ms.stateOf(m.id), MemberState.expiring);
      expect(ms.suggestedStart(m.id), DateTime(2026, 10, 29));
      final second = (await ms.sell(SaleRequest(memberId: m.id, planId: plan.id))).subscription;
      expect(second.start, DateTime(2026, 10, 29));
      expect(ms.renewedAfter(first), isTrue);
      expect(ms.stateOf(m.id), MemberState.active);
      clock.setDay(DateTime(2026, 11, 2));
      expect(ms.currentSub(m.id)!.id, second.id);
    });

    test('الخصم أعلى من المسموح لموظف الاستقبال يحتاج صلاحية', () async {
      final (g, _) = await newGym();
      final ms = MembershipService(g);
      final plan = await addPlan(g, price: 1000);
      final m = await ms.addMember(ms.newMember(name: 'x', phone: '0100000003'));
      g.user = Staff(id: 's1', name: 'استقبال', role: Role.reception);
      await expectLater(() => ms.sell(SaleRequest(memberId: m.id, planId: plan.id, discount: 300)), throwsA(isA<GymException>()));
      final ok = await ms.sell(SaleRequest(memberId: m.id, planId: plan.id, discount: 150));
      expect(ok.invoice.total, 850);
    });

    test('التجميد يمدد النهاية وفك التجميد المبكر يعيد الأيام', () async {
      final (g, clock) = await newGym();
      final ms = MembershipService(g);
      final plan = await addPlan(g, freezeDays: 10, freezeTimes: 1);
      final m = await ms.addMember(ms.newMember(name: 'خالد', phone: '0100000004'));
      final s = (await ms.sell(SaleRequest(memberId: m.id, planId: plan.id))).subscription;
      expect(s.end, DateTime(2026, 10, 28));
      await ms.freeze(s, start: DateTime(2026, 10, 5), days: 10);
      expect(s.end, DateTime(2026, 11, 7));
      expect(s.statusOn(DateTime(2026, 10, 5)), SubStatus.frozen);
      expect(s.statusOn(DateTime(2026, 10, 14)), SubStatus.frozen);
      expect(s.statusOn(DateTime(2026, 10, 15)), SubStatus.active);
      // تجاوز عدد المرات: موظف الاستقبال لا يستطيع، والمدير يستطيع
      g.user = Staff(id: 'r', name: 'استقبال', role: Role.reception);
      await expectLater(() => ms.freeze(s, start: DateTime(2026, 10, 20), days: 1), throwsA(isA<GymException>()));
      g.user = null;
      clock.setDay(DateTime(2026, 10, 8));
      await ms.unfreeze(s);
      expect(s.freezes.single.days, 3);
      expect(s.end, DateTime(2026, 10, 31));
      expect(s.statusOn(DateTime(2026, 10, 8)), SubStatus.active);
    });

    test('إلغاء اشتراك مع استرداد جزئي يصفّر المستحق', () async {
      final (g, _) = await newGym();
      final ms = MembershipService(g);
      final plan = await addPlan(g, price: 600);
      final m = await ms.addMember(ms.newMember(name: 'علي', phone: '0100000005'));
      final r = await ms.sell(SaleRequest(memberId: m.id, planId: plan.id, payments: const [PayInput(600, PayMethod.cash)]));
      await ms.cancel(r.subscription, reason: 'سفر', refund: 400);
      expect(r.invoice.paid, 200);
      expect(r.invoice.total, 200);
      expect(r.invoice.balance, 0);
      expect(ms.stateOf(m.id), MemberState.none);
      expect(Reports(g).collected(Range.today(g.now())), 200);
      expect(g.audit.all.any((a) => a.action == 'cancel'), isTrue);
    });

    test('رقم الجوال المكرر مرفوض، والبحث بالرقم والاسم والبطاقة', () async {
      final (g, _) = await newGym();
      final ms = MembershipService(g);
      final m = await ms.addMember(ms.newMember(name: 'محمد حسن', phone: '01001112223'));
      await expectLater(() => ms.addMember(ms.newMember(name: 'آخر', phone: '+20 100 111 2223')), throwsA(isA<GymException>()));
      expect(ms.search('محمد').single.id, m.id);
      expect(ms.search('1001').single.id, m.id);
      expect(ms.search('11122').single.id, m.id);
      expect(ms.resolveScan(m.qrData)!.id, m.id);
      expect(ms.resolveScan('1001')!.id, m.id);
      expect(ms.resolveScan('NADI:XXXX'), isNull);
    });

    test('مكافأة الترشيح تضيف أياماً للعضو المرشِّح', () async {
      final (g, _) = await newGym();
      g.settings.referralRewardDays = 7;
      final ms = MembershipService(g);
      final plan = await addPlan(g);
      final a = await ms.addMember(ms.newMember(name: 'أ', phone: '0100000011'));
      final sa = (await ms.sell(SaleRequest(memberId: a.id, planId: plan.id))).subscription;
      final b = await ms.addMember(ms.newMember(name: 'ب', phone: '0100000012')..referredBy = a.id);
      await ms.sell(SaleRequest(memberId: b.id, planId: plan.id));
      expect(sa.end, DateTime(2026, 11, 4));
    });

    test('كوبون الخصم', () async {
      final (g, _) = await newGym();
      final ms = MembershipService(g);
      final plan = await addPlan(g, price: 1000);
      await g.put(Coupon(id: 'c', code: 'RAMADAN20', value: 20, maxUses: 1));
      final m = await ms.addMember(ms.newMember(name: 'x', phone: '0100000013'));
      final r = await ms.sell(SaleRequest(memberId: m.id, planId: plan.id, couponCode: 'ramadan20'));
      expect(r.invoice.total, 800);
      expect(g.coupons['c']!.uses, 1);
      await expectLater(() => ms.quote(SaleRequest(memberId: m.id, planId: plan.id, couponCode: 'RAMADAN20')), throwsA(isA<GymException>()));
    });
  });

  group('الضريبة', () {
    test('ضريبة شاملة ومضافة', () {
      final inc = Invoice(id: 'a', number: 'n', date: DateTime(2026), items: [InvoiceItem(kind: ItemKind.other, description: 'x', unitPrice: 115)], taxRate: 0.15);
      expect(inc.total, 115);
      expect(inc.tax, 15);
      final exc = Invoice(
          id: 'b', number: 'n', date: DateTime(2026), items: [InvoiceItem(kind: ItemKind.other, description: 'x', unitPrice: 100)], taxRate: 0.15, taxInclusive: false);
      expect(exc.total, 115);
      expect(exc.tax, 15);
    });

    test('رمز QR للفاتورة السعودية', () {
      final b64 = zatcaTlv(seller: 'نادي', vatNumber: '300000000000003', time: DateTime.utc(2026, 9, 29, 10), total: 115, vat: 15);
      final raw = base64Decode(b64);
      expect(raw[0], 1);
      expect(utf8.decode(raw.sublist(2, 2 + raw[1])), 'نادي');
    });
  });

  group('الدخول', () {
    test('سماح، رفض عند الانتهاء، فترة سماح، والحد اليومي', () async {
      final (g, clock) = await newGym();
      final ms = MembershipService(g);
      final cs = CheckinService(g);
      final plan = await addPlan(g);
      final m = await ms.addMember(ms.newMember(name: 'يوسف', phone: '0100000020', gender: Gender.male));
      expect(cs.evaluate(m).result, CheckinResult.noSubscription);
      await ms.sell(SaleRequest(memberId: m.id, planId: plan.id, payments: const [PayInput(600, PayMethod.cash)]));
      final d1 = cs.evaluate(m);
      expect(d1.allowed, isTrue);
      expect(d1.warnings.any((w) => w.contains('أول زيارة')), isTrue);
      await cs.commit(d1, method: 'scan');
      expect(cs.evaluate(m).result, CheckinResult.dailyLimit);
      expect(cs.inGymNow().length, 1);
      clock.setDay(DateTime(2026, 10, 29));
      expect(cs.evaluate(m).result, CheckinResult.expired);
      g.settings.graceDays = 2;
      expect(cs.evaluate(m).allowed, isTrue);
      g.settings.graceDays = 0;
      // سماح المدير
      final dec = cs.evaluate(m);
      final c = await cs.commit(dec, override: true);
      expect(c.result, CheckinResult.override);
      expect(g.audit.all.any((a) => a.action == 'override'), isTrue);
    });

    test('باقة الحصص تخصم حصة مع كل دخول وتنتهي عند النفاد', () async {
      final (g, clock) = await newGym();
      final ms = MembershipService(g);
      final cs = CheckinService(g);
      final plan = await addPlan(g, kind: PlanKind.visits, visits: 2, value: 2);
      final m = await ms.addMember(ms.newMember(name: 'x', phone: '0100000021'));
      final s = (await ms.sell(SaleRequest(memberId: m.id, planId: plan.id))).subscription;
      await cs.commit(cs.evaluate(m));
      clock.advance(days: 1);
      final d2 = cs.evaluate(m);
      expect(d2.visitsLeft, 0);
      await cs.commit(d2);
      expect(s.visitsUsed, 2);
      clock.advance(days: 1);
      expect(cs.evaluate(m).result, CheckinResult.exhausted);
    });

    test('ساعات السيدات، ساعات الباقة، والتجميد والدين', () async {
      final (g, clock) = await newGym(DateTime(2026, 9, 29, 11)); // الثلاثاء 11 صباحاً
      g.settings.genderWindows = [GenderWindow(gender: 'f', weekdays: [], from: 10 * 60, to: 14 * 60)];
      final ms = MembershipService(g);
      final cs = CheckinService(g);
      final plan = await addPlan(g, price: 1000);
      final man = await ms.addMember(ms.newMember(name: 'رجل', phone: '0100000030', gender: Gender.male));
      final woman = await ms.addMember(ms.newMember(name: 'سيدة', phone: '0100000031', gender: Gender.female));
      await ms.sell(SaleRequest(memberId: man.id, planId: plan.id,
          payments: const [PayInput(500, PayMethod.cash)], installments: [Installment(due: DateTime(2026, 9, 29), amount: 500)]));
      await ms.sell(SaleRequest(memberId: woman.id, planId: plan.id));
      expect(cs.evaluate(man).result, CheckinResult.genderHours);
      expect(cs.evaluate(woman).allowed, isTrue); // الدين لا يمنع الدخول افتراضياً
      clock.now = DateTime(2026, 9, 29, 18);
      expect(cs.evaluate(woman).result, CheckinResult.genderHours); // خارج أوقاتها
      g.settings.set('genderStrict', false);
      final dw = cs.evaluate(woman);
      expect(dw.allowed, isTrue);
      expect(dw.warnings.any((w) => w.contains('متأخر')), isTrue);
      final dm = cs.evaluate(man);
      expect(dm.allowed, isTrue);
      g.settings
        ..blockOnDebt = true
        ..debtLimit = 100;
      expect(cs.evaluate(man).result, CheckinResult.debt);
      g.settings.blockOnDebt = false;
      // باقة صباحية
      final morning = await addPlan(g, name: 'صباحي', from: 6 * 60, to: 14 * 60, price: 0);
      final early = await ms.addMember(ms.newMember(name: 'صباحي', phone: '0100000032', gender: Gender.male));
      await ms.sell(SaleRequest(memberId: early.id, planId: morning.id));
      expect(cs.evaluate(early).result, CheckinResult.outsideHours);
      // تجميد
      clock.now = DateTime(2026, 9, 30, 18);
      final s = ms.currentSub(man.id)!;
      await ms.freeze(s, start: DateTime(2026, 9, 30), days: 3);
      expect(cs.evaluate(man).result, CheckinResult.frozen);
    });

    test('جلسات التدريب الشخصي', () async {
      final (g, _) = await newGym();
      final ms = MembershipService(g);
      final cs = CheckinService(g);
      final t = Staff(id: 't', name: 'كابتن', role: Role.trainer, isTrainer: true, commissionPct: 30, sessionRate: 50);
      await g.put(t);
      final pt = await addPlan(g, name: 'PT', kind: PlanKind.pt, visits: 8, price: 1600);
      final m = await ms.addMember(ms.newMember(name: 'x', phone: '0100000040'));
      await expectLater(() => ms.sell(SaleRequest(memberId: m.id, planId: pt.id)), throwsA(isA<GymException>()));
      final s = (await ms.sell(SaleRequest(memberId: m.id, planId: pt.id, trainerId: 't'))).subscription;
      await cs.recordPtSession(s);
      await cs.recordPtSession(s);
      expect(s.visitsLeft, 6);
      expect(ms.currentSub(m.id), isNull); // التدريب الشخصي لا يمنح دخولاً للنادي
      final tr = Reports(g).trainers(Range.today(g.now())).single;
      expect(tr.ptSales, 1600);
      expect(tr.sessions, 2);
      expect(tr.commission, 480);
      expect(tr.sessionPay, 100);
    });
  });

  group('الفواتير والمتجر', () {
    test('بيع منتجات يخصم المخزون وإلغاء الفاتورة يعيده', () async {
      final (g, _) = await newGym();
      final p = Product(id: 'p', name: 'مياه', price: 10, stock: 5);
      await g.put(p);
      final b = BillingService(g);
      await expectLater(() => b.sellProducts([CartLine(p, 6)], payments: const [PayInput(60, PayMethod.cash)]), throwsA(isA<GymException>()));
      final inv = await b.sellProducts([CartLine(p, 3)], customerName: 'زائر', payments: const [PayInput(30, PayMethod.cash)]);
      expect(p.stock, 2);
      expect(inv.status, InvoiceStatus.paid);
      await expectLater(() => b.voidInvoice(inv, 'خطأ'), throwsA(isA<GymException>()));
      await b.refund(inv, 30, PayMethod.cash, 'خطأ');
      await b.voidInvoice(inv, 'خطأ');
      expect(p.stock, 5);
      expect(inv.status, InvoiceStatus.voided);
    });

    test('تحصيل من العضو يوزع على الفواتير الأقدم', () async {
      final (g, clock) = await newGym();
      final ms = MembershipService(g);
      final plan = await addPlan(g, price: 300);
      final m = await ms.addMember(ms.newMember(name: 'x', phone: '0100000050'));
      final a = (await ms.sell(SaleRequest(memberId: m.id, planId: plan.id))).invoice;
      clock.advance(days: 1);
      final c = (await ms.sell(SaleRequest(memberId: m.id, planId: plan.id))).invoice;
      final pays = await BillingService(g).collectFromMember(m.id, 450, PayMethod.cash);
      expect(pays.length, 2);
      expect(a.balance, 0);
      expect(c.balance, 150);
      expect(BillingService(g).debtors().single.balance, 150);
    });
  });

  group('التذكيرات', () {
    test('تذكير قبل الانتهاء بالأيام المحددة بدون تكرار، ويتوقف بعد التجديد', () async {
      final (g, clock) = await newGym();
      g.settings
        ..waMode = 'phone'
        ..setReminderOn(Rk.inactive, false);
      final ms = MembershipService(g);
      final eng = ReminderEngine(g);
      final plan = await addPlan(g);
      final m = await ms.addMember(ms.newMember(name: 'أحمد علي', phone: '01001234567'));
      await ms.sell(SaleRequest(memberId: m.id, planId: plan.id));
      clock.now = DateTime(2026, 10, 21, 11); // باقي 7 أيام
      expect(await eng.run(), 1);
      final msg = g.messages.all.single;
      expect(msg.kind, Rk.expirySoon);
      expect(msg.status, MsgStatus.manual);
      expect(msg.body, contains('أحمد'));
      expect(msg.body, contains('7'));
      expect(await eng.run(), 0); // نفس اليوم
      clock.now = DateTime(2026, 10, 22, 11); // باقي 6: نفس العتبة (7)
      expect(await eng.run(), 0);
      clock.now = DateTime(2026, 10, 26, 11); // باقي 2: عتبة 3
      expect(await eng.run(), 1);
      await ms.sell(SaleRequest(memberId: m.id, planId: plan.id)); // جدد
      clock.now = DateTime(2026, 10, 27, 11);
      expect(await eng.run(), 0);
    });

    test('لا يبدأ قبل ساعة الإرسال، ويحترم إيقاف الرسائل', () async {
      final (g, clock) = await newGym();
      final ms = MembershipService(g);
      final eng = ReminderEngine(g);
      final plan = await addPlan(g);
      final m = await ms.addMember(ms.newMember(name: 'x', phone: '0100000060')..optOut = true);
      await ms.sell(SaleRequest(memberId: m.id, planId: plan.id));
      clock.now = DateTime(2026, 10, 21, 8);
      expect(await eng.run(), 0);
      clock.now = DateTime(2026, 10, 21, 12);
      expect(await eng.run(), 0); // أوقف الرسائل
    });

    test('انتهاء، استرجاع، أقساط متأخرة، عيد ميلاد، وغياب', () async {
      final (g, clock) = await newGym();
      final ms = MembershipService(g);
      final cs = CheckinService(g);
      final eng = ReminderEngine(g);
      final plan = await addPlan(g, price: 1000);
      final a = await ms.addMember(ms.newMember(name: 'منتهي', phone: '0100000070'));
      await ms.sell(SaleRequest(memberId: a.id, planId: plan.id, payments: const [PayInput(1000, PayMethod.cash)]));
      final b = await ms.addMember(ms.newMember(name: 'مقسط', phone: '0100000071')..birthDate = DateTime(1990, 10, 29));
      await ms.sell(SaleRequest(
          memberId: b.id,
          planId: await addPlan(g, name: 'سنوي', unit: DurationUnit.year, price: 1000).then((p) => p.id),
          payments: const [PayInput(400, PayMethod.cash)],
          installments: [Installment(due: DateTime(2026, 10, 20), amount: 600)]));
      await cs.commit(cs.evaluate(b));
      clock.now = DateTime(2026, 10, 29, 12);
      await eng.run();
      final kinds = g.messages.all.map((m) => m.kind).toSet();
      expect(kinds, containsAll([Rk.expired, Rk.installmentLate, Rk.birthday, Rk.inactive]));
      clock.now = DateTime(2026, 11, 4, 12);
      await eng.run();
      expect(g.messages.all.where((m) => m.kind == Rk.winback).length, 1);
    });

    test('القوالب تحذف الأسطر الفارغة', () {
      expect(renderTemplate('مرحباً {name}\n{pay_link}\nشكراً', {'name': 'أحمد', 'pay_link': ''}), 'مرحباً أحمد\nشكراً');
    });

    test('رسالة الإيصال والترحيب', () async {
      final (g, _) = await newGym();
      final ms = MembershipService(g);
      final plan = await addPlan(g);
      final m = await ms.addMember(ms.newMember(name: 'سارة', phone: '0100000080'));
      final r = await ms.sell(SaleRequest(memberId: m.id, planId: plan.id, payments: const [PayInput(600, PayMethod.cash)]));
      final eng = ReminderEngine(g);
      expect(eng.welcome(m, r.subscription)!.body, contains('1001'));
      expect(eng.receipt(r.invoice, r.payments.first)!.body, contains('600'));
      expect(eng.invoiceText(r.invoice), contains('INV-000001'));
    });
  });

  group('مزودو الرسائل', () {
    test('WhatsApp Cloud API', () async {
      late http.Request req;
      final client = MockClient((r) async {
        req = r;
        return http.Response('{"messages":[{"id":"wamid.1"}]}', 200);
      });
      final s = WhatsAppCloudSender(client, phoneNumberId: '123', token: 'T', templateName: 'reminder', templateLang: 'ar');
      final id = await s.send('201001234567', 'مرحباً أحمد\nاشتراكك ينتهي');
      expect(id, 'wamid.1');
      expect(req.url.toString(), 'https://graph.facebook.com/v21.0/123/messages');
      expect(req.headers['Authorization'], 'Bearer T');
      final body = jsonDecode(req.body);
      expect(body['template']['name'], 'reminder');
      expect(body['template']['components'][0]['parameters'][1]['text'], 'اشتراكك ينتهي');
    });

    test('Twilio', () async {
      late http.Request req;
      final client = MockClient((r) async {
        req = r;
        return http.Response('{"sid":"SM1"}', 201);
      });
      final id = await TwilioSender(client, sid: 'AC1', token: 'tok', from: '+14155550000', whatsapp: true).send('966501234567', 'hi');
      expect(id, 'SM1');
      expect(req.bodyFields['To'], 'whatsapp:+966501234567');
      expect(req.bodyFields['From'], 'whatsapp:+14155550000');
    });

    test('بوابة HTTP عامة (JSON و GET) مع فحص نص النجاح', () async {
      final seen = <http.Request>[];
      final client = MockClient((r) async {
        seen.add(r);
        return http.Response(r.method == 'GET' ? 'ERROR' : '{"sent":"true"}', 200);
      });
      final json = HttpGatewaySender(client,
          url: 'https://api.example.com/send',
          bodyTemplate: '{"to":"{phone_plus}","body":"{message}"}',
          headers: 'X-Token: abc',
          successText: 'true',
          countryCode: '20');
      await json.send('201001234567', 'سطر "1"\nسطر 2');
      final b = jsonDecode(seen.last.body);
      expect(b['to'], '+201001234567');
      expect(b['body'], 'سطر "1"\nسطر 2');
      expect(seen.last.headers['X-Token'], 'abc');
      final get = HttpGatewaySender(client,
          url: 'https://sms.example.com/?to={phone_local}&msg={message}', method: 'GET', successText: 'OK', countryCode: '20');
      await expectLater(get.send('201001234567', 'hi'), throwsA(isA<SendException>()));
      expect(seen.last.url.queryParameters['to'], '01001234567');
    });

    test('المرسل الآلي: نجاح، إعادة المحاولة، ثم التحويل إلى SMS', () async {
      final (g, _) = await newGym(DateTime(2026, 9, 29, 12));
      g.settings
        ..waMode = 'gateway'
        ..smsMode = 'phone'
        ..setStr('waGwUrl', 'https://api.example.com/send')
        ..setStr('waGwBody', '{"to":"{phone}","body":"{message}"}');
      var fail = true;
      final client = MockClient((r) async => fail ? http.Response('down', 500) : http.Response('ok', 200));
      final ms = MembershipService(g);
      final m = await ms.addMember(ms.newMember(name: 'x', phone: '01001234567'));
      final eng = ReminderEngine(g);
      final msg = eng.custom(m, 'مرحباً {first_name}')!;
      expect(msg.status, MsgStatus.queued);
      await g.put(msg);
      final disp = Dispatcher(g, client: client);
      for (var i = 0; i < 3; i++) {
        await disp.dispatchQueued();
      }
      expect(msg.channel, Channel.sms);
      expect(msg.status, MsgStatus.manual); // SMS يدوي
      expect(disp.manualLink(msg).toString(), startsWith('sms:+201001234567?body='));
      fail = false;
      final m2 = eng.custom(m, 'رسالة 2')!;
      await g.put(m2);
      final res = await disp.dispatchQueued();
      expect(res.sent, 1);
      expect(m2.status, MsgStatus.sent);
    });

    test('رابط واتساب اليدوي', () async {
      final (g, _) = await newGym();
      final disp = Dispatcher(g);
      final ms = MembershipService(g);
      final m = await ms.addMember(ms.newMember(name: 'x', phone: '01001234567'));
      final msg = ReminderEngine(g).custom(m, 'أهلاً بك')!;
      expect(disp.manualLink(msg).toString(), 'https://wa.me/201001234567?text=${Uri.encodeComponent('أهلاً بك')}');
    });
  });

  group('بوابات الدفع', () {
    test('Stripe: إنشاء رابط والتحقق من الدفع يسجل دفعة أونلاين', () async {
      final (g, _) = await newGym();
      g.settings
        ..payProvider = 'stripe'
        ..paySecretKey = 'sk_test'
        ..gymPhone = '01001234567';
      var paid = false;
      final calls = <http.Request>[];
      final client = MockClient((r) async {
        calls.add(r);
        if (r.method == 'POST') return http.Response('{"id":"cs_1","url":"https://checkout.stripe.com/c/cs_1"}', 200);
        return http.Response(jsonEncode({'payment_status': paid ? 'paid' : 'unpaid'}), 200);
      });
      final ms = MembershipService(g);
      final plan = await addPlan(g, price: 600);
      final m = await ms.addMember(ms.newMember(name: 'x', phone: '0100000090'));
      final inv = (await ms.sell(SaleRequest(memberId: m.id, planId: plan.id))).invoice;
      final svc = PaymentLinkService(g, client: client);
      final link = await svc.createLink(inv);
      expect(link.url, contains('checkout.stripe.com'));
      expect(calls.first.bodyFields['line_items[0][price_data][unit_amount]'], '60000');
      expect(calls.first.bodyFields['line_items[0][price_data][currency]'], 'egp');
      expect(calls.first.bodyFields['success_url'], 'https://wa.me/201001234567');
      expect(TemplateContext(g).payInfo(inv), link.url);
      expect(await svc.checkPending(), 0);
      paid = true;
      expect(await svc.checkPending(), 1);
      expect(inv.balance, 0);
      expect(g.paymentsOf(inv.id).single.method, PayMethod.online);
      expect(await svc.checkPending(), 0); // لا يُسجل مرتين
    });

    test('Moyasar و Tap', () async {
      final client = MockClient((r) async {
        if (r.url.host == 'api.moyasar.com') {
          expect(r.bodyFields['amount'], '11500');
          return http.Response('{"id":"inv_1","status":"initiated","url":"https://checkout.moyasar.com/invoices/inv_1"}', 201);
        }
        final b = jsonDecode(r.body);
        expect(b['amount'], 12.5);
        expect(b['customer']['phone']['number'], '501234567');
        return http.Response('{"id":"chg_1","transaction":{"url":"https://tap.company/pay/chg_1"}}', 200);
      });
      final inv = Invoice(id: 'i', number: 'INV-1', date: DateTime(2026), items: []);
      final l1 = await MoyasarGateway(client, secretKey: 'sk', currency: 'SAR', returnUrl: '').create(invoice: inv, amount: 115);
      expect(l1.externalId, 'inv_1');
      final l2 = await TapGateway(client, secretKey: 'sk', currency: 'KWD', returnUrl: '', countryCode: '966')
          .create(invoice: inv, amount: 12.5, member: Member(id: 'm', code: 1, name: 'x', phone: '0501234567', cardToken: 't', createdAt: DateTime(2026)));
      expect(l2.url, 'https://tap.company/pay/chg_1');
    });
  });

  group('الحصص', () {
    test('الحجز وقائمة الانتظار والترقية عند الإلغاء', () async {
      final (g, _) = await newGym(DateTime(2026, 9, 29, 9)); // الثلاثاء
      final ms = MembershipService(g);
      final plan = await addPlan(g);
      final cls = GymClass(id: 'c', name: 'كروس فت', capacity: 1, slots: [ClassSlot(DateTime.tuesday, 19 * 60)]);
      await g.put(cls);
      final a = await ms.addMember(ms.newMember(name: 'أ', phone: '0100000100'));
      final b = await ms.addMember(ms.newMember(name: 'ب', phone: '0100000101'));
      final c = await ms.addMember(ms.newMember(name: 'بدون', phone: '0100000102'));
      await ms.sell(SaleRequest(memberId: a.id, planId: plan.id));
      await ms.sell(SaleRequest(memberId: b.id, planId: plan.id));
      final svc = ClassService(g);
      final s = svc.sessionsOn(DateTime(2026, 9, 29)).single;
      final ba = await svc.book(s, a);
      final bb = await svc.book(s, b);
      expect(ba.status, BookingStatus.booked);
      expect(bb.status, BookingStatus.waitlist);
      await expectLater(() => svc.book(s, c), throwsA(isA<GymException>()));
      final promoted = await svc.cancel(ba);
      expect(promoted!.id, bb.id);
      expect(bb.status, BookingStatus.booked);
      await svc.mark(bb, BookingStatus.attended);
      expect(g.checkinsOf(b.id).single.method, 'class');
    });
  });

  group('التقارير والبيانات', () {
    test('البيانات التجريبية متسقة والتقارير تعمل', () async {
      final (g, _) = await newGym(DateTime(2026, 9, 29, 20));
      await DemoData(g).generate(members: 60);
      expect(g.members.items.length, 60);
      final rep = Reports(g);
      final r = Range.thisMonth(g.now());
      expect(rep.collected(r), greaterThan(0));
      expect(rep.activeCount(), greaterThan(10));
      // المدفوع في كل فاتورة = مجموع دفعاتها
      for (final inv in g.invoices.all) {
        final sum = g.paymentsOf(inv.id).fold(0.0, (s, p) => s + p.amount);
        expect(roundMoney(sum), roundMoney(inv.paid), reason: inv.number);
        expect(inv.balance >= -0.001, isTrue);
      }
      final numbers = g.invoices.all.map((i) => i.number).toSet();
      expect(numbers.length, g.invoices.items.length);
      expect(rep.dailySummaryText(g.today), contains('المحصّل'));
      expect(rep.visitsByHour(Range.lastDays(g.now(), 30)).reduce((a, b) => a + b), greaterThan(0));
      // الأرقام التسلسلية تكمل بعد البيانات التجريبية
      final ms = MembershipService(g);
      final m = await ms.addMember(ms.newMember(name: 'جديد', phone: '0109999999'));
      expect(m.code, 1061);
      // التذكيرات تعمل على بيانات كبيرة
      expect(await ReminderEngine(g).run(force: true), greaterThan(0));
    });

    test('النسخ الاحتياطي والاسترجاع', () async {
      final (g, _) = await newGym();
      await DemoData(g).generate(members: 15);
      final bytes = await BackupService(g).exportBytes();
      final (g2, _) = await newGym();
      await BackupService(g2).restore(bytes);
      expect(g2.members.items.length, 15);
      expect(g2.invoices.items.length, g.invoices.items.length);
      expect(g2.settings.gymName, g.settings.gymName);
      expect(g2.peekCounter('invoice'), g.peekCounter('invoice'));
    });

    test('استيراد الأعضاء من CSV', () async {
      final (g, _) = await newGym();
      const csv = '﻿الاسم;الجوال;الجنس;الباقة;تاريخ الانتهاء;الرصيد\n'
          'أحمد علي;01001234567;ذكر;شهري;15/10/2026;200\n'
          '"سارة, محمد";01007654321;أنثى;;;\n'
          'مكرر;01001234567;;;;\n';
      final res = await MemberImporter(g).importCsv(csv);
      expect(res.members, 2);
      expect(res.subscriptions, 1);
      expect(res.skipped, 1);
      final ahmed = g.members.all.firstWhere((m) => m.name == 'أحمد علي');
      expect(ahmed.gender, Gender.male);
      expect(MembershipService(g).currentSub(ahmed.id)!.end, DateTime(2026, 10, 15));
      expect(g.balanceOf(ahmed.id), 200);
      expect(g.members.all.any((m) => m.name == 'سارة, محمد' && m.gender == Gender.female), isTrue);
    });

    test('الرقم السري', () {
      final s = Staff(id: 'a', name: 'x');
      s.pinHash = hashPin('1234', s.id);
      expect(checkPin(s, '1234'), isTrue);
      expect(checkPin(s, '0000'), isFalse);
    });
  });
}
