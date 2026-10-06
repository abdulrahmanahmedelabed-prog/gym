import 'package:flutter_test/flutter_test.dart';
import 'package:nadi_gym/core/money.dart';
import 'package:nadi_gym/models/billing.dart';
import 'package:nadi_gym/services/accounting.dart';
import 'package:nadi_gym/services/billing.dart';
import 'package:nadi_gym/services/demo_data.dart';
import 'package:nadi_gym/services/membership.dart';
import 'package:nadi_gym/services/reports.dart';

import 'helpers.dart';

double sumDr(List<TrialRow> t) => roundMoney(t.fold(0.0, (s, x) => s + x.debit));
double sumCr(List<TrialRow> t) => roundMoney(t.fold(0.0, (s, x) => s + x.credit));

void main() {
  group('المحاسبة الآلية', () {
    test('نادٍ تجريبي كامل: كل قيد متوازن، وميزان المراجعة متساوٍ، والأرقام تطابق التقارير', () async {
      final (g, _) = await newGym(DateTime(2026, 9, 29, 18));
      await DemoData(g).generate();
      final a = Accounting(g);
      final j = a.journal();
      expect(j, isNotEmpty);
      expect(j.where((e) => !e.balanced), isEmpty);
      final tb = a.trialBalance();
      expect(sumDr(tb), sumCr(tb));
      // ذمم الأعضاء في الدفاتر = مجموع المتبقي على الفواتير
      final ar = tb.firstWhere((t) => t.account == Accounts.receivable).balance;
      final open = roundMoney(g.invoices.all.fold(0.0, (s, i) => s + i.balance));
      expect(ar, closeTo(open, 0.05));
      // المقبوض في قائمة الدخل = المحصّل في التقارير
      final r = Range(DateTime(2020), g.today);
      final inc = a.incomeStatement(r);
      final rep = Reports(g);
      expect(roundMoney(inc.collected - inc.refunds), closeTo(rep.collected(r), 0.05));
      expect(inc.totalExpenses, closeTo(rep.expenses(r), 0.05));
      // النقد في كل الحسابات = المحصّل − المصروفات
      final cash = a.moneyBalances(g.today).values.fold(0.0, (s, v) => s + v);
      final opening = g.moves.all.where((m) => m.kind == 'opening').fold(0.0, (s, m) => s + m.amount);
      expect(cash, closeTo(rep.collected(r) - rep.expenses(r) + opening, 0.05));
      expect(a.balanceSheet(g.today).balanced, isTrue);
      // أعمار الديون = مجموع الديون
      expect(a.aging(g.today).total, closeTo(open, 0.05));
      final audit = a.audit();
      expect(audit.where((f) => f.severity == Severity.critical), isEmpty);
    });
  
    test('الضريبة الشاملة والمضافة والخصم والإلغاء: القيد متوازن والضريبة صحيحة', () async {
      for (final inclusive in [true, false]) {
        final (g, _) = await newGym();
        g.settings
          ..taxEnabled = true
          ..taxInclusive = inclusive
          ..taxRate = 16;
        final plan = await addPlan(g, price: 1160, fee: 50);
        final ms = MembershipService(g);
        final m = await ms.addMember(ms.newMember(name: 'x', phone: '0592000001'));
        final r = await ms.sell(SaleRequest(memberId: m.id, planId: plan.id, discount: 100, registrationFee: true));
        await BillingService(g).collect(r.invoice, 300, PayMethod.wallet, account: 'جوال باي');
        final a = Accounting(g);
        final e = a.invoiceEntries(r.invoice).first;
        expect(e.balanced, isTrue);
        final vat = e.lines.where((l) => l.account == Accounts.vat).fold(0.0, (s, l) => s + l.credit);
        expect(vat, closeTo(r.invoice.tax, 0.02));
        expect(a.moneyBalances(g.today)['جوال باي'], 300);
        // إلغاء الاشتراك مع استرداد: يبقى كل شيء متوازناً
        await ms.cancel(r.subscription, reason: 'سفر', refund: 100);
        final tb = a.trialBalance();
        expect(sumDr(tb), sumCr(tb));
        expect(a.journal().every((x) => x.balanced), isTrue);
      }
    });

    test('التدقيق يكتشف الأخطاء ويصلح ما يمكن إصلاحه', () async {
      final (g, _) = await newGym(DateTime(2026, 9, 29, 12));
      final plan = await addPlan(g, price: 500);
      final ms = MembershipService(g);
      final m = await ms.addMember(ms.newMember(name: 'سالم', phone: '0592000002'));
      final r = await ms.sell(SaleRequest(memberId: m.id, planId: plan.id, payments: const [PayInput(200, PayMethod.cash)]));
      final a = Accounting(g);
      expect(a.audit().where((f) => f.severity == Severity.critical), isEmpty);
      // تلاعب: المدفوع في الفاتورة لا يطابق الدفعات
      r.invoice.paid = 500;
      await g.put(r.invoice);
      var f = a.audit().firstWhere((x) => x.code == 'paid_mismatch');
      expect(f.severity, Severity.critical);
      await f.fix!();
      expect(g.invoices[r.invoice.id]!.paid, 200);
      expect(a.audit().any((x) => x.code == 'paid_mismatch'), isFalse);
      // دفعة بلا فاتورة + رقم مكرر + تاريخ مستقبلي
      final p = r.payments.single;
      await g.put(Payment(id: 'orphan', number: p.number, invoiceId: 'missing', date: DateTime(2026, 12, 1), amount: 50, method: PayMethod.cash));
      final codes = a.audit().map((x) => x.code).toSet();
      expect(codes, containsAll(['orphan_payment', 'dup_numbers', 'future']));
      // فاتورة محذوفة من خارج البرنامج: رقم ناقص في التسلسل
      final r2 = await ms.sell(SaleRequest(memberId: m.id, planId: plan.id));
      await ms.sell(SaleRequest(memberId: m.id, planId: plan.id));
      await g.remove(r2.invoice);
      expect(a.audit().firstWhere((x) => x.code == 'gaps').items, contains(r2.invoice.number));
    });

    test('إغلاق الصندوق: المتوقع = النقد الداخل − المردود − المصروف النقدي، والفرق يُسجَّل', () async {
      final (g, clock) = await newGym(DateTime(2026, 9, 29, 20));
      final plan = await addPlan(g, price: 300);
      final ms = MembershipService(g);
      final b = BillingService(g);
      final m = await ms.addMember(ms.newMember(name: 'x', phone: '0592000003'));
      final r = await ms.sell(SaleRequest(memberId: m.id, planId: plan.id, payments: const [PayInput(300, PayMethod.cash)]));
      await ms.sell(SaleRequest(memberId: m.id, planId: plan.id, payments: const [PayInput(300, PayMethod.wallet, 'T1', 'بال باي')]));
      await b.refund(r.invoice, 50, PayMethod.cash, 'خطأ');
      await b.addExpense(date: g.today, category: 'نظافة', amount: 30);
      await b.addExpense(date: g.today, category: 'إيجار', amount: 1000, method: 'transfer', account: 'بنك فلسطين');
      final a = Accounting(g);
      final cd = a.cashDay(g.today);
      expect(cd.cashIn, 300);
      expect(cd.cashRefunds, 50);
      expect(cd.cashExpenses, 30);
      expect(cd.expected, 220);
      expect(cd.otherAccounts['بال باي'], 300);
      expect(cd.otherAccounts['بنك فلسطين'], -1000);
      final c = await a.closeCash(g.today, 200, note: 'عدّ آخر الليل');
      expect(c.variance, -20);
      expect(g.audit.all.any((x) => x.action == 'cash_close'), isTrue);
      clock.advance(days: 1);
      final f = a.audit().firstWhere((x) => x.code == 'cash_variance');
      expect(f.items.single, contains('-20'));
      // تقرير الموظفين
      expect(a.staffReport(Range(g.today.subtract(const Duration(days: 1)), g.today)).first.collected, 600);
    });

    test('محاسبة 10/10: قيود بتاريخ حدوثها، إقفال الفترة، إعدام الدين، حركات المال، الميزانية', () async {
      final (g, clock) = await newGym(DateTime(2026, 8, 10, 12));
      final plan = await addPlan(g, price: 500);
      final ms = MembershipService(g);
      final b = BillingService(g);
      final a = Accounting(g);
      final m = await ms.addMember(ms.newMember(name: 'سالم', phone: '0592000004'));
      final ra = await ms.sell(SaleRequest(memberId: m.id, planId: plan.id)); // آجل
      final rb = await ms.sell(SaleRequest(memberId: m.id, planId: plan.id, payments: const [PayInput(500, PayMethod.cash)]));
      await a.addMove(kind: 'opening', date: g.today, amount: 1000, to: 'بنك فلسطين');
      final aug = Range(DateTime(2026, 8, 1), DateTime(2026, 8, 31));
      final augBefore = {for (final t in a.trialBalance(aug)) t.account: t.balance};
      expect(augBefore[Accounts.opening], -1000);

      clock.setDay(DateTime(2026, 9, 5), 10);
      expect(a.audit().any((f) => f.code == 'no_lock'), isTrue);
      await a.lockPeriod(DateTime(2026, 8, 31));
      expect(g.lockedUntil, DateTime(2026, 8, 31));
      expect(a.audit().any((f) => f.code == 'no_lock'), isFalse);

      // أحداث سبتمبر لا تغيّر أرقام أغسطس
      await b.voidInvoice(ra.invoice, 'لم يحضر');
      await ms.cancel(rb.subscription, reason: 'سفر', refund: 100);
      expect({for (final t in a.trialBalance(aug)) t.account: t.balance}, augBefore);
      expect(a.audit().any((f) => f.code == 'lock_changed'), isFalse);
      final sep = a.incomeStatement(Range(DateTime(2026, 9, 1), g.today));
      expect(sep.netRevenue, lessThan(0)); // إلغاءات في سبتمبر لمبيعات أغسطس

      // لا عمليات بتاريخ داخل الفترة المقفلة
      expect(() => b.addExpense(date: DateTime(2026, 8, 20), category: 'نظافة', amount: 10), throwsA(isA<GymException>()));
      expect(() => a.addMove(kind: 'capital', date: DateTime(2026, 8, 20), amount: 10, to: Accounts.cash), throwsA(isA<GymException>()));

      // حركات المال وأثرها على الصندوق
      await a.addMove(kind: 'transfer', date: g.today, amount: 150, from: Accounts.cash, to: 'بنك فلسطين');
      await a.addMove(kind: 'capital', date: g.today, amount: 200, to: Accounts.cash);
      await a.addMove(kind: 'draw', date: g.today, amount: 50, from: 'بنك فلسطين');
      expect(() => a.addMove(kind: 'transfer', date: g.today, amount: 5, from: Accounts.cash, to: Accounts.cash), throwsA(isA<GymException>()));
      final cd = a.cashDay(g.today);
      expect(cd.cashRefunds, 100);
      expect(cd.movesOut, 150);
      expect(cd.movesIn, 200);
      expect(cd.expected, -50);
      final money = a.moneyBalances(g.today);
      expect(money[Accounts.cash], 500 - 100 - 150 + 200);
      expect(money['بنك فلسطين'], 1000 + 150 - 50);

      // إعدام دين
      final rc = await ms.sell(SaleRequest(memberId: m.id, planId: plan.id, payments: const [PayInput(100, PayMethod.cash)]));
      await b.writeOff(rc.invoice, 'سافر');
      expect(rc.invoice.balance, 0);
      expect(rc.invoice.status, InvoiceStatus.writtenOff);
      expect(g.balanceOf(m.id), 0);
      expect(a.incomeStatement(Range(DateTime(2026, 9, 1), g.today)).expenses[Accounts.badDebtCategory], 400);
      expect(a.trend(2).last.expenses, 400);

      // الميزانية متوازنة والذمم = الديون المفتوحة
      final bs = a.balanceSheet(g.today);
      expect(bs.balanced, isTrue);
      expect(bs.assets[Accounts.receivable] ?? 0, 0);
      expect(bs.equity[Accounts.drawings], -50);
      expect(a.journal().every((e) => e.balanced), isTrue);
      final led = a.ledger('بنك فلسطين');
      expect(led.last.balance, 1100);

      // دفعة بتاريخ قديم تصل من جهاز آخر: التدقيق يكشف تغيّر الفترة المقفلة
      await g.put(Payment(id: 'late', number: 'RC-X', invoiceId: rb.invoice.id, date: DateTime(2026, 8, 15), amount: 5, method: PayMethod.cash));
      expect(a.audit().firstWhere((f) => f.code == 'lock_changed').severity, Severity.critical);
      await a.unlockLast();
      expect(g.lockedUntil, isNull);
      expect(g.audit.all.any((x) => x.action == 'unlock'), isTrue);
    });
  });
}
