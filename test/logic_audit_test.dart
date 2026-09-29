import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nadi_gym/core/phone.dart';
import 'package:nadi_gym/models/activity.dart';
import 'package:nadi_gym/models/billing.dart';
import 'package:nadi_gym/models/business.dart';
import 'package:nadi_gym/models/member.dart';
import 'package:nadi_gym/models/settings.dart';
import 'package:nadi_gym/services/billing.dart';
import 'package:nadi_gym/services/checkin.dart';
import 'package:nadi_gym/services/data_tools.dart';
import 'package:nadi_gym/services/membership.dart';
import 'package:nadi_gym/ui/widgets/common.dart';

import 'helpers.dart';

/// مراجعة منطقية: قيم غير منطقية تُرفض، والحسابات تتطابق في كل مكان
void main() {
  group('الأرقام العربية', () {
    test('تُقبل في كل الحقول والبحث والرقم السري', () async {
      expect(parseIntInput('١٢'), 12);
      expect(parseIntInput('۳'), 3);
      expect(parseIntInput(' 7 '), 7);
      expect(parseIntInput('abc'), isNull);
      final (g, _) = await newGym();
      final ms = MembershipService(g);
      final m = await ms.addMember(ms.newMember(name: 'سامي', phone: '0599876543'));
      expect(ms.search('${m.code}'.split('').map((c) => '٠١٢٣٤٥٦٧٨٩'[int.parse(c)]).join()).single.id, m.id);
      expect(ms.search('٩٨٧٦٥').single.id, m.id);
      expect(ms.resolveScan('${m.code}'.split('').map((c) => '٠١٢٣٤٥٦٧٨٩'[int.parse(c)]).join())?.id, m.id);
      // جوال بأرقام عربية: يُقبل ويُحفظ موحداً، والتكرار يُكتشف
      final a = await ms.addMember(ms.newMember(name: 'عربي', phone: '٠٥٦٩٢٢٢٣٣٣'));
      expect(a.phone, '0569222333');
      await expectLater(ms.addMember(ms.newMember(name: 'مكرر', phone: '0569222333')), throwsA(isA<GymException>()));
      final s = Staff(id: 'x', name: 'موظف')..pinHash = hashPin('١٢٣٤', 'x');
      expect(checkPin(s, '1234'), isTrue);
    });
  });

  group('البيع والخصومات والضريبة', () {
    test('خصم سالب أو نسبة أكثر من 100% تُرفض', () async {
      final (g, _) = await newGym();
      final plan = await addPlan(g, price: 500);
      final ms = MembershipService(g);
      final m = await ms.addMember(ms.newMember(name: 'x', phone: '0591000001'));
      expect(() => ms.quote(SaleRequest(memberId: m.id, planId: plan.id, discount: -100)), throwsA(isA<GymException>()));
      expect(() => ms.quote(SaleRequest(memberId: m.id, planId: plan.id, discountPct: 150)), throwsA(isA<GymException>()));
      await expectLater(
          ms.sell(SaleRequest(memberId: m.id, planId: plan.id, payments: const [PayInput(100, PayMethod.cash)], installments: [
            Installment(due: g.today, amount: 450),
            Installment(due: g.today, amount: -50),
          ])),
          throwsA(isA<GymException>()));
    });

    test('خصومات أكبر من السعر: الفاتورة صفر لا سالبة', () async {
      final (g, _) = await newGym();
      final plan = await addPlan(g, price: 100);
      final ms = MembershipService(g);
      final m = await ms.addMember(ms.newMember(name: 'x', phone: '0591000002'));
      final r = await ms.sell(SaleRequest(memberId: m.id, planId: plan.id, discount: 100, discountPct: 50));
      expect(r.invoice.total, 0);
      expect(r.invoice.balance, 0);
      expect(r.subscription.discount, 100);
    });

    test('الضريبة المضافة: إجمالي شاشة البيع = إجمالي الفاتورة، والدفع الكامل لا يترك ديناً', () async {
      final (g, _) = await newGym();
      g.settings
        ..taxEnabled = true
        ..taxInclusive = false
        ..taxRate = 16;
      final plan = await addPlan(g, price: 1000);
      final ms = MembershipService(g);
      final m = await ms.addMember(ms.newMember(name: 'x', phone: '0591000003'));
      final q = ms.quote(SaleRequest(memberId: m.id, planId: plan.id));
      expect(q.tax, 160);
      expect(q.total, 1160);
      final r = await ms.sell(SaleRequest(memberId: m.id, planId: plan.id, payments: [PayInput(q.total, PayMethod.cash)]));
      expect(r.invoice.total, 1160);
      expect(r.invoice.balance, 0);
      // تقسيط: المدفوع + الأقساط = الإجمالي مع الضريبة
      final m2 = await ms.addMember(ms.newMember(name: 'y', phone: '0591000004'));
      final r2 = await ms.sell(SaleRequest(memberId: m2.id, planId: plan.id, payments: const [PayInput(160, PayMethod.cash)],
          installments: [Installment(due: g.today.add(const Duration(days: 30)), amount: 1000)]));
      expect(r2.invoice.balance, 1000);
      // المتجر لزائر بدون عضو: يُدفع الإجمالي مع الضريبة فلا يُرفض البيع
      final p = Product(id: 'w', name: 'مياه', price: 10, stock: 10);
      await g.put(p);
      final inv = await BillingService(g).sellProducts([CartLine(p, 2)], customerName: 'زائر',
          payments: [PayInput(ms.totalWithTax(20), PayMethod.cash)]);
      expect(inv.total, 23.2);
      expect(inv.balance, 0);
    });
  });

  group('التواريخ', () {
    test('مواليد 29 فبراير يُهنَّؤون في 28 فبراير في السنوات غير الكبيسة', () {
      final m = Member(id: 'm', code: 1, name: 'x', phone: '1', birthDate: DateTime(2000, 2, 29), cardToken: 't', createdAt: DateTime(2020));
      expect(m.isBirthday(DateTime(2027, 2, 28)), isTrue);
      expect(m.isBirthday(DateTime(2028, 2, 28)), isFalse);
      expect(m.isBirthday(DateTime(2028, 2, 29)), isTrue);
    });

    test('تعديل نهاية الاشتراك قبل بدايته يُرفض', () async {
      final (g, _) = await newGym();
      final plan = await addPlan(g);
      final ms = MembershipService(g);
      final m = await ms.addMember(ms.newMember(name: 'x', phone: '0591000005'));
      final s = (await ms.sell(SaleRequest(memberId: m.id, planId: plan.id))).subscription;
      await expectLater(ms.adjustEnd(s, s.start.subtract(const Duration(days: 1)), 'خطأ'), throwsA(isA<GymException>()));
    });

    test('أوقات السيدات التي تتجاوز منتصف الليل', () async {
      final (g, clock) = await newGym(DateTime(2026, 9, 29, 23, 30));
      g.settings.genderWindows = [GenderWindow(gender: 'f', weekdays: [], from: 20 * 60, to: 60)];
      final ms = MembershipService(g);
      final plan = await addPlan(g);
      final man = await ms.addMember(ms.newMember(name: 'رجل', phone: '0591000006', gender: Gender.male));
      await ms.sell(SaleRequest(memberId: man.id, planId: plan.id));
      final cs = CheckinService(g);
      expect(cs.evaluate(man).result, CheckinResult.genderHours);
      clock.now = DateTime(2026, 9, 30, 0, 30);
      expect(cs.evaluate(man).result, CheckinResult.genderHours);
      clock.now = DateTime(2026, 9, 30, 9);
      expect(cs.evaluate(man).allowed, isTrue);
    });
  });

  test('الإعدادات لا تقبل قيماً غير منطقية', () {
    final s = GymSettings()
      ..taxRate = 250
      ..maxDiscountPct = -5
      ..graceDays = -3
      ..sessionMinutes = 0
      ..debtLimit = -100;
    s.setReminderDays('expiry_soon', [3, -1, 7, 3, 1]);
    expect(s.taxRate, 100);
    expect(s.maxDiscountPct, 0);
    expect(s.graceDays, 0);
    expect(s.sessionMinutes, 10);
    expect(s.debtLimit, 0);
    expect(s.reminderDays('expiry_soon'), [7, 3, 1]);
  });

  testWidgets('تاريخ الميلاد: من 1920 حتى اليوم، ويبدأ باختيار السنة', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Builder(builder: (c) => TextButton(onPressed: () => pickBirthDate(c, null, DateTime(2026, 9, 29)), child: const Text('go'))),
    ));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    final dlg = t.widget<DatePickerDialog>(find.byType(DatePickerDialog));
    expect(dlg.firstDate, DateTime(1920));
    expect(dlg.lastDate, DateTime(2026, 9, 29));
    expect(dlg.initialCalendarMode, DatePickerMode.year);
    // تاريخ مبدئي خارج المدى لا يعطّل المنتقي
    Navigator.of(t.element(find.byType(DatePickerDialog))).pop();
    await t.pumpAndSettle();
    await t.pumpWidget(MaterialApp(
      home: Builder(builder: (c) => TextButton(onPressed: () => pickDay(c, DateTime(1990), first: DateTime(2020)), child: const Text('go2'))),
    ));
    await t.tap(find.text('go2'));
    await t.pumpAndSettle();
    expect(t.widget<DatePickerDialog>(find.byType(DatePickerDialog)).initialDate, DateTime(2020));
  });
}
