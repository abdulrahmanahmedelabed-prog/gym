import 'package:flutter_test/flutter_test.dart';
import 'package:nadi_gym/core/dates.dart';
import 'package:nadi_gym/core/ids.dart';
import 'package:nadi_gym/models/activity.dart';
import 'package:nadi_gym/models/billing.dart';
import 'package:nadi_gym/models/member.dart';
import 'package:nadi_gym/services/data_tools.dart';
import 'package:nadi_gym/services/membership.dart';

import 'helpers.dart';

void main() {
  test('التخفيف: يحذف الدخول القديم والرسائل المرسلة القديمة فقط، ولا يمس الفواتير والدفعات', () async {
    final (g, clock) = await newGym(DateTime(2024, 1, 10, 12));
    final plan = await addPlan(g);
    final ms = MembershipService(g);
    final m = await ms.addMember(ms.newMember(name: 'قديم', phone: '0591111111'));
    final old = await ms.sell(SaleRequest(memberId: m.id, planId: plan.id, payments: const [PayInput(600, PayMethod.cash)]));
    Checkin chk(DateTime t, String? sub) =>
        Checkin(id: newId(), memberId: m.id, subscriptionId: sub, time: t, result: CheckinResult.allowed, method: 'manual');
    await g.putAll([chk(DateTime(2024, 1, 12, 18), old.subscription.id), chk(DateTime(2024, 1, 13, 18), null)]);
    Message msg(MsgStatus st) => Message(
        id: newId(), memberId: m.id, name: m.name, phone: m.phone, channel: Channel.whatsapp, kind: 'custom', body: 'x', status: st, createdAt: g.now());
    await g.putAll([msg(MsgStatus.sent), msg(MsgStatus.queued)]);

    // بعد سنتين ونصف: اشتراك جديد ودخول حديث
    clock.setDay(DateTime(2026, 7, 1));
    final fresh = await ms.sell(SaleRequest(memberId: m.id, planId: plan.id, payments: const [PayInput(600, PayMethod.cash)]));
    await g.put(chk(addDays(g.today, -3), fresh.subscription.id));

    final n = await Maintenance(g).prune();
    expect(n, 3); // دخولان قديمان + رسالة مرسلة
    expect(g.checkins.items.length, 1);
    expect(g.messages.all.single.status, MsgStatus.queued);
    expect(g.invoices.items.length, 2);
    expect(g.payments.items.length, 2);
    expect(g.subs.items.length, 2);
    expect(await Maintenance(g).pruneDaily(), 0);
  });
}
