import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nadi_gym/main.dart' as app;

import 'tour.dart';

/// يعمل على محاكي أندرويد حقيقي: يفتح التطبيق كما يفتحه المستخدم، يبدأ بنادٍ تجريبي، ثم يمر على الشاشات ويلتقط صورها.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('جولة كاملة على المحاكي', (t) async {
    await app.main();
    await pumpFor(t, 2000);
    await binding.convertFlutterSurfaceToImage();
    await pumpFor(t, 500);

    // أول تشغيل: شاشة الإعداد
    final demo = find.text('جرّب ببيانات نادٍ تجريبي');
    if (demo.evaluate().isNotEmpty) {
      await binding.takeScreenshot('00_onboarding');
      await t.tap(demo);
      await waitFor(t, find.byType(NavigationBar), seconds: 120);
    }
    await tour(t, (name) async {
      await pumpFor(t, 300);
      await binding.takeScreenshot(name);
    });
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
