import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nadi_gym/services/demo_data.dart';
import 'package:nadi_gym/ui/app.dart';

import '../integration_test/tour.dart';
import 'helpers.dart';

/// اختبار الواجهة: يمر على كل الشاشات ببيانات تجريبية على شاشة بحجم الجوال.
/// أي خطأ رسم أو تجاوز للمساحة (overflow) يُفشل الاختبار.
void main() {
  testWidgets('جولة على كل الشاشات بدون أخطاء', (t) async {
    t.view.physicalSize = const Size(412 * 2.6, 915 * 2.6);
    t.view.devicePixelRatio = 2.6;
    addTearDown(t.view.reset);

    final (g, _) = (await t.runAsync(() => newGym(DateTime(2026, 9, 29, 18, 30))))!;
    await t.runAsync(() => DemoData(g).generate(members: 60));
    g.settings.onboarded = true;

    await t.pumpWidget(GymApp(gym: g, startBackground: false));
    await tour(t, (name) async {});
    expect(t.takeException(), isNull);
  });

  testWidgets('شاشة الإعداد الأولى', (t) async {
    t.view.physicalSize = const Size(412 * 2.6, 915 * 2.6);
    t.view.devicePixelRatio = 2.6;
    addTearDown(t.view.reset);
    final (g, _) = (await t.runAsync(() => newGym()))!;
    await t.pumpWidget(GymApp(gym: g, startBackground: false));
    await t.pump();
    expect(find.text('ابدأ'), findsOneWidget);
    expect(find.text('جرّب ببيانات نادٍ تجريبي'), findsOneWidget);
  });
}
