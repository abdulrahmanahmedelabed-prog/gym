import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nadi_gym/models/billing.dart';
import 'package:nadi_gym/services/demo_data.dart';
import 'package:nadi_gym/ui/app.dart';
import 'package:nadi_gym/ui/screens/sale_screen.dart';

import '../integration_test/tour.dart';
import 'helpers.dart';

/// قيمة بطاقة «أعضاء فعّالون» في الرئيسية
int activeKpi(WidgetTester t) {
  final card = find.ancestor(of: find.text('أعضاء فعّالون'), matching: find.byType(Card)).first;
  return int.parse(find.descendant(of: card, matching: find.byType(Text)).evaluate().map((e) => (e.widget as Text).data!).first);
}

/// كما يفعل موظف الاستقبال: عضو جديد ← باقة سنوية ← يدفع 500 بمحفظة بال باي ← يقسّط الباقي
void main() {
  testWidgets('بيع بالمحفظة مع تقسيط الباقي: الحساب المختار يبقى، والأقساط تقسّم الباقي، والعدد يزيد', (t) async {
    t.view.physicalSize = const Size(1280, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final (g, _) = (await t.runAsync(() => newGym(DateTime(2026, 9, 29, 18, 30))))!;
    await t.runAsync(() => DemoData(g).generate());
    await t.pumpWidget(GymApp(gym: g, startBackground: false));
    await pumpFor(t, 1000);
    final before = activeKpi(t);

    await tap(t, find.text('عضو جديد'));
    await t.enterText(find.widgetWithText(TextFormField, 'الاسم الكامل *'), 'عضو تجربة');
    await t.enterText(find.widgetWithText(TextFormField, 'الجوال (واتساب) *'), '0599123456');
    await tap(t, find.text('حفظ ومتابعة للاشتراك'));
    await pumpFor(t, 800);
    final sale = find.byType(SaleScreen);
    final scroll = find.descendant(of: sale, matching: find.byType(Scrollable)).first;
    await tap(t, find.descendant(of: sale, matching: find.text('سنوي')));

    // المحفظة: الانتقال من جوال باي إلى بال باي يبقى
    await t.scrollUntilVisible(find.text('محفظة إلكترونية'), 200, scrollable: scroll);
    await tap(t, find.text('محفظة إلكترونية'));
    ChoiceChip chip(String n) => t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, n));
    expect(chip('جوال باي').selected, isTrue);
    await tap(t, find.widgetWithText(ChoiceChip, 'بال باي'));
    await pumpFor(t, 300);
    expect(chip('بال باي').selected, isTrue);
    expect(chip('جوال باي').selected, isFalse);

    // المدفوع 500 ثم تقسيط الباقي على 3: المبلغ المكتوب يبقى والباقي يُقسم
    await t.enterText(find.widgetWithText(TextField, 'المدفوع الآن'), '500');
    await pumpFor(t, 300);
    await t.scrollUntilVisible(find.widgetWithText(SwitchListTile, 'تقسيط الباقي'), 200, scrollable: scroll);
    await tap(t, find.widgetWithText(SwitchListTile, 'تقسيط الباقي'));
    await t.scrollUntilVisible(find.byIcon(Icons.add_circle_outline), 200, scrollable: scroll);
    await tap(t, find.byIcon(Icons.add_circle_outline));
    expect(t.widget<TextField>(find.widgetWithText(TextField, 'المدفوع الآن')).controller!.text, '500');
    expect(chip('بال باي').selected, isTrue);

    await tap(t, find.textContaining('تأكيد واستلام'));
    await pumpFor(t, 1500);
    await tap(t, find.text('تم'));
    await pumpFor(t, 1500);

    final m = g.members.all.firstWhere((x) => x.name == 'عضو تجربة');
    final inv = g.invoicesOf(m.id).single;
    final pay = g.paymentsOf(inv.id).single;
    expect(pay.amount, 500);
    expect(pay.method, PayMethod.wallet);
    expect(pay.account, 'بال باي');
    expect(inv.installments.length, 3);
    final rest = inv.total - 500;
    expect(inv.installments.fold(0.0, (s, i) => s + i.amount), closeTo(rest, 0.01));
    expect(inv.installments.first.amount, closeTo(rest / 3, 0.01));

    await t.scrollUntilVisible(find.text('أعضاء فعّالون'), -300, scrollable: find.byType(Scrollable).first);
    expect(activeKpi(t), before + 1);
    expect(t.takeException(), isNull);
  });
}
