import 'dart:math' as math;

import '../core/dates.dart';
import '../core/i18n.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../data/gym_data.dart';
import '../models/billing.dart';
import '../models/business.dart';
import 'license.dart';
import 'membership.dart';
import 'reports.dart';

// =============================================================================
// المحاسبة الآلية: قيد مزدوج لكل عملية، مشتق دائماً من البيانات نفسها (لا يُدخل يدوياً)
// فلا يمكن أن تختلف الدفاتر عن الفواتير والدفعات. منها تُبنى كل القوائم المالية.
// =============================================================================

enum AcctType { asset, liability, equity, revenue, contra, expense }

class Accounts {
  static const cash = 'الصندوق (نقد)';
  static const cards = 'البطاقات';
  static const bank = 'تحويلات بنكية';
  static const wallets = 'محافظ إلكترونية';
  static const gateway = 'بوابة الدفع الإلكتروني';
  static const receivable = 'ذمم الأعضاء (مبالغ مستحقة)';
  static const discounts = 'خصومات ممنوحة';
  static const vat = 'ضريبة القيمة المضافة المستحقة';
  static const rounding = 'فروقات تقريب';
  static const capital = 'رأس مال المالك';
  static const drawings = 'مسحوبات المالك';
  static const opening = 'أرصدة افتتاحية';
  static const badDebtCategory = 'ديون معدومة';

  static String revenue(ItemKind k) => switch (k) {
        ItemKind.subscription => 'إيرادات الاشتراكات',
        ItemKind.registration => 'إيرادات رسوم التسجيل',
        ItemKind.pt => 'إيرادات التدريب الشخصي',
        ItemKind.product => 'إيرادات المتجر',
        ItemKind.locker => 'إيرادات الخزائن',
        ItemKind.classFee => 'إيرادات الحصص',
        ItemKind.other => 'إيرادات أخرى',
      };

  static String expense(String category) => 'مصروف: $category';

  /// اسم الحساب بلغة الواجهة (أسماء المحافظ والبنوك تبقى كما كتبها المستخدم)
  static String label(String a) =>
      a.startsWith('مصروف: ') ? tr('مصروف: {c}', {'c': tr(a.substring(7))}) : tr(a);

  /// الحساب المالي الذي دخل إليه المال أو خرج منه
  static String money(String method, String? account) => switch (method) {
        'cash' => cash,
        'card' => cards,
        'transfer' => account ?? bank,
        'wallet' => account ?? wallets,
        'online' => gateway,
        _ => account ?? cash,
      };
}

class JLine {
  final String account;
  final double debit;
  final double credit;
  const JLine(this.account, {this.debit = 0, this.credit = 0});
}

/// قيد يومية: مدين = دائن دائماً
class JEntry {
  final DateTime date;
  final String ref; // رقم الفاتورة أو الإيصال
  final String text;
  final String source; // invoice / payment / expense / move
  final String sourceId;
  final List<JLine> lines;
  JEntry(this.date, this.ref, this.text, this.source, this.sourceId, this.lines);

  double get debit => roundMoney(lines.fold(0.0, (s, l) => s + l.debit));
  double get credit => roundMoney(lines.fold(0.0, (s, l) => s + l.credit));
  bool get balanced => (debit - credit).abs() < 0.005;
}

class TrialRow {
  final String account;
  final AcctType type;
  final double debit;
  final double credit;
  const TrialRow(this.account, this.type, this.debit, this.credit);
  double get balance => roundMoney(debit - credit);
}

/// قائمة الدخل لفترة
class IncomeStatement {
  final Range range;
  final Map<String, double> revenue; // حسب نوع الإيراد (بدون الضريبة)
  final double discounts;
  final Map<String, double> expenses;
  final double vat; // ضريبة محصّلة لصالح الحكومة (ليست ربحاً)
  final double collected; // المقبوض فعلاً في الفترة
  final double paidOut; // المصروفات المدفوعة
  final double refunds;
  IncomeStatement(this.range, this.revenue, this.discounts, this.expenses, this.vat, this.collected, this.paidOut, this.refunds);

  double get grossRevenue => roundMoney(revenue.values.fold(0.0, (s, v) => s + v));
  double get netRevenue => roundMoney(grossRevenue - discounts);
  double get totalExpenses => roundMoney(expenses.values.fold(0.0, (s, v) => s + v));
  double get netProfit => roundMoney(netRevenue - totalExpenses);
  double get margin => netRevenue <= 0 ? 0 : netProfit / netRevenue * 100;

  /// صافي النقد الداخل بعد المصروفات (ما زاد في الحسابات فعلاً)
  double get netCash => roundMoney(collected - paidOut);
}

class Aging {
  final double d30, d60, d90, older;
  final List<({String memberId, double amount, int days})> top;
  Aging(this.d30, this.d60, this.d90, this.older, this.top);
  double get total => roundMoney(d30 + d60 + d90 + older);
}

class CashDay {
  final DateTime day;
  final double cashIn;
  final double cashRefunds;
  final double cashExpenses;
  final Map<String, double> otherAccounts; // المحافظ والبنوك في نفس اليوم (للمطابقة مع كشوفها)
  final double movesIn; // إيداع من المالك في الصندوق
  final double movesOut; // إيداع النقد في البنك، سحب المالك، توريد الضريبة نقداً
  CashDay(this.day, this.cashIn, this.cashRefunds, this.cashExpenses, this.otherAccounts, {this.movesIn = 0, this.movesOut = 0});
  double get expected => roundMoney(cashIn - cashRefunds - cashExpenses + movesIn - movesOut);
}

/// الميزانية العمومية (المركز المالي) في يوم: ما يملكه النادي = ما عليه + حق المالك
class BalanceSheet {
  final DateTime day;
  final Map<String, double> assets;
  final Map<String, double> liabilities;
  final Map<String, double> equity; // رأس المال والمسحوبات والأرصدة الافتتاحية
  final double retained; // الأرباح المتراكمة
  BalanceSheet(this.day, this.assets, this.liabilities, this.equity, this.retained);

  double get totalAssets => roundMoney(assets.values.fold(0.0, (s, v) => s + v));
  double get totalLiabilities => roundMoney(liabilities.values.fold(0.0, (s, v) => s + v));
  double get totalEquity => roundMoney(equity.values.fold(0.0, (s, v) => s + v) + retained);
  bool get balanced => (totalAssets - totalLiabilities - totalEquity).abs() < 0.05;
}

/// سطر في كشف حساب
class LedgerLine {
  final DateTime date;
  final String ref;
  final String text;
  final double debit;
  final double credit;
  final double balance;
  const LedgerLine(this.date, this.ref, this.text, this.debit, this.credit, this.balance);
}

class MonthFigures {
  final DateTime month;
  final double revenue; // صافي الإيرادات بعد الخصومات
  final double expenses;
  MonthFigures(this.month, this.revenue, this.expenses);
  double get profit => roundMoney(revenue - expenses);
}

enum Severity { critical, warning, info }

/// ملاحظة من التدقيق الآلي
class Finding {
  final String code;
  final Severity severity;
  final String title;
  final String advice;
  final List<String> items;
  final Future<void> Function()? fix;
  final String? fixLabel;
  Finding(this.code, this.severity, this.title, this.advice, this.items, {this.fix, this.fixLabel});
  int get count => items.length;
}

class Accounting {
  final GymData d;
  Accounting(this.d);

  final Map<String, AcctType> _types = {};

  AcctType typeOf(String account) {
    final t = _types[account];
    if (t != null) return t;
    if (account.startsWith('إيرادات')) return AcctType.revenue;
    if (account.startsWith('مصروف')) return AcctType.expense;
    return AcctType.asset;
  }

  // ---------------------------------------------------------------------------
  // دفتر اليومية
  // ---------------------------------------------------------------------------

  /// أثر مجموعة بنود الفاتورة على كل حساب (مدين موجب، دائن سالب). المجموع صفر دائماً.
  Map<String, double> _invoiceEffect(Invoice inv, List<InvoiceItem> items) {
    final tmp = Invoice(
        id: inv.id, number: inv.number, date: inv.date, items: items, discount: inv.discount, taxRate: inv.taxRate, taxInclusive: inv.taxInclusive);
    final f = inv.taxInclusive && inv.taxRate > 0 ? 1 / (1 + inv.taxRate) : 1.0;
    final out = <String, double>{};
    void add(String a, double v) => out[a] = roundMoney((out[a] ?? 0) + v);
    var revSum = 0.0;
    for (final i in items) {
      final k = Accounts.revenue(i.total < 0 ? ItemKind.subscription : i.kind);
      final v = roundMoney(i.total * f);
      add(k, -v);
      revSum += v;
      _types[k] = AcctType.revenue;
    }
    final disc = roundMoney(inv.discount * f);
    final total = tmp.total;
    add(Accounts.receivable, total);
    if (disc != 0) add(Accounts.discounts, disc);
    // الضريبة هي الفرق الذي يوازن القيد (فلا يبقى فرق تقريب)
    final diff = roundMoney(total + disc - roundMoney(revSum));
    if (diff.abs() >= 0.005) add(inv.taxRate > 0 ? Accounts.vat : Accounts.rounding, -diff);
    _types[Accounts.receivable] = AcctType.asset;
    _types[Accounts.discounts] = AcctType.contra;
    _types[Accounts.vat] = AcctType.liability;
    _types[Accounts.rounding] = AcctType.expense;
    return out;
  }

  List<JLine> _lines(Map<String, double> effect, String balancing) {
    final lines = <JLine>[];
    var dr = 0.0, cr = 0.0;
    for (final e in effect.entries) {
      final v = roundMoney(e.value);
      if (v > 0) {
        lines.add(JLine(e.key, debit: v));
        dr += v;
      } else if (v < 0) {
        lines.add(JLine(e.key, credit: -v));
        cr += -v;
      }
    }
    final res = roundMoney(dr - cr);
    if (res.abs() >= 0.005) lines.add(res > 0 ? JLine(balancing, credit: res) : JLine(balancing, debit: -res));
    return lines;
  }

  /// قيود الفاتورة، كلٌّ بتاريخ حدوثه: البيع يوم الفاتورة، إلغاء الاشتراك يوم إلغائه، إلغاء الفاتورة يوم إلغائها،
  /// وإعدام الدين يوم إعدامه. فلا يتغير ما سُجّل في شهر سابق مهما حدث بعده.
  List<JEntry> invoiceEntries(Invoice inv) {
    if (inv.items.isEmpty) return const [];
    if (inv.voided && inv.voidedAt == null) return const []; // إلغاء قديم بلا تاريخ: لا قيد
    final who = inv.customerName ?? d.members[inv.memberId]?.name ?? '';
    final bal = inv.taxRate > 0 ? Accounts.vat : Accounts.rounding;
    DateTime? creditDate(InvoiceItem i) => i.total < 0 && i.refId != null ? d.subs[i.refId]?.cancelledAt : null;
    final credits = [for (final i in inv.items) if (creditDate(i) != null) i]..sort((a, b) => creditDate(a)!.compareTo(creditDate(b)!));
    var current = [for (final i in inv.items) if (creditDate(i) == null) i];
    var effect = _invoiceEffect(inv, current);
    final out = <JEntry>[
      JEntry(inv.date, inv.number, tr('فاتورة {n} — {w}', {'n': inv.number, 'w': who}), 'invoice', inv.id, _lines(effect, bal)),
    ];
    for (final c in credits) {
      current = [...current, c];
      final next = _invoiceEffect(inv, current);
      final delta = {for (final k in {...effect.keys, ...next.keys}) k: roundMoney((next[k] ?? 0) - (effect[k] ?? 0))};
      out.add(JEntry(creditDate(c)!, inv.number, tr('إلغاء اشتراك — فاتورة {n} — {w}', {'n': inv.number, 'w': who}), 'invoice', inv.id, _lines(delta, bal)));
      effect = next;
    }
    if (inv.voided) {
      out.add(JEntry(inv.voidedAt!, inv.number, tr('إلغاء الفاتورة {n} — {w}', {'n': inv.number, 'w': who}), 'invoice', inv.id,
          _lines({for (final e in effect.entries) e.key: -e.value}, bal)));
    } else if (inv.writtenOff > 0.001) {
      final exp = Accounts.expense(Accounts.badDebtCategory);
      _types[exp] = AcctType.expense;
      out.add(JEntry(inv.writtenOffAt ?? inv.date, inv.number, tr('إعدام دين — فاتورة {n} — {w}', {'n': inv.number, 'w': who}), 'invoice', inv.id,
          [JLine(exp, debit: inv.writtenOff), JLine(Accounts.receivable, credit: inv.writtenOff)]));
    }
    return out.where((e) => e.lines.isNotEmpty).toList();
  }

  JEntry paymentEntry(Payment p) {
    final acc = Accounts.money(p.method.name, p.account);
    _types[acc] = AcctType.asset;
    _types[Accounts.receivable] = AcctType.asset;
    final a = p.amount.abs();
    final lines = p.amount >= 0
        ? [JLine(acc, debit: a), JLine(Accounts.receivable, credit: a)]
        : [JLine(Accounts.receivable, debit: a), JLine(acc, credit: a)];
    final inv = d.invoices[p.invoiceId];
    final text = p.amount >= 0
        ? tr('قبض {n} — فاتورة {i}', {'n': p.number, 'i': inv?.number ?? '?'})
        : tr('رد مبلغ {n} — فاتورة {i}', {'n': p.number, 'i': inv?.number ?? '?'});
    return JEntry(p.date, p.number, text, 'payment', p.id, lines);
  }

  JEntry expenseEntry(Expense e) {
    final exp = Accounts.expense(e.category);
    final acc = Accounts.money(e.method, e.account);
    _types[exp] = AcctType.expense;
    _types[acc] = AcctType.asset;
    return JEntry(e.date, '', tr('مصروف: {c}{n}', {'c': e.category, 'n': e.note == null ? '' : ' — ${e.note}'}), 'expense', e.id,
        [JLine(exp, debit: e.amount), JLine(acc, credit: e.amount)]);
  }

  JEntry moveEntry(MoneyMove m) {
    final a = m.amount;
    final lines = switch (m.kind) {
      'transfer' => [JLine(m.to!, debit: a), JLine(m.from!, credit: a)],
      'draw' => [JLine(Accounts.drawings, debit: a), JLine(m.from!, credit: a)],
      'capital' => [JLine(m.to!, debit: a), JLine(Accounts.capital, credit: a)],
      'opening' => [JLine(m.to!, debit: a), JLine(Accounts.opening, credit: a)],
      _ => [JLine(Accounts.vat, debit: a), JLine(m.from!, credit: a)], // vat: توريد الضريبة
    };
    for (final x in [m.from, m.to]) {
      if (x != null) _types[x] = AcctType.asset;
    }
    _types[Accounts.drawings] = AcctType.equity;
    _types[Accounts.capital] = AcctType.equity;
    _types[Accounts.opening] = AcctType.equity;
    _types[Accounts.vat] = AcctType.liability;
    return JEntry(m.date, '', '${moveKindName(m.kind)}${m.note == null ? '' : ' — ${m.note}'}', 'move', m.id, lines);
  }

  static String moveKindName(String k) => switch (k) {
        'transfer' => tr('تحويل بين الحسابات'),
        'draw' => tr('سحب المالك'),
        'capital' => tr('إيداع من المالك'),
        'opening' => tr('رصيد افتتاحي'),
        _ => tr('توريد الضريبة'),
      };

  /// كل القيود (أو قيود فترة) مرتبة زمنياً
  List<JEntry> journal([Range? r]) {
    final out = <JEntry>[];
    for (final inv in d.invoices.all) {
      for (final e in invoiceEntries(inv)) {
        if (r == null || r.has(e.date)) out.add(e);
      }
    }
    for (final p in d.payments.all) {
      if (r != null && !r.has(p.date)) continue;
      out.add(paymentEntry(p));
    }
    for (final x in d.expenses.all) {
      if (r != null && !r.has(x.date)) continue;
      out.add(expenseEntry(x));
    }
    for (final m in d.moves.all) {
      if (r != null && !r.has(m.date)) continue;
      out.add(moveEntry(m));
    }
    out.sort((a, b) {
      final c = a.date.compareTo(b.date);
      return c != 0 ? c : a.ref.compareTo(b.ref);
    });
    return out;
  }

  /// ميزان المراجعة: مجموع المدين = مجموع الدائن
  List<TrialRow> trialBalance([Range? r]) {
    final dr = <String, double>{}, cr = <String, double>{};
    for (final e in journal(r)) {
      for (final l in e.lines) {
        dr[l.account] = (dr[l.account] ?? 0) + l.debit;
        cr[l.account] = (cr[l.account] ?? 0) + l.credit;
      }
    }
    final rows = [
      for (final a in {...dr.keys, ...cr.keys}) TrialRow(a, typeOf(a), roundMoney(dr[a] ?? 0), roundMoney(cr[a] ?? 0)),
    ]..sort((a, b) {
        final t = a.type.index.compareTo(b.type.index);
        return t != 0 ? t : a.account.compareTo(b.account);
      });
    return rows;
  }

  /// أرصدة الحسابات حتى يوم معيّن (مدين موجب)
  Map<String, double> balancesAsOf(DateTime day) {
    final r = Range(DateTime(1990), day);
    return {for (final t in trialBalance(r)) t.account: t.balance};
  }

  // ---------------------------------------------------------------------------
  // القوائم المالية
  // ---------------------------------------------------------------------------

  IncomeStatement incomeStatement(Range r) {
    final rows = trialBalance(r);
    final revenue = <String, double>{};
    final expenses = <String, double>{};
    var discounts = 0.0, vat = 0.0;
    for (final t in rows) {
      switch (t.type) {
        case AcctType.revenue:
          revenue[t.account] = roundMoney(t.credit - t.debit);
        case AcctType.expense:
          expenses[t.account.replaceFirst('مصروف: ', '')] = roundMoney(t.debit - t.credit);
        case AcctType.contra:
          discounts += t.debit - t.credit;
        case AcctType.liability:
          if (t.account == Accounts.vat) vat += t.credit - t.debit;
        case AcctType.asset:
        case AcctType.equity:
          break;
      }
    }
    final pays = d.payments.all.where((p) => r.has(p.date));
    final collected = roundMoney(pays.where((p) => p.amount > 0).fold(0.0, (s, p) => s + p.amount));
    final refunds = roundMoney(-pays.where((p) => p.amount < 0).fold(0.0, (s, p) => s + p.amount));
    final paidOut = roundMoney(d.expenses.all.where((e) => r.has(e.date)).fold(0.0, (s, e) => s + e.amount) + refunds);
    return IncomeStatement(r, revenue, roundMoney(discounts), expenses, roundMoney(vat), collected, paidOut, refunds);
  }

  /// رصيد كل حساب مالي (الصندوق، كل محفظة، كل بنك) حتى يوم معيّن
  Map<String, double> moneyBalances(DateTime day) {
    final b = balancesAsOf(day);
    final out = <String, double>{};
    for (final e in b.entries) {
      if (typeOf(e.key) == AcctType.asset && e.key != Accounts.receivable) out[e.key] = e.value;
    }
    return out;
  }

  /// الميزانية العمومية في يوم
  BalanceSheet balanceSheet(DateTime day) {
    final assets = <String, double>{}, liab = <String, double>{}, eq = <String, double>{};
    var retained = 0.0;
    for (final t in trialBalance(Range(DateTime(1990), day))) {
      final b = t.balance;
      if (b.abs() < 0.005) continue;
      switch (t.type) {
        case AcctType.asset:
          assets[t.account] = b;
        case AcctType.liability:
          liab[t.account] = roundMoney(-b);
        case AcctType.equity:
          eq[t.account] = roundMoney(-b);
        case AcctType.revenue:
        case AcctType.contra:
        case AcctType.expense:
          retained -= b;
      }
    }
    return BalanceSheet(dateOnly(day), assets, liab, eq, roundMoney(retained));
  }

  /// كشف حساب: كل حركة على الحساب مع الرصيد بعدها
  List<LedgerLine> ledger(String account) {
    final out = <LedgerLine>[];
    var bal = 0.0;
    final credit = {AcctType.liability, AcctType.equity, AcctType.revenue}.contains(typeOf(account));
    for (final e in journal()) {
      for (final l in e.lines.where((l) => l.account == account)) {
        bal = roundMoney(bal + (credit ? l.credit - l.debit : l.debit - l.credit));
        out.add(LedgerLine(e.date, e.ref, e.text, l.debit, l.credit, bal));
      }
    }
    return out;
  }

  /// الإيرادات والمصروفات والربح لآخر [n] أشهر (الأقدم أولاً)
  List<MonthFigures> trend(int n) {
    final today = d.today;
    final first = DateTime(today.year, today.month - n + 1, 1);
    final rev = List.filled(n, 0.0), exp = List.filled(n, 0.0);
    for (final e in journal(Range(first, today))) {
      final i = (e.date.year - first.year) * 12 + e.date.month - first.month;
      if (i < 0 || i >= n) continue;
      for (final l in e.lines) {
        switch (typeOf(l.account)) {
          case AcctType.revenue:
            rev[i] += l.credit - l.debit;
          case AcctType.contra:
            rev[i] -= l.debit - l.credit;
          case AcctType.expense:
            exp[i] += l.debit - l.credit;
          default:
            break;
        }
      }
    }
    return [for (var i = 0; i < n; i++) MonthFigures(DateTime(first.year, first.month + i, 1), roundMoney(rev[i]), roundMoney(exp[i]))];
  }

  /// أعمار الديون: كم من المستحق عمره شهر، شهران، ثلاثة، أكثر
  Aging aging(DateTime day) {
    var a = 0.0, b = 0.0, c = 0.0, o = 0.0;
    final byMember = <String, ({double amount, int days})>{};
    for (final inv in d.invoices.all) {
      final bal = inv.balance;
      if (bal <= 0.001) continue;
      final age = daysBetween(dateOnly(inv.date), day);
      if (age <= 30) {
        a += bal;
      } else if (age <= 60) {
        b += bal;
      } else if (age <= 90) {
        c += bal;
      } else {
        o += bal;
      }
      final k = inv.memberId ?? inv.customerName ?? '-';
      final prev = byMember[k];
      byMember[k] = (amount: (prev?.amount ?? 0) + bal, days: math.max(prev?.days ?? 0, age));
    }
    final top = [for (final e in byMember.entries) (memberId: e.key, amount: roundMoney(e.value.amount), days: e.value.days)]
      ..sort((x, y) => y.amount.compareTo(x.amount));
    return Aging(roundMoney(a), roundMoney(b), roundMoney(c), roundMoney(o), top.take(10).toList());
  }

  /// إيراد مقبوض أو مفوتر مقابل خدمة لم تُقدَّم بعد (أيام اشتراك متبقية) — التزام تجاه الأعضاء
  double deferredRevenue(DateTime day) {
    var sum = 0.0;
    for (final s in d.subs.all) {
      if (s.cancelled) continue;
      final inv = d.invoices[s.invoiceId];
      if (inv == null || inv.voided) continue;
      final value = s.price - s.discount;
      if (value <= 0) continue;
      final f = inv.taxInclusive && inv.taxRate > 0 ? 1 / (1 + inv.taxRate) : 1.0;
      final totalDays = daysBetween(s.start, s.end) + 1;
      if (totalDays <= 0) continue;
      final used = (daysBetween(s.start, day) + 1).clamp(0, totalDays);
      sum += value * f * (1 - used / totalDays);
    }
    return roundMoney(sum);
  }

  /// حركة الصندوق النقدي في يوم (للإغلاق اليومي)
  CashDay cashDay(DateTime day) {
    final r = Range(day, day);
    var cin = 0.0, cref = 0.0, cexp = 0.0;
    final other = <String, double>{};
    for (final p in d.payments.all.where((p) => r.has(p.date))) {
      if (p.method == PayMethod.cash) {
        if (p.amount >= 0) {
          cin += p.amount;
        } else {
          cref += -p.amount;
        }
      } else {
        final k = Accounts.money(p.method.name, p.account);
        other[k] = roundMoney((other[k] ?? 0) + p.amount);
      }
    }
    for (final e in d.expenses.all.where((e) => r.has(e.date))) {
      if (e.method == 'cash') {
        cexp += e.amount;
      } else {
        final k = Accounts.money(e.method, e.account);
        other[k] = roundMoney((other[k] ?? 0) - e.amount);
      }
    }
    var mIn = 0.0, mOut = 0.0;
    for (final m in d.moves.all.where((m) => r.has(m.date) && m.kind != 'opening')) {
      for (final (acc, sign) in [(m.to, 1), (m.from, -1)]) {
        if (acc == null) continue;
        if (acc == Accounts.cash) {
          if (sign > 0) {
            mIn += m.amount;
          } else {
            mOut += m.amount;
          }
        } else {
          other[acc] = roundMoney((other[acc] ?? 0) + sign * m.amount);
        }
      }
    }
    return CashDay(dateOnly(day), roundMoney(cin), roundMoney(cref), roundMoney(cexp), other, movesIn: roundMoney(mIn), movesOut: roundMoney(mOut));
  }

  CashClose? closeOf(DateTime day) {
    final k = dayKey(day);
    final l = d.closes.all.where((c) => dayKey(c.day) == k).toList()..sort((a, b) => b.time.compareTo(a.time));
    return l.firstOrNull;
  }

  /// إغلاق الصندوق: يُسجَّل المتوقع والمعدود والفرق في سجل لا يُعدَّل
  Future<CashClose> closeCash(DateTime day, double counted, {String? note}) async {
    d.require(Feature.accounting);
    if (counted < 0) throw GymException(tr('المبلغ المعدود لا يكون سالباً'));
    final cd = cashDay(day);
    final c = CashClose(id: newId(), day: dateOnly(day), time: d.now(), by: d.userName, expected: cd.expected, counted: roundMoney(counted), note: note);
    await d.putAll([
      c,
      d.auditEntry('cash_close', tr('إغلاق صندوق {d}: المتوقع {e}، المعدود {c}، الفرق {v}',
          {'d': dayKey(day), 'e': fmtMoney(c.expected), 'c': fmtMoney(c.counted), 'v': fmtMoney(c.variance)})),
    ]);
    return c;
  }

  // ---------------------------------------------------------------------------
  // حركات المال وإقفال الفترات
  // ---------------------------------------------------------------------------

  /// الحسابات المالية المعروفة: الصندوق، كل محفظة وبنك في الإعدادات، وأي حساب له رصيد
  List<String> moneyAccounts() {
    final out = <String>[Accounts.cash];
    for (final a in d.settings.payAccounts.where((a) => a.active)) {
      if (!out.contains(a.name)) out.add(a.name);
    }
    for (final k in moneyBalances(d.today).keys) {
      if (!out.contains(k)) out.add(k);
    }
    return out;
  }

  Future<MoneyMove> addMove({required String kind, required DateTime date, required double amount, String? from, String? to, String? note}) async {
    d.require(Feature.accounting);
    if (!d.can(Perm.expenses)) throw GymException(tr('ليست لديك صلاحية'));
    amount = roundMoney(amount);
    if (amount <= 0) throw GymException(tr('اكتب مبلغاً صحيحاً'));
    if (!MoneyMove.kinds.contains(kind)) throw GymException(tr('نوع غير معروف'));
    final needFrom = kind == 'transfer' || kind == 'draw' || kind == 'vat';
    final needTo = kind == 'transfer' || kind == 'capital' || kind == 'opening';
    if (needFrom && (from == null || from.isEmpty) || needTo && (to == null || to.isEmpty)) throw GymException(tr('اختر الحساب'));
    if (kind == 'transfer' && from == to) throw GymException(tr('اختر حسابين مختلفين'));
    if (dateOnly(date).isAfter(d.today)) throw GymException(tr('التاريخ في المستقبل'));
    d.requireOpen(date);
    final m = MoneyMove(
        id: newId(), date: date, kind: kind, amount: amount, from: needFrom ? from : null, to: needTo ? to : null, note: note, by: d.userName);
    await d.putAll([
      m,
      d.auditEntry('move', '${moveKindName(kind)}: ${fmtMoney(amount)} ${m.from ?? ''}${m.from != null && m.to != null ? ' ← ' : ''}${m.to ?? ''}'),
    ]);
    return m;
  }

  Future<void> deleteMove(MoneyMove m) async {
    if (!d.can(Perm.expenses)) throw GymException(tr('ليست لديك صلاحية'));
    d.requireOpen(m.date);
    await d.remove(m);
    await d.log('move_delete', '${moveKindName(m.kind)} ${dayKey(m.date)}: ${fmtMoney(m.amount)}');
  }

  Map<String, double> _snapshot(DateTime until) => {
        for (final t in trialBalance(Range(DateTime(1990), until)))
          if (t.balance.abs() >= 0.005) t.account: t.balance,
      };

  /// إقفال الفترة حتى [until]: لا عمليات بتاريخ قبله بعد اليوم، ويُحفظ ميزان المراجعة للمقارنة
  Future<PeriodLock> lockPeriod(DateTime until) async {
    d.require(Feature.accounting);
    if (!d.can(Perm.settings)) throw GymException(tr('يحتاج صلاحية المالك'));
    until = dateOnly(until);
    if (!until.isBefore(d.today)) throw GymException(tr('يمكن إقفال الأيام الماضية فقط'));
    final cur = d.lockedUntil;
    if (cur != null && !until.isAfter(cur)) throw GymException(tr('الفترة حتى {d} مقفلة أصلاً', {'d': dayKey(cur)}));
    final l = PeriodLock(id: newId(), until: until, time: d.now(), by: d.userName, snapshot: _snapshot(until));
    await d.putAll([l, d.auditEntry('lock', tr('إقفال الفترة حتى {d}', {'d': dayKey(until)}))]);
    return l;
  }

  /// فتح آخر فترة مقفلة (يُسجَّل في العمليات الحساسة)
  Future<void> unlockLast() async {
    if (!d.can(Perm.settings)) throw GymException(tr('يحتاج صلاحية المالك'));
    final l = d.locks.all.fold<PeriodLock?>(null, (a, b) => a == null || b.until.isAfter(a.until) ? b : a);
    if (l == null) return;
    await d.remove(l);
    await d.log('unlock', tr('فتح الفترة المقفلة حتى {d}', {'d': dayKey(l.until)}));
  }

  /// سطور المحاسبة في ملخص المالك اليومي: إغلاق الصندوق وملاحظات التدقيق
  String dailyAuditText(DateTime day) {
    final b = StringBuffer();
    final c = closeOf(day);
    final cd = cashDay(day);
    if (c != null) {
      b.writeln(c.variance.abs() < 0.5
          ? tr('🧾 الصندوق: مطابق ({a}) — {by}', {'a': fmtMoney(c.counted), 'by': c.by ?? tr('المالك')})
          : tr('🧾 الصندوق: فرق {v} — {by}', {'v': '${c.variance > 0 ? '+' : ''}${fmtMoney(c.variance)}', 'by': c.by ?? tr('المالك')}));
    } else if (cd.cashIn > 0 || cd.cashExpenses > 0) {
      b.writeln(tr('🧾 الصندوق: لم يُغلق (المتوقع {a})', {'a': fmtMoney(cd.expected)}));
    }
    final f = audit().where((x) => x.severity != Severity.info).toList();
    b.writeln(f.isEmpty
        ? tr('✅ التدقيق المالي: الحسابات سليمة')
        : tr('⚠️ التدقيق المالي: {n} ملاحظة — {t}', {'n': f.length, 't': f.first.title}));
    return b.toString().trim();
  }

  /// درجة صحة الحسابات من 100
  static int healthScore(List<Finding> f) {
    var s = 100;
    for (final x in f) {
      s -= switch (x.severity) {
        Severity.critical => 25,
        Severity.warning => 8,
        Severity.info => 2,
      };
    }
    return s.clamp(0, 100);
  }

  /// أداء كل موظف: ما حصّله، الخصومات، الاستردادات
  List<({String name, double collected, int receipts, double refunds, double discounts})> staffReport(Range r) {
    final m = <String, ({double collected, int receipts, double refunds, double discounts})>{};
    ({double collected, int receipts, double refunds, double discounts}) z(String k) =>
        m[k] ?? (collected: 0.0, receipts: 0, refunds: 0.0, discounts: 0.0);
    for (final p in d.payments.all.where((p) => r.has(p.date))) {
      final k = p.by ?? tr('المالك');
      final x = z(k);
      m[k] = p.amount >= 0
          ? (collected: x.collected + p.amount, receipts: x.receipts + 1, refunds: x.refunds, discounts: x.discounts)
          : (collected: x.collected, receipts: x.receipts, refunds: x.refunds - p.amount, discounts: x.discounts);
    }
    for (final inv in d.invoices.all.where((i) => !i.voided && r.has(i.date) && i.discount > 0)) {
      final k = inv.createdBy ?? tr('المالك');
      final x = z(k);
      m[k] = (collected: x.collected, receipts: x.receipts, refunds: x.refunds, discounts: x.discounts + inv.discount);
    }
    return [
      for (final e in m.entries)
        (name: e.key, collected: roundMoney(e.value.collected), receipts: e.value.receipts, refunds: roundMoney(e.value.refunds), discounts: roundMoney(e.value.discounts))
    ]..sort((a, b) => b.collected.compareTo(a.collected));
  }

  // ---------------------------------------------------------------------------
  // التدقيق الآلي
  // ---------------------------------------------------------------------------

  static int? _seq(String number) {
    final m = RegExp(r'(\d+)$').firstMatch(number);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  static String _prefix(String number) => number.replaceFirst(RegExp(r'\d+$'), '');

  List<String> _gaps(Iterable<String> numbers) {
    final byPrefix = <String, List<int>>{};
    for (final n in numbers) {
      final s = _seq(n);
      if (s != null) (byPrefix[_prefix(n)] ??= []).add(s);
    }
    final out = <String>[];
    for (final e in byPrefix.entries) {
      final set = e.value.toSet();
      if (set.length < 2) continue;
      final lo = set.reduce(math.min), hi = set.reduce(math.max);
      final width = numbers.firstWhere((n) => _prefix(n) == e.key).length - e.key.length;
      for (var i = lo; i <= hi && out.length < 50; i++) {
        if (!set.contains(i)) out.add('${e.key}${i.toString().padLeft(width, '0')}');
      }
    }
    return out;
  }

  List<Finding> audit() {
    final out = <Finding>[];
    final today = d.today;
    String inv(Invoice i) => '${i.number} — ${i.customerName ?? d.members[i.memberId]?.name ?? ''}';

    // 1) المدفوع المسجّل في الفاتورة = مجموع دفعاتها
    final mism = [for (final i in d.invoices.all) if ((i.paid - _paySum(i.id)).abs() > 0.01) i];
    if (mism.isNotEmpty) {
      out.add(Finding('paid_mismatch', Severity.critical, tr('المدفوع في الفاتورة لا يطابق دفعاتها'),
          tr('يحدث عند انقطاع أثناء الحفظ أو دمج من أجهزة متعددة. الإصلاح يعيد الحساب من الدفعات نفسها.'),
          [for (final i in mism) '${inv(i)}: ${fmtMoney(i.paid)} ≠ ${fmtMoney(_paySum(i.id))}'],
          fixLabel: tr('إعادة الحساب من الدفعات'), fix: () async {
        for (final i in mism) {
          i.paid = _paySum(i.id);
        }
        await d.putAll([...mism, d.auditEntry('audit_fix', tr('إعادة حساب المدفوع في {n} فاتورة', {'n': mism.length}))]);
      }));
    }
    // 2) دفعات بلا فاتورة
    final orphan = [for (final p in d.payments.all) if (d.invoices[p.invoiceId] == null) p];
    if (orphan.isNotEmpty) {
      out.add(Finding('orphan_payment', Severity.critical, tr('دفعات لا ترتبط بأي فاتورة'), tr('راجعها: قد تكون فاتورتها حُذفت من نسخة احتياطية قديمة.'),
          [for (final p in orphan) '${p.number}: ${fmtMoney(p.amount)} — ${dayKey(p.date)}']));
    }
    // 3) فاتورة ملغاة عليها دفعات
    final vp = [for (final i in d.invoices.all) if (i.voided && _paySum(i.id).abs() > 0.01) i];
    if (vp.isNotEmpty) {
      out.add(Finding('voided_paid', Severity.critical, tr('فواتير ملغاة ما زال عليها مبالغ مقبوضة'), tr('يجب ردّ المبلغ للعضو وتسجيل الاسترداد.'),
          [for (final i in vp) '${inv(i)}: ${fmtMoney(_paySum(i.id))}']));
    }
    // 4) أرقام مكررة
    List<String> dups(Iterable<String> ns) {
      final seen = <String>{}, dup = <String>{};
      for (final n in ns) {
        if (!seen.add(n)) dup.add(n);
      }
      return dup.toList();
    }

    final di = dups(d.invoices.all.map((i) => i.number));
    final dr = dups(d.payments.all.map((p) => p.number));
    if (di.isNotEmpty || dr.isNotEmpty) {
      out.add(Finding('dup_numbers', Severity.critical, tr('أرقام فواتير أو إيصالات مكررة'), tr('كل رقم يجب أن يُستخدم مرة واحدة.'), [...di, ...dr]));
    }
    // 5) أرقام ناقصة من التسلسل (فاتورة حُذفت) — عند العمل على جهاز واحد
    if (!d.syncSlotted) {
      final gi = _gaps(d.invoices.all.map((i) => i.number));
      final gr = _gaps(d.payments.all.map((p) => p.number));
      if (gi.isNotEmpty || gr.isNotEmpty) {
        out.add(Finding('gaps', Severity.warning, tr('أرقام ناقصة من تسلسل الفواتير أو الإيصالات'),
            tr('الفواتير لا تُحذف في البرنامج (تُلغى فقط)، فالرقم الناقص يعني حذفاً من خارجه أو استعادة نسخة قديمة.'), [...gi, ...gr]));
      }
    }
    // 6) توازن القيود
    final unb = [for (final e in journal()) if (!e.balanced) e];
    if (unb.isNotEmpty) {
      out.add(Finding('unbalanced', Severity.critical, tr('قيود غير متوازنة'), tr('بيانات الفاتورة غير متسقة.'),
          [for (final e in unb) '${e.ref}: ${fmtMoney(e.debit)} / ${fmtMoney(e.credit)}']));
    }
    // 7) مدفوع أكثر من قيمة الفاتورة
    final over = [for (final i in d.invoices.all) if (!i.voided && i.balance < -0.01) i];
    if (over.isNotEmpty) {
      out.add(Finding('overpaid', Severity.warning, tr('مبالغ مدفوعة أكثر من قيمة الفاتورة'), tr('الزيادة حق للعضو: ردّها أو احسبها من فاتورة قادمة.'),
          [for (final i in over) '${inv(i)}: ${fmtMoney(-i.balance)}']));
    }
    // 8) أقساط أكثر من قيمة الفاتورة
    final instBad = [
      for (final i in d.invoices.all)
        if (!i.voided && i.installments.isNotEmpty && i.installments.fold(0.0, (s, x) => s + x.amount) - i.total > 0.01) i
    ];
    if (instBad.isNotEmpty) {
      out.add(Finding('installments', Severity.warning, tr('مجموع الأقساط أكبر من قيمة الفاتورة'), tr('عدّل جدول الأقساط.'),
          [for (final i in instBad) inv(i)]));
    }
    // 9) تحويلات لم يُتأكد من وصولها
    final unv = [for (final p in d.payments.all) if (p.needsCheck && daysBetween(dateOnly(p.date), today) > 3) p];
    if (unv.isNotEmpty) {
      out.add(Finding('unverified', Severity.warning, tr('تحويلات ومحافظ لم يُتأكد من وصولها منذ أكثر من 3 أيام'),
          tr('افتح المالية › المطابقة وقارنها بكشف الحساب.'),
          [for (final p in unv) '${p.number}: ${fmtMoney(p.amount)} — ${p.account ?? payMethodName(p.method)} ${p.reference ?? ''}']));
    }
    // 10) اشتراك بلا فاتورة
    final noInv = [for (final s in d.subs.all) if (!s.imported && !s.cancelled && (s.invoiceId == null || d.invoices[s.invoiceId] == null)) s];
    if (noInv.isNotEmpty) {
      out.add(Finding('sub_no_invoice', Severity.warning, tr('اشتراكات بدون فاتورة'), tr('خدمة قُدّمت بدون قيمة مسجّلة.'),
          [for (final s in noInv) '${d.members[s.memberId]?.name ?? ''}: ${s.planName} (${dayKey(s.start)})']));
    }
    // 11) فروقات الصندوق
    final varc = [for (final c in d.closes.all) if (c.variance.abs() >= 0.5 && daysBetween(c.day, today) <= 30) c]
      ..sort((a, b) => b.day.compareTo(a.day));
    if (varc.isNotEmpty) {
      out.add(Finding('cash_variance', Severity.warning, tr('فروقات في إغلاق الصندوق'), tr('عجز أو زيادة بين المعدود والمتوقع.'),
          [for (final c in varc) '${dayKey(c.day)}: ${c.variance > 0 ? '+' : ''}${fmtMoney(c.variance)} (${c.by ?? tr('المالك')})']));
    }
    // 12) أيام فيها نقد بلا إغلاق صندوق
    final missing = <String>[];
    for (var i = 1; i <= 7; i++) {
      final day = addDays(today, -i);
      final cd = cashDay(day);
      if ((cd.cashIn > 0 || cd.cashExpenses > 0) && closeOf(day) == null) missing.add('${dayKey(day)}: ${fmtMoney(cd.expected)}');
    }
    if (missing.isNotEmpty) {
      out.add(Finding('no_close', Severity.info, tr('أيام بدون إغلاق صندوق'), tr('أغلق الصندوق آخر كل يوم لتكشف أي عجز فوراً.'), missing));
    }
    // 13) خصومات أعلى من الحد المسموح
    final maxPct = d.settings.maxDiscountPct;
    final bigDisc = [
      for (final i in d.invoices.all)
        if (!i.voided && daysBetween(dateOnly(i.date), today) <= 30 && i.subtotal > 0 && i.discount / i.subtotal * 100 > maxPct + 0.01) i
    ];
    if (bigDisc.isNotEmpty) {
      out.add(Finding('big_discount', Severity.info, tr('خصومات أعلى من الحد المسموح للاستقبال ({p}%)', {'p': fmtNum(maxPct)}),
          tr('آخر 30 يوماً. تأكد أنها بموافقتك.'),
          [for (final i in bigDisc) '${inv(i)}: ${fmtNum(i.discount / i.subtotal * 100)}% — ${i.createdBy ?? tr('المالك')}']));
    }
    // 14) عمليات حساسة
    const sensitive = {'refund', 'cancel', 'void', 'reject', 'override', 'adjust', 'price', 'audit_fix', 'writeoff', 'unlock', 'move_delete', 'expense_delete'};
    final ops = [for (final a in d.audit.all) if (sensitive.contains(a.action) && daysBetween(dateOnly(a.time), today) <= 7) a]
      ..sort((a, b) => b.time.compareTo(a.time));
    if (ops.isNotEmpty) {
      out.add(Finding('sensitive', Severity.info, tr('عمليات حساسة آخر 7 أيام'), tr('استرداد، إلغاء، سماح استثنائي، تعديل أسعار أو اشتراكات.'),
          [for (final a in ops) '${dayKey(a.time)} ${a.user ?? tr('المالك')}: ${a.details}']));
    }
    // 15) مخزون سالب أو بيع بأقل من التكلفة
    final neg = [for (final p in d.products.all) if (p.trackStock && p.stock < 0) p];
    final loss = [for (final p in d.products.all) if (p.active && p.cost > 0 && p.price < p.cost) p];
    if (neg.isNotEmpty || loss.isNotEmpty) {
      out.add(Finding('stock', Severity.warning, tr('المتجر: مخزون سالب أو سعر أقل من التكلفة'), tr('راجع الجرد والأسعار.'), [
        for (final p in neg) tr('{p}: المخزون {q}', {'p': p.name, 'q': fmtNum(p.stock)}),
        for (final p in loss) tr('{p}: السعر {a} أقل من التكلفة {c}', {'p': p.name, 'a': fmtMoney(p.price), 'c': fmtMoney(p.cost)}),
      ]));
    }
    // 16) تواريخ مستقبلية أو دفعة قبل فاتورتها
    final fut = <String>[
      for (final p in d.payments.all) if (dateOnly(p.date).isAfter(addDays(today, 1))) '${p.number}: ${dayKey(p.date)}',
      for (final i in d.invoices.all) if (dateOnly(i.date).isAfter(addDays(today, 1))) '${i.number}: ${dayKey(i.date)}',
      for (final e in d.expenses.all) if (dateOnly(e.date).isAfter(addDays(today, 1))) '${e.category}: ${dayKey(e.date)}',
    ];
    if (fut.isNotEmpty) {
      out.add(Finding('future', Severity.warning, tr('عمليات بتاريخ مستقبلي'), tr('غالباً تاريخ الجهاز خاطئ. صحّح تاريخ الجوال.'), fut));
    }
    // 17) ديون قديمة
    final old = [for (final i in d.invoices.all) if (i.balance > 0.001 && daysBetween(dateOnly(i.date), today) > 90) i];
    if (old.isNotEmpty) {
      out.add(Finding('old_debt', Severity.info, tr('ديون عمرها أكثر من 90 يوماً'), tr('تابع تحصيلها، أو افتح الفاتورة واختر «إعدام الدين» إن تعذّر التحصيل.'),
          [for (final i in old) '${inv(i)}: ${fmtMoney(i.balance)}']));
    }
    // 18) تغيّر في فترة مقفلة
    for (final l in d.locks.all) {
      final now = _snapshot(l.until);
      final diff = <String>[
        for (final k in {...l.snapshot.keys, ...now.keys})
          if (((now[k] ?? 0) - (l.snapshot[k] ?? 0)).abs() > 0.01)
            '${Accounts.label(k)}: ${fmtMoney(l.snapshot[k] ?? 0)} → ${fmtMoney(now[k] ?? 0)}',
      ];
      if (diff.isNotEmpty) {
        out.add(Finding('lock_changed', Severity.critical, tr('تغيّرت أرقام فترة مقفلة (حتى {d})', {'d': dayKey(l.until)}), tr('عملية بتاريخ قديم وصلت من جهاز آخر أو من نسخة احتياطية. راجعها في دفتر اليومية.'), diff));
      }
    }
    // 19) حساب مالي برصيد سالب
    final negMoney = [for (final e in moneyBalances(today).entries) if (e.value < -0.01) e];
    if (negMoney.isNotEmpty) {
      out.add(Finding('negative_money', Severity.warning, tr('حسابات مالية برصيد سالب'),
          tr('سجّل الرصيد الافتتاحي أو التحويل الناقص من «حركة مال»، أو راجع المصروفات المسجّلة عليه.'),
          [for (final e in negMoney) '${Accounts.label(e.key)}: ${fmtMoney(e.value)}']));
    }
    // 20) مصروفات أعلى من المعتاد
    final cut = addDays(today, -30);
    final recent = <String, double>{}, past = <String, double>{};
    for (final e in d.expenses.all) {
      final age = daysBetween(dateOnly(e.date), today);
      if (age < 0) continue;
      if (!e.date.isBefore(cut)) {
        recent[e.category] = (recent[e.category] ?? 0) + e.amount;
      } else if (age <= 120) {
        past[e.category] = (past[e.category] ?? 0) + e.amount;
      }
    }
    final spikes = [
      for (final e in recent.entries)
        if ((past[e.key] ?? 0) > 0 && e.value > 2 * past[e.key]! / 3 && e.value - past[e.key]! / 3 > 100)
          tr('{c}: {a} (المعتاد {n} شهرياً)', {'c': e.key, 'a': fmtMoney(e.value), 'n': fmtMoney(past[e.key]! / 3)})
    ];
    if (spikes.isNotEmpty) {
      out.add(Finding('expense_spike', Severity.info, tr('مصروفات أعلى من المعتاد آخر 30 يوماً'), tr('أكثر من ضعف متوسط الأشهر الثلاثة السابقة. تأكد أنها صحيحة.'), spikes));
    }
    // 21) الشهر الماضي غير مقفل
    final lastMonthEnd = DateTime(today.year, today.month, 0);
    final lu = d.lockedUntil;
    if (today.day >= 5 && (lu == null || lu.isBefore(lastMonthEnd)) && d.invoices.all.any((i) => !i.date.isAfter(lastMonthEnd))) {
      out.add(Finding('no_lock', Severity.info, tr('الشهر الماضي غير مقفل'), tr('أقفله من «الأرصدة» بعد مراجعته، فلا تتغير أرقامه بعد ذلك.'), [dayKey(lastMonthEnd).substring(0, 7)]));
    }
    out.sort((a, b) => a.severity.index.compareTo(b.severity.index));
    return out;
  }

  double _paySum(String invoiceId) => roundMoney(d.paymentsOf(invoiceId).fold(0.0, (s, p) => s + p.amount));

  // ---------------------------------------------------------------------------
  // التصدير
  // ---------------------------------------------------------------------------

  List<List<Object?>> journalRows(Range r) => [
        [tr('التاريخ'), tr('المرجع'), tr('البيان'), tr('الحساب'), tr('مدين'), tr('دائن')],
        for (final e in journal(r))
          for (final l in e.lines) [dayKey(e.date), e.ref, e.text, Accounts.label(l.account), l.debit == 0 ? '' : l.debit, l.credit == 0 ? '' : l.credit],
      ];

  List<List<Object?>> trialRows(Range r) {
    final rows = trialBalance(r);
    return [
      [tr('الحساب'), tr('مدين'), tr('دائن'), tr('الرصيد')],
      for (final t in rows) [Accounts.label(t.account), t.debit, t.credit, t.balance],
      [tr('المجموع'), roundMoney(rows.fold(0.0, (s, t) => s + t.debit)), roundMoney(rows.fold(0.0, (s, t) => s + t.credit)), ''],
    ];
  }
}
