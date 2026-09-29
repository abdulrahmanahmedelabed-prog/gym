import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nadi_gym/ui/screens/checkin_screen.dart';
import 'package:nadi_gym/ui/screens/finance_screen.dart';
import 'package:nadi_gym/ui/screens/member_detail_screen.dart';
import 'package:nadi_gym/ui/screens/members_screen.dart';
import 'package:nadi_gym/ui/screens/more_screen.dart';
import 'package:nadi_gym/ui/screens/settings_screen.dart';
import 'package:nadi_gym/ui/screens/sync_screen.dart';

/// جولة على كل شاشات التطبيق بخطوات يستخدمها المستخدم فعلاً.
/// تُشغَّل كاختبار عادي (flutter test) وعلى محاكي أندرويد حقيقي (مع صور الشاشات).
typedef Snap = Future<void> Function(String name);

Future<void> pumpFor(WidgetTester t, [int ms = 600]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> waitFor(WidgetTester t, Finder f, {int seconds = 60}) async {
  for (var i = 0; i < seconds * 5; i++) {
    if (f.evaluate().isNotEmpty) return;
    await t.pump(const Duration(milliseconds: 200));
  }
  throw TestFailure('لم يظهر: $f');
}

/// عنصر التنقل: الشريط السفلي على الجوال أو الجانبي على الشاشات الكبيرة
Finder navItem(String label) =>
    find.descendant(of: find.byWidgetPredicate((w) => w is NavigationBar || w is NavigationRail), matching: find.text(label));

Future<void> tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f.first);
  await pumpFor(t, 300);
  await t.tap(f.first, warnIfMissed: false);
  await pumpFor(t);
}

Future<void> back(WidgetTester t) async {
  await t.state<NavigatorState>(find.byType(Navigator).first).maybePop();
  await pumpFor(t);
}

Future<void> tour(WidgetTester t, Snap snap) async {
  // الرئيسية
  await waitFor(t, navItem('الرئيسية'));
  await pumpFor(t, 1500);
  await snap('01_dashboard');

  // الأعضاء ثم ملف أول عضو فعّال
  await tap(t, navItem('الأعضاء'));
  await snap('02_members');
  final members = find.byType(MembersScreen);
  await tap(t, find.descendant(of: members, matching: find.widgetWithText(ChoiceChip, 'فعّال')));
  await tap(t, find.descendant(of: members, matching: find.byType(ListTile)));
  await waitFor(t, find.byType(MemberDetailScreen));
  await snap('03_member_profile');

  // التجديد
  final profile = find.byType(MemberDetailScreen);
  await tap(t, find.descendant(of: profile, matching: find.text('تجديد')));
  await waitFor(t, find.text('الباقة'));
  await snap('04_renew');
  await back(t);

  // بطاقة العضو
  await tap(t, find.descendant(of: profile, matching: find.text('البطاقة')));
  await pumpFor(t, 800);
  await snap('05_member_card');
  await tap(t, find.text('إغلاق'));
  await back(t);

  // الدخول: بحث بالاسم وتسجيل
  await tap(t, navItem('الدخول'));
  final checkin = find.byType(CheckinScreen);
  await t.enterText(find.descendant(of: checkin, matching: find.byType(TextField)).first, 'أحمد');
  await pumpFor(t);
  await snap('06_checkin_search');
  final tiles = find.descendant(of: checkin, matching: find.byType(ListTile));
  if (tiles.evaluate().isNotEmpty) {
    await tap(t, tiles.first);
    await pumpFor(t, 800);
    await snap('07_checkin_result');
  }

  // المالية والفاتورة
  await tap(t, navItem('المالية'));
  await snap('08_invoices');
  final finance = find.byType(FinanceScreen);
  await tap(t, find.descendant(of: finance, matching: find.text('الأقساط')));
  await snap('09_installments');
  await tap(t, find.descendant(of: finance, matching: find.text('الفواتير')));
  await tap(t, find.descendant(of: finance, matching: find.textContaining('INV-')));
  await waitFor(t, find.text('الدفعات'));
  await snap('10_invoice');
  await back(t);

  // المزيد
  await tap(t, navItem('المزيد'));
  await snap('11_more');
  Finder more(String label) => find.descendant(of: find.byType(MoreScreen), matching: find.text(label));

  await tap(t, more('الرسائل والتذكيرات'));
  await snap('12_messages');
  await back(t);

  await tap(t, more('التقارير'));
  await pumpFor(t, 800);
  await snap('13_reports');
  await back(t);

  await tap(t, more('الحصص والحجوزات'));
  await snap('14_classes');
  await back(t);

  await tap(t, more('المتجر والمخزون'));
  await snap('15_shop');
  await back(t);

  await tap(t, more('الباقات والأسعار'));
  await snap('16_plans');
  await back(t);

  await tap(t, more('العملاء المحتملون'));
  await snap('17_leads');
  await back(t);

  await tap(t, more('الإعدادات'));
  await tap(t, find.descendant(of: find.byType(SettingsScreen), matching: find.text('الرسائل والتذكيرات')));
  await snap('18_messaging_settings');
  await back(t);
  await tap(t, find.descendant(of: find.byType(SettingsScreen), matching: find.text('المزامنة السحابية')));
  await waitFor(t, find.byType(SyncScreen));
  await pumpFor(t, 500);
  await snap('19_cloud_sync');
  await back(t);
  await back(t);
}
