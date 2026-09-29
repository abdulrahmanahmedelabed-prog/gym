import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nadi_gym/main.dart' as app;

import 'tour.dart';

/// يعمل على جهاز حقيقي أو محاكي (أندرويد، آيفون، ويندوز): يفتح التطبيق كما يفتحه المستخدم،
/// يبدأ بنادٍ تجريبي، ثم يمر على الشاشات ويلتقط صورها (على أندرويد وآيفون).
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final canShoot = Platform.isAndroid || Platform.isIOS;

  Future<void> shot(String name) async {
    if (!canShoot) return;
    try {
      await binding.takeScreenshot(name);
    } catch (_) {
      // التقاط الصور غير مدعوم على هذه المنصة
    }
  }

  testWidgets('جولة كاملة على الجهاز', (t) async {
    await app.main();
    await pumpFor(t, 2000);
    if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();
    await pumpFor(t, 500);

    // أول تشغيل: شاشة الإعداد. على الجوالات القديمة البطيئة قد يتأخر أول رسم، فننتظر أياً من الشاشتين
    final welcome = find.text('أهلاً بك في نادي جيم');
    final demo = find.text('جرّب ببيانات نادٍ تجريبي');
    await waitFor(t, find.byWidgetPredicate((w) => w is Text && (w.data == 'أهلاً بك في نادي جيم' || w.data == 'الرئيسية')), seconds: 120);
    if (welcome.evaluate().isNotEmpty) {
      await shot('00_onboarding');
      // الشاشة الصغيرة (جوال قديم): الزر في أسفل القائمة فننزل إليه
      await t.scrollUntilVisible(demo, 250, scrollable: find.byType(Scrollable).first);
      await pumpFor(t, 300);
      await t.tap(demo);
      await waitFor(t, navItem('الرئيسية'), seconds: 180);
    }
    await tour(t, (name) async {
      await pumpFor(t, 300);
      await shot(name);
    });
    expect(navItem('الرئيسية'), findsOneWidget);
  });
}
