import 'package:flutter_test/flutter_test.dart';
import 'package:nadi_gym/core/dates.dart';
import 'package:nadi_gym/core/vendor.dart';
import 'package:nadi_gym/models/billing.dart';
import 'package:nadi_gym/models/member.dart';
import 'package:nadi_gym/services/license.dart';
import 'package:nadi_gym/services/membership.dart';
import 'package:nadi_gym/services/messaging.dart';
import 'package:nadi_gym/services/reminders.dart';

import 'helpers.dart';
import 'license_keys.dart';

void main() {
  test('التجربة Pro ثم المجاني بعد انتهاء المدة', () async {
    final (g, clock) = await newGym(null, true);
    expect(g.license.status().state, LicenseState.trial);
    expect(g.license.tier, Tier.pro);
    expect(g.has(Feature.classes), isTrue);
    clock.advance(days: Vendor.trialDays);
    expect(g.license.status().state, LicenseState.free);
    expect(g.license.tier, Tier.free);
    expect(g.has(Feature.installments), isFalse);
    expect(g.has(Feature.autoReminders), isFalse);
  });

  test('إرجاع ساعة الجهاز لا يعيد التجربة', () async {
    final (g, clock) = await newGym(null, true);
    clock.advance(days: Vendor.trialDays + 5);
    expect(g.license.tier, Tier.free);
    clock.advance(days: -(Vendor.trialDays + 5));
    expect(g.license.tier, Tier.free);
  });

  test('التحقق من المفاتيح: الجهاز والصلاحية والتزوير', () async {
    final (g, clock) = await newGym(null, true);
    g.license
      ..testN = testN
      ..testE = testE
      ..deviceCode = 'TEST-DEVI-CE01';
    await expectLater(g.license.activate(keyOtherDevice), throwsA(isA<LicenseException>()));
    await expectLater(g.license.activate(keyExpired), throwsA(isA<LicenseException>()));
    // تعديل حرف واحد يُبطل التوقيع
    final forged = keyPlusForever.replaceRange(20, 21, keyPlusForever[20] == 'A' ? 'B' : 'A');
    await expectLater(g.license.activate(forged), throwsA(isA<LicenseException>()));
    final st = await g.license.activate(keyPlusForever);
    expect(st.state, LicenseState.licensed);
    expect(st.tier, Tier.plus);
    expect(st.expires, isNull);
    expect(g.has(Feature.installments), isTrue);
    expect(g.has(Feature.classes), isFalse);
    await g.license.activate(keyPro2027);
    expect(g.license.tier, Tier.pro);
    clock.now = DateTime(2027, 4, 1);
    final exp = g.license.status();
    expect(exp.state, LicenseState.expired);
    expect(exp.tier, Tier.free);
  });

  test('المفتاح الحقيقي في التطبيق يقبل مفاتيح أداة البائع فقط', () {
    expect(() => parseLicenseKey(keyPro2027), throwsA(isA<LicenseException>()));
  });

  test('النسخة المجانية: حد الأعضاء والمزايا المقفلة', () async {
    final (g, clock) = await newGym(null, true);
    clock.advance(days: Vendor.trialDays);
    final ms = MembershipService(g);
    final plan = await addPlan(g);
    for (var i = 0; i < Vendor.freeMemberLimit; i++) {
      final m = await ms.addMember(ms.newMember(name: 'عضو $i', phone: '05900${(10000 + i)}'));
      await ms.sell(SaleRequest(memberId: m.id, planId: plan.id));
    }
    final extra = await ms.addMember(ms.newMember(name: 'زائد', phone: '0599999999'));
    await expectLater(ms.sell(SaleRequest(memberId: extra.id, planId: plan.id)), throwsA(isA<LicenseException>()));
    // تجديد عضو فعّال مسموح
    final first = g.members.all.firstWhere((m) => m.name == 'عضو 0');
    await ms.sell(SaleRequest(memberId: first.id, planId: plan.id));
    // التقسيط مقفل
    await expectLater(
        ms.sell(SaleRequest(
            memberId: first.id,
            planId: plan.id,
            payments: const [PayInput(300, PayMethod.cash)],
            installments: [Installment(due: addDays(g.today, 30), amount: 300)])),
        throwsA(isA<LicenseException>()));
    // التذكيرات الآلية والإرسال الآلي مقفلان
    expect(await ReminderEngine(g).run(force: true), 0);
    g.settings.smsMode = 'sim';
    expect(Dispatcher(g).isAuto(Channel.sms), isFalse);
  });
}
