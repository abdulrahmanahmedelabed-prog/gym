import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nadi_gym/services/membership.dart';
import 'package:nadi_gym/services/sync.dart';

import 'helpers.dart';

/// اختبار على خادم مزامنة حقيقي (Supabase بعد تنفيذ server/supabase_sync.sql).
/// يعمل فقط عند ضبط المتغيرين: NADI_SYNC_URL و NADI_SYNC_KEY
///   NADI_SYNC_URL=https://xxxx.supabase.co NADI_SYNC_KEY=eyJ... flutter test test/sync_server_test.dart
void main() {
  final url = Platform.environment['NADI_SYNC_URL'] ?? '';
  final key = Platform.environment['NADI_SYNC_KEY'] ?? '';
  test('مزامنة جهازين عبر الخادم الحقيقي', () async {
    final (a, _) = await newGym();
    final sa = SyncService(a);
    await sa.load();
    final ms = MembershipService(a);
    final m = await ms.addMember(ms.newMember(name: 'اختبار الخادم', phone: '0599999999'));
    await sa.create(url: url, key: key);
    expect(sa.lastError, isNull);
    expect(sa.phase, SyncPhase.synced);

    final (b, _) = await newGym();
    final sb = SyncService(b);
    await sb.load();
    await sb.join(sa.joinCode);
    expect(b.members[m.id]?.name, 'اختبار الخادم');

    b.members[m.id]!.name = 'عدّله ب';
    await b.put(b.members[m.id]!);
    expect(await sb.syncNow(), isTrue);
    expect(await sa.syncNow(), isTrue);
    expect(a.members[m.id]!.name, 'عدّله ب');
    expect(sa.devices, 2);

    // رمز خاطئ
    final (c, _) = await newGym();
    final sc = SyncService(c);
    await sc.load();
    final bad = sa.joinCode.substring(0, sa.joinCode.length - 6);
    await expectLater(sc.join(bad), throwsA(anything));
  }, skip: url.isEmpty || key.isEmpty ? 'NADI_SYNC_URL / NADI_SYNC_KEY غير مضبوطين' : false);
}
