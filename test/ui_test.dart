import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nadi_gym/core/i18n.dart';
import 'package:nadi_gym/services/demo_data.dart';
import 'package:nadi_gym/services/sync.dart';
import 'package:nadi_gym/ui/app.dart';
import 'package:nadi_gym/ui/screens/sync_screen.dart';

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

  testWidgets('جوال قديم صغير الشاشة (720×1280، خط مكبّر): كل الشاشات بدون تجاوز', (t) async {
    t.view.physicalSize = const Size(720, 1280);
    t.view.devicePixelRatio = 2.0;
    t.platformDispatcher.textScaleFactorTestValue = 1.15;
    addTearDown(t.view.reset);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    final (g, _) = (await t.runAsync(() => newGym(DateTime(2026, 9, 29, 18, 30))))!;
    await t.runAsync(() => DemoData(g).generate(members: 60));
    g.settings.onboarded = true;
    await t.pumpWidget(GymApp(gym: g, startBackground: false));
    await tour(t, (name) async {});
    expect(t.takeException(), isNull);
  });

  testWidgets('شاشة المزامنة بعد التفعيل: الحالة ورمز ربط جهاز جديد', (t) async {
    t.view.physicalSize = const Size(720, 1280);
    t.view.devicePixelRatio = 2.0;
    addTearDown(t.view.reset);
    final (g, _) = (await t.runAsync(() => newGym(DateTime(2026, 9, 29, 18, 30))))!;
    await t.runAsync(() => DemoData(g).generate(members: 10));
    g.settings.onboarded = true;
    final sync = SyncService(g, backend: MemorySyncBackend());
    await t.runAsync(() async {
      await sync.load();
      await sync.create(url: 'mem://', key: 'k');
    });
    expect(sync.phase, SyncPhase.synced);
    await t.pumpWidget(GymApp(gym: g, startBackground: false, sync: sync));
    await pumpFor(t, 1000);
    await tap(t, find.byIcon(Icons.cloud_done_outlined));
    await waitFor(t, find.text('متزامن'));
    expect(find.byType(SyncScreen), findsOneWidget);
    await t.scrollUntilVisible(find.text('الجهاز الرئيسي'), 200,
        scrollable: find.descendant(of: find.byType(SyncScreen), matching: find.byType(Scrollable)).first);
    await tap(t, find.text('إضافة جهاز'));
    expect(find.text('رمز ربط جهاز جديد'), findsOneWidget);
    expect(find.textContaining('NS1.'), findsOneWidget);
    await tap(t, find.text('تم'));
    expect(t.takeException(), isNull);
  });

  testWidgets('جولة على شاشة الكمبيوتر (ويندوز)', (t) async {
    t.view.physicalSize = const Size(1280, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final (g, _) = (await t.runAsync(() => newGym(DateTime(2026, 9, 29, 18, 30))))!;
    await t.runAsync(() => DemoData(g).generate(members: 40));
    g.settings.onboarded = true;
    await t.pumpWidget(GymApp(gym: g, startBackground: false));
    await tour(t, (name) async {});
    expect(t.takeException(), isNull);
  });

  testWidgets('الواجهة بالإنجليزية', (t) async {
    t.view.physicalSize = const Size(412 * 2.6, 915 * 2.6);
    t.view.devicePixelRatio = 2.6;
    addTearDown(t.view.reset);
    final (g, _) = (await t.runAsync(() => newGym(DateTime(2026, 9, 29, 18, 30))))!;
    await t.runAsync(() => DemoData(g).generate(members: 20));
    g.settings
      ..onboarded = true
      ..language = 'en';
    g.applySettings();
    addTearDown(() => I18n.lang = 'ar');
    await t.pumpWidget(GymApp(gym: g, startBackground: false));
    await pumpFor(t, 1000);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Active members'), findsOneWidget);
    await t.tap(find.text('Members'));
    await pumpFor(t, 1000);
    expect(find.text('Search by name, phone or member number'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('شاشة الإعداد الأولى على جوال قديم (360×592): زر التجربة يُوصل إليه بالتمرير', (t) async {
    t.view.physicalSize = const Size(720, 1184);
    t.view.devicePixelRatio = 2.0;
    addTearDown(t.view.reset);
    final (g, _) = (await t.runAsync(() => newGym()))!;
    await t.pumpWidget(GymApp(gym: g, startBackground: false));
    await pumpFor(t, 500);
    final demo = find.text('جرّب ببيانات نادٍ تجريبي');
    await t.scrollUntilVisible(demo, 250, scrollable: find.byType(Scrollable).first);
    expect(demo.hitTestable(), findsOneWidget);
    expect(find.text('ناديك مسجّل على جهاز آخر؟ اربط هذا الجهاز'), findsOneWidget);
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

  testWidgets('المحاسبة بالإنجليزية: إغلاق الصندوق من النافذة وقائمة الدخل', (t) async {
    t.view.physicalSize = const Size(720, 1280);
    t.view.devicePixelRatio = 2.0;
    addTearDown(t.view.reset);
    final (g, _) = (await t.runAsync(() => newGym(DateTime(2026, 9, 29, 18, 30))))!;
    await t.runAsync(() => DemoData(g).generate(members: 20));
    g.settings
      ..onboarded = true
      ..language = 'en';
    g.applySettings();
    addTearDown(() => I18n.lang = 'ar');
    await t.pumpWidget(GymApp(gym: g, startBackground: false));
    await pumpFor(t, 1000);
    await tap(t, navItem('More'));
    await tap(t, find.text('Accounting & audit').last);
    await waitFor(t, find.text("Close today's cash drawer"));
    await tap(t, find.widgetWithText(FilledButton, 'Close cash drawer'));
    await t.enterText(find.widgetWithText(TextField, 'Counted amount'), '0');
    await tap(t, find.widgetWithText(FilledButton, 'Save'));
    await pumpFor(t, 1000);
    expect(g.closes.all, hasLength(1));
    await tap(t, find.widgetWithText(Tab, 'Income statement'));
    expect(find.text('Net revenue'), findsOneWidget);
    await tap(t, find.widgetWithText(Tab, 'Balances'));
    expect(find.text('Where the money is now'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
