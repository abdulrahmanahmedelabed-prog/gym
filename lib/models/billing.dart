import '../core/dates.dart';
import '../core/money.dart';
import 'base.dart';

/// نوع بند الفاتورة (للتقارير: كم دخل من الاشتراكات، التدريب الشخصي، المتجر...)
enum ItemKind { subscription, registration, pt, product, locker, classFee, other }

ItemKind itemKindFrom(Object? v) =>
    ItemKind.values.firstWhere((k) => k.name == v, orElse: () => ItemKind.other);

class InvoiceItem {
  ItemKind kind;
  String? refId; // معرّف الاشتراك أو المنتج
  String description;
  double qty;
  double unitPrice;
  double discount;

  InvoiceItem({
    required this.kind,
    required this.description,
    this.refId,
    this.qty = 1,
    required this.unitPrice,
    this.discount = 0,
  });

  double get total => roundMoney(qty * unitPrice - discount);

  Map<String, Object?> toMap() => compact({
        'kind': kind.name,
        'refId': refId,
        'description': description,
        'qty': qty,
        'unitPrice': unitPrice,
        'discount': discount == 0 ? null : discount,
      });

  factory InvoiceItem.fromMap(Map<String, Object?> m) => InvoiceItem(
        kind: itemKindFrom(m['kind']),
        refId: asStrOrNull(m['refId']),
        description: asStr(m['description']),
        qty: asDouble(m['qty'], 1),
        unitPrice: asDouble(m['unitPrice']),
        discount: asDouble(m['discount']),
      );
}

/// قسط: مبلغ مستحق في تاريخ. ما دُفع يوزَّع على الأقساط بالترتيب (الأقدم أولاً).
class Installment {
  DateTime due;
  double amount;

  Installment({required this.due, required this.amount});

  Map<String, Object?> toMap() => {'due': dayKey(due), 'amount': amount};

  factory Installment.fromMap(Map<String, Object?> m) =>
      Installment(due: parseDay(asStr(m['due'])), amount: asDouble(m['amount']));
}

enum LinkStatus { pending, paid, failed, cancelled }

/// رابط دفع إلكتروني أُنشئ عبر بوابة الدفع
class PaymentLink {
  final String provider;
  final String externalId;
  final String url;
  final double amount;
  LinkStatus status;
  final DateTime createdAt;
  DateTime? paidAt;

  PaymentLink({
    required this.provider,
    required this.externalId,
    required this.url,
    required this.amount,
    this.status = LinkStatus.pending,
    required this.createdAt,
    this.paidAt,
  });

  Map<String, Object?> toMap() => compact({
        'provider': provider,
        'externalId': externalId,
        'url': url,
        'amount': amount,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        'paidAt': paidAt?.toIso8601String(),
      });

  factory PaymentLink.fromMap(Map<String, Object?> m) => PaymentLink(
        provider: asStr(m['provider']),
        externalId: asStr(m['externalId']),
        url: asStr(m['url']),
        amount: asDouble(m['amount']),
        status: LinkStatus.values.firstWhere((s) => s.name == m['status'], orElse: () => LinkStatus.pending),
        createdAt: asTime(m['createdAt']) ?? DateTime.now(),
        paidAt: asTime(m['paidAt']),
      );
}

enum InvoiceStatus { paid, partial, unpaid, voided, writtenOff }

class Invoice implements Entity {
  @override
  final String id;
  final String number;
  String? memberId; // فارغ لبيع المتجر لزائر
  String? customerName;
  final DateTime date;
  List<InvoiceItem> items;
  double discount; // خصم على الفاتورة كلها
  double taxRate; // 0.15 = 15%
  bool taxInclusive;
  double paid; // مجموع المدفوعات (يُحدّث مع كل دفعة)
  List<Installment> installments;
  List<PaymentLink> links;
  bool voided;
  String? voidReason;
  DateTime? voidedAt;
  double writtenOff; // دين معدوم: مبلغ تنازل عنه النادي بقرار (لا يُحصّل ولا يُذكَّر به)
  DateTime? writtenOffAt;
  String? notes;
  String? createdBy;
  String? pendingPlanId; // فاتورة تجديد: يُنشأ الاشتراك تلقائياً عند اكتمال دفعها

  Invoice({
    required this.id,
    required this.number,
    this.memberId,
    this.customerName,
    required this.date,
    required this.items,
    this.discount = 0,
    this.taxRate = 0,
    this.taxInclusive = true,
    this.paid = 0,
    List<Installment>? installments,
    List<PaymentLink>? links,
    this.voided = false,
    this.voidReason,
    this.voidedAt,
    this.writtenOff = 0,
    this.writtenOffAt,
    this.notes,
    this.createdBy,
    this.pendingPlanId,
  })  : installments = installments ?? [],
        links = links ?? [];

  double get subtotal => roundMoney(items.fold(0.0, (s, i) => s + i.total));

  double get taxable => roundMoney(subtotal - discount);

  double get tax {
    if (taxRate <= 0) return 0;
    return taxInclusive
        ? roundMoney(taxable - taxable / (1 + taxRate))
        : roundMoney(taxable * taxRate);
  }

  double get total => voided ? 0 : grossTotal;

  /// الإجمالي حسب البنود حتى لو أُلغيت الفاتورة (لقيد الإلغاء في المحاسبة)
  double get grossTotal => roundMoney(taxInclusive ? taxable : taxable + tax);

  /// المبلغ قبل الضريبة
  double get net => roundMoney(total - tax);

  double get balance => voided ? 0 : roundMoney(total - paid - writtenOff);

  InvoiceStatus get status {
    if (voided) return InvoiceStatus.voided;
    if (balance <= 0.0001) return writtenOff > 0 ? InvoiceStatus.writtenOff : InvoiceStatus.paid;
    if (paid > 0) return InvoiceStatus.partial;
    return InvoiceStatus.unpaid;
  }

  /// الأقساط مع ما دُفع من كل قسط (توزيع المدفوع على الأقدم أولاً)
  List<({Installment inst, double paid, double left})> installmentStatus() {
    var remaining = paid;
    // المبلغ المدفوع مقدماً (غير المقسط) يُخصم أولاً
    final scheduled = installments.fold(0.0, (s, i) => s + i.amount);
    remaining -= (total - scheduled);
    final out = <({Installment inst, double paid, double left})>[];
    for (final i in installments) {
      final p = remaining <= 0 ? 0.0 : (remaining >= i.amount ? i.amount : remaining);
      remaining -= p;
      out.add((inst: i, paid: roundMoney(p), left: roundMoney(i.amount - p)));
    }
    return out;
  }

  /// أقرب قسط غير مدفوع بالكامل
  ({Installment inst, double left})? nextDueInstallment() {
    for (final s in installmentStatus()) {
      if (s.left > 0.0001) return (inst: s.inst, left: s.left);
    }
    return null;
  }

  @override
  Map<String, Object?> toMap() => compact({
        'id': id,
        'number': number,
        'memberId': memberId,
        'customerName': customerName,
        'date': date.toIso8601String(),
        'items': items.map((i) => i.toMap()).toList(),
        'discount': discount == 0 ? null : discount,
        'taxRate': taxRate == 0 ? null : taxRate,
        'taxInclusive': taxInclusive,
        'paid': paid,
        'installments': installments.isEmpty ? null : installments.map((i) => i.toMap()).toList(),
        'links': links.isEmpty ? null : links.map((l) => l.toMap()).toList(),
        'voided': voided ? true : null,
        'voidReason': voidReason,
        'voidedAt': voidedAt?.toIso8601String(),
        'writtenOff': writtenOff == 0 ? null : writtenOff,
        'writtenOffAt': writtenOffAt?.toIso8601String(),
        'notes': notes,
        'createdBy': createdBy,
        'pendingPlanId': pendingPlanId,
      });

  factory Invoice.fromMap(Map<String, Object?> m) => Invoice(
        id: asStr(m['id']),
        number: asStr(m['number']),
        memberId: asStrOrNull(m['memberId']),
        customerName: asStrOrNull(m['customerName']),
        date: asTime(m['date']) ?? DateTime.now(),
        items: asMapList(m['items']).map(InvoiceItem.fromMap).toList(),
        discount: asDouble(m['discount']),
        taxRate: asDouble(m['taxRate']),
        taxInclusive: asBool(m['taxInclusive'], true),
        paid: asDouble(m['paid']),
        installments: asMapList(m['installments']).map(Installment.fromMap).toList(),
        links: asMapList(m['links']).map(PaymentLink.fromMap).toList(),
        voided: asBool(m['voided']),
        voidReason: asStrOrNull(m['voidReason']),
        voidedAt: asTime(m['voidedAt']),
        writtenOff: asDouble(m['writtenOff']),
        writtenOffAt: asTime(m['writtenOffAt']),
        notes: asStrOrNull(m['notes']),
        createdBy: asStrOrNull(m['createdBy']),
        pendingPlanId: asStrOrNull(m['pendingPlanId']),
      );
}

enum PayMethod { cash, card, transfer, wallet, online }

PayMethod payMethodFrom(Object? v) =>
    PayMethod.values.firstWhere((k) => k.name == v, orElse: () => PayMethod.cash);

/// دفعة (أو استرداد إذا كان المبلغ سالباً)
class Payment implements Entity {
  @override
  final String id;
  final String number;
  final String invoiceId;
  final String? memberId;
  final DateTime date;
  final double amount;
  final PayMethod method;
  final String? reference; // رقم العملية / آخر 4 أرقام البطاقة
  final String? note;
  final String? by;
  final String? account; // اسم المحفظة/الحساب الذي استُلم عليه المبلغ
  bool verified; // تأكد الموظف من وصول المبلغ إلى الحساب (للتحويلات والمحافظ)
  DateTime? verifiedAt;

  Payment({
    required this.id,
    required this.number,
    required this.invoiceId,
    this.memberId,
    required this.date,
    required this.amount,
    required this.method,
    this.reference,
    this.note,
    this.by,
    this.account,
    this.verified = true,
    this.verifiedAt,
  });

  bool get isRefund => amount < 0;

  /// دفعة تحتاج مطابقة مع كشف المحفظة/البنك
  bool get needsCheck => !verified && amount > 0;

  @override
  Map<String, Object?> toMap() => compact({
        'id': id,
        'number': number,
        'invoiceId': invoiceId,
        'memberId': memberId,
        'date': date.toIso8601String(),
        'amount': amount,
        'method': method.name,
        'reference': reference,
        'note': note,
        'by': by,
        'account': account,
        'verified': verified ? null : false,
        'verifiedAt': verifiedAt?.toIso8601String(),
      });

  factory Payment.fromMap(Map<String, Object?> m) => Payment(
        id: asStr(m['id']),
        number: asStr(m['number']),
        invoiceId: asStr(m['invoiceId']),
        memberId: asStrOrNull(m['memberId']),
        date: asTime(m['date']) ?? DateTime.now(),
        amount: asDouble(m['amount']),
        method: payMethodFrom(m['method']),
        reference: asStrOrNull(m['reference']),
        note: asStrOrNull(m['note']),
        by: asStrOrNull(m['by']),
        account: asStrOrNull(m['account']),
        verified: asBool(m['verified'], true),
        verifiedAt: asTime(m['verifiedAt']),
      );
}
