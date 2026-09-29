import 'package:flutter_test/flutter_test.dart';
import 'package:nadi_gym/core/dates.dart';
import 'package:nadi_gym/models/activity.dart';
import 'package:nadi_gym/models/billing.dart';
import 'package:nadi_gym/models/business.dart';
import 'package:nadi_gym/models/settings.dart';
import 'package:nadi_gym/services/billing.dart';
import 'package:nadi_gym/services/membership.dart';
import 'package:nadi_gym/services/reminders.dart';
import 'package:nadi_gym/services/reports.dart';
import 'package:nadi_gym/services/templates.dart';

import 'helpers.dart';

void main() {
  test('العرض يُطبق تلقائياً: نسبة وأيام مجانية، ويمكن إلغاؤه', () async {
    final (g, _) = await newGym();
    final ms = MembershipService(g);
    final quarter = await addPlan(g, name: '3 أشهر', value: 3, price: 400);
    final other = await addPlan(g, name: 'شهري', price: 150);
    await g.put(Offer(id: 'o1', name: 'عرض الخريف', value: 15, bonusDays: 10, planIds: [quarter.id], end: addDays(g.today, 20)));
    final m = await ms.addMember(ms.newMember(name: 'أحمد', phone: '0599000001'));
    final q = ms.quote(SaleRequest(memberId: m.id, planId: quarter.id));
    expect(q.offer!.name, 'عرض الخريف');
    expect(q.total, 340);
    expect(ms.quote(SaleRequest(memberId: m.id, planId: other.id)).offer, isNull);
    expect(ms.quote(SaleRequest(memberId: m.id, planId: quarter.id, useOffer: false)).total, 400);
    final r = await ms.sell(SaleRequest(memberId: m.id, planId: quarter.id));
    expect(r.invoice.total, 340);
    expect(r.subscription.end, addDays(periodEnd(g.today, 3, DurationUnit.month), 10));
  });

  test('خصم يدوي بالنسبة المئوية وعرض بسعر خاص وللجدد فقط', () async {
    final (g, _) = await newGym();
    final ms = MembershipService(g);
    final plan = await addPlan(g, price: 200);
    final m = await ms.addMember(ms.newMember(name: 'x', phone: '0599000002'));
    expect(ms.quote(SaleRequest(memberId: m.id, planId: plan.id, discountPct: 10)).total, 180);
    await g.put(Offer(id: 'o', name: 'افتتاح', type: 'price', value: 120, newMembersOnly: true));
    expect(ms.quote(SaleRequest(memberId: m.id, planId: plan.id)).total, 120);
    await ms.sell(SaleRequest(memberId: m.id, planId: plan.id));
    expect(ms.quote(SaleRequest(memberId: m.id, planId: plan.id)).offer, isNull); // لم يعد جديداً
  });

  test('التجديد شبه التلقائي: فاتورة ورسالة قبل الانتهاء، ويتجدد عند الدفع', () async {
    final (g, clock) = await newGym();
    g.settings.payAccounts = [PayAccount(id: 'a', name: 'جوال باي', number: '0599123456', qr: 'QR')];
    final ms = MembershipService(g);
    final plan = await addPlan(g, price: 150);
    final m = await ms.addMember(ms.newMember(name: 'سارة علي', phone: '0599000003')..autoRenew = true);
    final first = (await ms.sell(SaleRequest(memberId: m.id, planId: plan.id, payments: const [PayInput(150, PayMethod.cash)]))).subscription;
    clock.now = DateTime(2026, 10, 25, 12); // باقي 3 أيام
    await ReminderEngine(g).run();
    final msg = g.messages.all.firstWhere((x) => x.kind == Rk.renewalRequest);
    expect(msg.body, contains('جوال باي: 0599123456'));
    final inv = ms.openRenewalInvoice(m.id)!;
    expect(inv.total, 150);
    expect(inv.pendingPlanId, plan.id);
    expect(ms.renewedAfter(first), isFalse);
    await ReminderEngine(g).run(force: true); // لا تتكرر
    expect(g.messages.all.where((x) => x.kind == Rk.renewalRequest).length, 1);
    expect(g.invoicesOf(m.id).where((i) => i.pendingPlanId != null).length, 1);
    // الدفع بمحفظة غير مؤكد بعد: يتجدد الاشتراك ويبقى في المطابقة
    await BillingService(g).collect(inv, 150, PayMethod.wallet, reference: '778899', account: 'جوال باي', verified: false);
    expect(inv.pendingPlanId, isNull);
    expect(ms.renewedAfter(first), isTrue);
    expect(ms.nextSub(m.id, first)!.start, DateTime(2026, 10, 29));
    expect(BillingService(g).unverified().single.reference, '778899');
  });

  test('المطابقة: تأكيد الوصول، أو عكس دفعة لم تصل', () async {
    final (g, _) = await newGym();
    final ms = MembershipService(g);
    final b = BillingService(g);
    final plan = await addPlan(g, price: 150);
    final m = await ms.addMember(ms.newMember(name: 'x', phone: '0599000004'));
    final r = await ms.sell(SaleRequest(
        memberId: m.id, planId: plan.id, payments: const [PayInput(100, PayMethod.wallet, '111', 'بال باي', false)]));
    final p = r.payments.single;
    expect(p.needsCheck, isTrue);
    expect(p.account, 'بال باي');
    final rep = Reports(g).collectedByAccount(Range.today(g.now()));
    expect(rep['بال باي']!.unverified, 1);
    await b.rejectPayment(p, 'لا يوجد في الكشف');
    expect(r.invoice.balance, 150);
    expect(b.unverified(), isEmpty);
    expect(g.audit.all.any((a) => a.action == 'reject'), isTrue);
    final p2 = await b.collect(r.invoice, 150, PayMethod.transfer, account: 'بنك فلسطين', verified: false);
    await b.verifyPayment(p2);
    expect(p2.verified, isTrue);
    expect(r.invoice.status, InvoiceStatus.paid);
  });

  test('بيانات الدفع في الرسائل تُبنى من حسابات الاستلام', () async {
    final (g, _) = await newGym();
    g.settings.payAccounts = [
      PayAccount(id: 'a', name: 'جوال باي', number: '0599123456', holder: 'النادي'),
      PayAccount(id: 'b', name: 'بال باي', number: '0569123456', active: false),
    ];
    final t = TemplateContext(g).payInfo();
    expect(t, 'جوال باي: 0599123456 (النادي)');
    g.settings.walletInfo = 'نص يدوي';
    expect(TemplateContext(g).payInfo(), 'نص يدوي');
  });

  test('الدفعة النقدية مؤكدة دائماً', () async {
    final (g, _) = await newGym();
    final ms = MembershipService(g);
    final plan = await addPlan(g, price: 100);
    final m = await ms.addMember(ms.newMember(name: 'x', phone: '0599000005'));
    final r = await ms.sell(SaleRequest(memberId: m.id, planId: plan.id, payments: const [PayInput(100, PayMethod.cash, null, null, false)]));
    expect(r.payments.single.verified, isTrue);
    expect(CheckinResult.values, isNotEmpty);
  });
}
