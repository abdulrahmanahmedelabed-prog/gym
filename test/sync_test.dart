import 'package:flutter_test/flutter_test.dart';
import 'package:nadi_gym/data/gym_data.dart';
import 'package:nadi_gym/models/billing.dart';
import 'package:nadi_gym/models/plan.dart';
import 'package:nadi_gym/services/billing.dart';
import 'package:nadi_gym/services/checkin.dart';
import 'package:nadi_gym/services/license.dart';
import 'package:nadi_gym/services/membership.dart';
import 'package:nadi_gym/services/sync.dart';
import 'package:sembast/sembast.dart';

import 'helpers.dart';

/// جهازان (أو أكثر) لنفس النادي على خادم في الذاكرة بنفس قواعد الخادم الحقيقي
Future<(GymData, SyncService)> device(MemorySyncBackend server) async {
  final (g, _) = await newGym();
  final s = SyncService(g, backend: server);
  await s.load();
  return (g, s);
}

void main() {
  group('المزامنة السحابية (تعمل بدون نت وتتزامن عند عودته)', () {
    test('جهاز ثانٍ ينضم فيستلم كل بيانات النادي والإعدادات، والإعدادات المحلية لا تنتقل', () async {
      final server = MemorySyncBackend();
      final (a, sa) = await device(server);
      a.settings.gymName = 'نادي الأبطال';
      a.settings.themeMode = 'dark';
      await a.saveSettings();
      final plan = await addPlan(a);
      final ms = MembershipService(a);
      final m = await ms.addMember(ms.newMember(name: 'أحمد', phone: '0591234567'));
      await ms.sell(SaleRequest(memberId: m.id, planId: plan.id, payments: const [PayInput(600, PayMethod.cash)]));

      await sa.create(url: 'mem://', key: 'k');
      expect(sa.phase, SyncPhase.synced);
      expect(sa.pending, 0);

      final (b, sb) = await device(server);
      await b.put(plan); // بيانات محلية قديمة تُستبدل عند الانضمام
      await sb.join(sa.joinCode);
      expect(sb.enabled, isTrue);
      expect(sb.isMain, isFalse);
      expect(b.members.items.keys, [m.id]);
      expect(b.invoices.all.single.paid, 600);
      expect(b.subs.all.length, 1);
      expect(b.settings.gymName, 'نادي الأبطال');
      expect(b.settings.themeMode, isNot('dark'));
    });

    test('العمل بدون نت على جهازين ثم الدمج: لا يضيع شيء ولا تتكرر أرقام الفواتير', () async {
      final server = MemorySyncBackend();
      final (a, sa) = await device(server);
      final plan = await addPlan(a);
      await sa.create(url: 'mem://', key: 'k');
      final (b, sb) = await device(server);
      await sb.join(sa.joinCode);

      server.online = false;
      final msA = MembershipService(a), msB = MembershipService(b);
      final ma = await msA.addMember(msA.newMember(name: 'من الجهاز أ', phone: '0590000001'));
      final mb = await msB.addMember(msB.newMember(name: 'من الجهاز ب', phone: '0590000002'));
      final ra = await msA.sell(SaleRequest(memberId: ma.id, planId: plan.id));
      final rb = await msB.sell(SaleRequest(memberId: mb.id, planId: plan.id));

      expect(await sa.syncNow(), isFalse);
      expect(sa.phase, SyncPhase.offline);
      expect(sa.pending, greaterThan(0));
      // التطبيق يعمل عادياً بدون نت
      expect(a.members.items.length, 1);

      server.online = true;
      expect(await sa.syncNow(), isTrue);
      expect(await sb.syncNow(), isTrue);
      expect(await sa.syncNow(), isTrue);
      for (final g in [a, b]) {
        expect(g.members.items.length, 2);
        expect(g.invoices.items.length, 2);
      }
      expect(ra.invoice.number, isNot(rb.invoice.number));
      expect(ma.code, isNot(mb.code));
      expect(sa.pending, 0);
      expect(sb.pending, 0);
      // بعد الدمج: الرقم التالي أكبر من كل ما استُخدم في أي جهاز
      final next = await msA.addMember(msA.newMember(name: 'جديد', phone: '0590000003'));
      expect(next.code, greaterThan(mb.code > ma.code ? mb.code : ma.code));
    });

    test('دفعتان على نفس الفاتورة من جهازين بدون نت: المدفوع = مجموع الدفعات', () async {
      final server = MemorySyncBackend();
      final (a, sa) = await device(server);
      final plan = await addPlan(a);
      final ms = MembershipService(a);
      final m = await ms.addMember(ms.newMember(name: 'x', phone: '0590000010'));
      final inv = (await ms.sell(SaleRequest(memberId: m.id, planId: plan.id))).invoice;
      await sa.create(url: 'mem://', key: 'k');
      final (b, sb) = await device(server);
      await sb.join(sa.joinCode);

      server.online = false;
      await BillingService(a).collect(a.invoices[inv.id]!, 200, PayMethod.cash);
      await BillingService(b).collect(b.invoices[inv.id]!, 100, PayMethod.wallet);
      server.online = true;
      await sa.syncNow();
      await sb.syncNow();
      await sa.syncNow();
      expect(a.invoices[inv.id]!.paid, 300);
      expect(b.invoices[inv.id]!.paid, 300);
      expect(a.balanceOf(m.id), 300);
      expect(b.balanceOf(m.id), 300);
    });

    test('دخول نفس العضو (باقة حصص) من جهازين بدون نت: الحصص المستخدمة 2', () async {
      final server = MemorySyncBackend();
      final (a, sa) = await device(server);
      final plan = await addPlan(a, kind: PlanKind.visits, visits: 12, dailyLimit: 5);
      final ms = MembershipService(a);
      final m = await ms.addMember(ms.newMember(name: 'x', phone: '0590000020'));
      final sub = (await ms.sell(SaleRequest(memberId: m.id, planId: plan.id, payments: const [PayInput(600, PayMethod.cash)]))).subscription;
      await sa.create(url: 'mem://', key: 'k');
      final (b, sb) = await device(server);
      await sb.join(sa.joinCode);

      server.online = false;
      final ca = CheckinService(a), cb = CheckinService(b);
      await ca.commit(ca.evaluate(a.members[m.id]));
      await cb.commit(cb.evaluate(b.members[m.id]));
      server.online = true;
      await sa.syncNow();
      await sb.syncNow();
      await sa.syncNow();
      expect(a.subs[sub.id]!.visitsUsed, 2);
      expect(b.subs[sub.id]!.visitsUsed, 2);
      expect(a.checkins.items.length, 2);

      // تعديل المدير اليدوي يبقى صحيحاً بعد المزامنة
      await MembershipService(a).adjustVisits(a.subs[sub.id]!, 5, 'تصحيح');
      await sa.syncNow();
      await sb.syncNow();
      expect(b.subs[sub.id]!.visitsUsed, 5);
    });

    test('الحذف والتعديل الأحدث ينتقلان، والتعديل المحلي الأحدث لا يُستبدل', () async {
      final server = MemorySyncBackend();
      final (a, sa) = await device(server);
      final ms = MembershipService(a);
      final m1 = await ms.addMember(ms.newMember(name: 'يُحذف', phone: '0590000030'));
      final m2 = await ms.addMember(ms.newMember(name: 'قديم', phone: '0590000031'));
      await sa.create(url: 'mem://', key: 'k');
      final (b, sb) = await device(server);
      await sb.join(sa.joinCode);

      await a.remove(a.members[m1.id]!);
      await sa.syncNow();
      a.members[m2.id]!.name = 'من أ';
      await a.put(a.members[m2.id]!);
      await sa.syncNow();
      await sb.syncNow();
      expect(b.members[m2.id]!.name, 'من أ');
      // ب يعدّل بعد رؤية تعديل أ، فتعديله هو الأحدث حتى لو كانت ساعة جواله متأخرة
      a.clock = () => DateTime(2020);
      b.clock = () => DateTime(2020);
      b.members[m2.id]!.name = 'من ب';
      await b.put(b.members[m2.id]!);
      await sb.syncNow();
      await sa.syncNow();
      expect(b.members[m1.id], isNull);
      expect(a.members[m2.id]!.name, 'من ب');
      expect(b.members[m2.id]!.name, 'من ب');
    });

    test('Plus: جهازان فقط؛ الجهاز الثالث يحتاج Pro. والمجانية لا تزامن', () async {
      final server = MemorySyncBackend();
      final (a, sa) = await device(server);
      a.license.debugTier = Tier.plus;
      await sa.create(url: 'mem://', key: 'k');
      final (b, sb) = await device(server);
      b.license.debugTier = Tier.plus;
      await sb.join(sa.joinCode);
      final (c, sc) = await device(server);
      c.license.debugTier = Tier.plus;
      await expectLater(sc.join(sa.joinCode), throwsA(isA<LicenseException>()));
      expect(await sa.syncNow(), isFalse);
      expect(sa.phase, SyncPhase.locked);
      a.license.debugTier = Tier.pro;
      expect(await sa.syncNow(), isTrue);

      final (f, sf) = await device(server);
      f.license.debugTier = Tier.free;
      await expectLater(sf.join(sa.joinCode), throwsA(isA<LicenseException>()));
      expect(f.syncDevice, isNull);
    });

    test('إيقاف المزامنة أو مسح البيانات على جهاز لا يمس السحابة', () async {
      final server = MemorySyncBackend();
      final (a, sa) = await device(server);
      final ms = MembershipService(a);
      await ms.addMember(ms.newMember(name: 'باقٍ', phone: '0590000040'));
      await sa.create(url: 'mem://', key: 'k');
      final (b, sb) = await device(server);
      await sb.join(sa.joinCode);
      await b.wipe();
      expect(sb.enabled, isFalse);
      await sa.syncNow();
      expect(a.members.items.length, 1);
      final (c, sc) = await device(server);
      await sc.join(sa.joinCode);
      expect(c.members.items.length, 1);
    });

    test('تعديل محلي لم يُرفع وهو أحدث لا يستبدله القادم الأقدم', () async {
      final (g, _) = await newGym();
      g.syncDevice = 'me';
      final ms = MembershipService(g);
      final m = await ms.addMember(ms.newMember(name: 'محلي', phone: '0590000050'));
      final older = RemoteRecord('members', m.id, {...m.toMap(), 'name': 'قديم'}, g.hlc - 1000, 'other');
      expect(await g.applyRemote([older]), 0);
      expect(g.members[m.id]!.name, 'محلي');
      expect(await g.pendingCount(), greaterThan(0));
      final newer = RemoteRecord('members', m.id, {...m.toMap(), 'name': 'أحدث'}, g.hlc + 1000, 'other');
      expect(await g.applyRemote([newer]), 1);
      expect(g.members[m.id]!.name, 'أحدث');
      expect((await GymData.outbox.record('members/${m.id}').get(g.db)), isNull);
    });

    test('رمز الربط', () {
      expect(() => SyncService.parseJoinCode('abc'), throwsA(isA<GymException>()));
      final c = SyncService.parseJoinCode('NS1.eyJnIjoiR1lNMTIzNDU2NzgiLCJzIjoic2VjcmV0c2VjcmV0c2VjcmV0c2VjcmV0IiwidSI6Imh0dHBzOi8veC5zdXBhYmFzZS5jbyIsImsiOiJrZXkifQ');
      expect(c.gym, 'GYM12345678');
      expect(c.url, 'https://x.supabase.co');
    });
  });
}
