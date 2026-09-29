import '../core/i18n.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../data/gym_data.dart';
import '../models/base.dart';
import '../models/billing.dart';
import '../models/business.dart';
import 'membership.dart';

/// سطر في سلة المتجر
class CartLine {
  final Product product;
  double qty;
  CartLine(this.product, [this.qty = 1]);
  double get total => roundMoney(product.price * qty);
}

class BillingService {
  final GymData d;
  final MembershipService ms;
  BillingService(this.d) : ms = MembershipService(d);

  /// تحصيل دفعة على فاتورة
  Future<Payment> collect(Invoice inv, double amount, PayMethod method, {String? reference, String? note}) async {
    amount = roundMoney(amount);
    if (inv.voided) throw GymException(tr('الفاتورة ملغاة'));
    if (amount <= 0) throw GymException(tr('اكتب مبلغاً صحيحاً'));
    if (amount - inv.balance > 0.001) {
      throw GymException(tr('المبلغ أكبر من المتبقي ({b})', {'b': fmtMoney(inv.balance)}));
    }
    final p = ms.newPayment(inv, PayInput(amount, method, reference), note: note);
    inv.paid = roundMoney(inv.paid + amount);
    await d.putAll([p, inv]);
    return p;
  }

  /// توزيع مبلغ على ديون العضو (الأقدم أولاً)
  Future<List<Payment>> collectFromMember(String memberId, double amount, PayMethod method, {String? reference}) async {
    amount = roundMoney(amount);
    final open = d.invoicesOf(memberId).where((i) => i.balance > 0).toList()..sort((a, b) => a.date.compareTo(b.date));
    final total = open.fold(0.0, (s, i) => s + i.balance);
    if (amount <= 0) throw GymException(tr('اكتب مبلغاً صحيحاً'));
    if (amount - total > 0.001) throw GymException(tr('المبلغ أكبر من المستحق ({b})', {'b': fmtMoney(total)}));
    final out = <Payment>[];
    final save = <Entity>[];
    var left = amount;
    for (final inv in open) {
      if (left <= 0) break;
      final part = left >= inv.balance ? inv.balance : left;
      final p = ms.newPayment(inv, PayInput(part, method, reference));
      inv.paid = roundMoney(inv.paid + part);
      left = roundMoney(left - part);
      out.add(p);
      save..add(p)..add(inv);
    }
    await d.putAll(save);
    return out;
  }

  /// استرداد مبلغ من فاتورة (يقلل المدفوع ويُسجل في سجل العمليات)
  Future<Payment> refund(Invoice inv, double amount, PayMethod method, String reason) async {
    if (!d.can(Perm.refund)) throw GymException(tr('ليست لديك صلاحية الاسترداد'));
    amount = roundMoney(amount);
    if (amount <= 0 || amount - inv.paid > 0.001) throw GymException(tr('مبلغ الاسترداد غير صحيح'));
    final p = ms.newPayment(inv, PayInput(-amount, method), note: tr('استرداد: {r}', {'r': reason}));
    inv.paid = roundMoney(inv.paid - amount);
    await d.putAll([p, inv, d.auditEntry('refund', '${inv.number}: ${fmtMoney(amount)} — $reason')]);
    return p;
  }

  /// إلغاء فاتورة لم يُدفع منها شيء: تُلغى اشتراكاتها ويعود المخزون
  Future<void> voidInvoice(Invoice inv, String reason) async {
    if (!d.can(Perm.refund)) throw GymException(tr('ليست لديك صلاحية إلغاء الفواتير'));
    if (inv.voided) return;
    if (inv.paid > 0.001) throw GymException(tr('استرد المبلغ المدفوع أولاً ثم ألغِ الفاتورة'));
    final save = <Entity>[];
    for (final item in inv.items) {
      if (item.refId == null) continue;
      final sub = d.subs[item.refId];
      if (sub != null && !sub.cancelled) {
        sub
          ..cancelled = true
          ..cancelledAt = d.now()
          ..cancelReason = reason;
        save.add(sub);
      }
      final prod = d.products[item.refId];
      if (prod != null && item.kind == ItemKind.product && prod.trackStock) {
        prod.stock += item.qty;
        save.add(prod);
      }
    }
    inv
      ..voided = true
      ..voidReason = reason
      ..installments.clear();
    save
      ..add(inv)
      ..add(d.auditEntry('void', '${inv.number} — $reason'));
    await d.putAll(save);
  }

  /// بيع من متجر النادي (لعضو أو لزائر)
  Future<Invoice> sellProducts(List<CartLine> cart,
      {String? memberId, String? customerName, List<PayInput> payments = const [], double discount = 0}) async {
    if (cart.isEmpty) throw GymException(tr('السلة فارغة'));
    for (final l in cart) {
      final p = l.product;
      if (p.trackStock && p.stock < l.qty) {
        throw GymException(tr('الكمية غير متوفرة من {p} (المتوفر {q})', {'p': p.name, 'q': fmtNum(p.stock)}));
      }
    }
    final inv = ms.newInvoice(
      memberId: memberId,
      customerName: customerName,
      discount: discount,
      items: [
        for (final l in cart)
          InvoiceItem(
              kind: ItemKind.product, refId: l.product.id, description: l.product.name, qty: l.qty, unitPrice: l.product.price),
      ],
    );
    final paidNow = payments.fold(0.0, (s, p) => s + p.amount);
    if (paidNow - inv.total > 0.001) throw GymException(tr('المبلغ المدفوع أكبر من الإجمالي'));
    if (memberId == null && inv.total - paidNow > 0.001) {
      throw GymException(tr('البيع بالآجل يحتاج اختيار عضو'));
    }
    final pays = [for (final p in payments.where((p) => p.amount > 0)) ms.newPayment(inv, p)];
    inv.paid = roundMoney(pays.fold(0.0, (s, p) => s + p.amount));
    for (final l in cart) {
      if (l.product.trackStock) l.product.stock -= l.qty;
    }
    await d.putAll([inv, ...pays, ...cart.map((l) => l.product)]);
    return inv;
  }

  /// فاتورة يدوية (رسوم خزانة، حصة منفردة، غرامة...)
  Future<Invoice> customInvoice({required String memberId, required List<InvoiceItem> items, List<PayInput> payments = const []}) async {
    final inv = ms.newInvoice(memberId: memberId, items: items);
    final pays = [for (final p in payments.where((p) => p.amount > 0)) ms.newPayment(inv, p)];
    inv.paid = roundMoney(pays.fold(0.0, (s, p) => s + p.amount));
    await d.putAll([inv, ...pays]);
    return inv;
  }

  /// إنشاء مصروف
  Future<Expense> addExpense({required DateTime date, required String category, required double amount, String? note}) async {
    if (!d.can(Perm.expenses)) throw GymException(tr('ليست لديك صلاحية المصروفات'));
    if (amount <= 0) throw GymException(tr('اكتب مبلغاً صحيحاً'));
    final e = Expense(id: newId(), date: date, category: category, amount: roundMoney(amount), note: note, by: d.userName);
    await d.put(e);
    return e;
  }

  /// الأقساط المستحقة (لشاشة التحصيل والتذكيرات)
  List<({Invoice invoice, Installment inst, double left})> dueInstallments({DateTime? until}) {
    final out = <({Invoice invoice, Installment inst, double left})>[];
    for (final inv in d.invoices.all) {
      if (inv.voided || inv.installments.isEmpty || inv.balance <= 0) continue;
      for (final s in inv.installmentStatus()) {
        if (s.left <= 0) continue;
        if (until != null && s.inst.due.isAfter(until)) continue;
        out.add((invoice: inv, inst: s.inst, left: s.left));
      }
    }
    out.sort((a, b) => a.inst.due.compareTo(b.inst.due));
    return out;
  }

  /// الأعضاء المدينون مع مبلغ الدين
  List<({String memberId, double balance, double overdue})> debtors() {
    final out = <({String memberId, double balance, double overdue})>[];
    for (final m in d.members.all) {
      final b = d.balanceOf(m.id);
      if (b > 0.001) out.add((memberId: m.id, balance: b, overdue: d.overdueOf(m.id)));
    }
    out.sort((a, b) => b.balance.compareTo(a.balance));
    return out;
  }
}
