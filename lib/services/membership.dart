import '../core/dates.dart';
import '../core/i18n.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../data/gym_data.dart';
import '../models/base.dart';
import '../models/billing.dart';
import '../models/business.dart';
import '../models/member.dart';
import '../models/plan.dart';
import '../models/subscription.dart';
import 'license.dart';

/// حالة العضو كما تظهر في القوائم
enum MemberState { active, expiring, frozen, pending, expired, none }

class GymException implements Exception {
  final String message;
  GymException(this.message);
  @override
  String toString() => message;
}

/// دفعة تُسجل مع البيع
class PayInput {
  final double amount;
  final PayMethod method;
  final String? reference;
  const PayInput(this.amount, this.method, [this.reference]);
}

/// طلب بيع/تجديد اشتراك
class SaleRequest {
  final String memberId;
  final String planId;
  final DateTime? start;
  final double discount; // خصم يدوي بالمبلغ
  final String? couponCode;
  final bool registrationFee;
  final String? trainerId;
  final List<PayInput> payments;
  final List<Installment> installments;
  final String? notes;
  final List<InvoiceItem> extraItems;

  const SaleRequest({
    required this.memberId,
    required this.planId,
    this.start,
    this.discount = 0,
    this.couponCode,
    this.registrationFee = false,
    this.trainerId,
    this.payments = const [],
    this.installments = const [],
    this.notes,
    this.extraItems = const [],
  });
}

class SaleResult {
  final Subscription subscription;
  final Invoice invoice;
  final List<Payment> payments;
  SaleResult(this.subscription, this.invoice, this.payments);
}

class MembershipService {
  final GymData d;
  MembershipService(this.d);

  // ---------------------------------------------------------------------------
  // الأعضاء
  // ---------------------------------------------------------------------------

  Member newMember({required String name, required String phone, Gender? gender}) => Member(
        id: newId(),
        code: 0,
        name: name.trim(),
        phone: phone.trim(),
        gender: gender,
        cardToken: newCardToken(),
        createdAt: d.now(),
      );

  /// حفظ عضو جديد: يأخذ رقم عضوية تسلسلياً (يبدأ من 1001)
  Future<Member> addMember(Member m) async {
    if (m.name.trim().isEmpty) throw GymException(tr('اكتب اسم العضو'));
    final dup = findByPhone(m.phone);
    if (dup != null && dup.id != m.id) {
      throw GymException(tr('رقم الجوال مسجل للعضو {name} (رقم {code})', {'name': dup.name, 'code': dup.code}));
    }
    if (m.code == 0) m.code = d.nextCounter('member', start: 1001);
    if (m.cardToken.isEmpty) m.cardToken = newCardToken();
    await d.put(m);
    return m;
  }

  Future<void> updateMember(Member m) async {
    final dup = findByPhone(m.phone);
    if (dup != null && dup.id != m.id) {
      throw GymException(tr('رقم الجوال مسجل للعضو {name} (رقم {code})', {'name': dup.name, 'code': dup.code}));
    }
    await d.put(m);
  }

  Member? findByPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7) return null;
    final tail = digits.substring(digits.length - 9 < 0 ? 0 : digits.length - 9);
    for (final m in d.members.all) {
      final md = m.phone.replaceAll(RegExp(r'\D'), '');
      if (md.length >= 7 && md.endsWith(tail)) return m;
    }
    return null;
  }

  /// بحث بالاسم أو الجوال أو رقم العضوية أو رمز البطاقة
  List<Member> search(String q, {bool includeArchived = false}) {
    q = q.trim().toLowerCase();
    final list = d.members.all.where((m) => includeArchived || !m.archived);
    if (q.isEmpty) return list.toList();
    final code = int.tryParse(q);
    return list.where((m) {
      if (code != null && m.code == code) return true;
      if (m.name.toLowerCase().contains(q)) return true;
      if (q.length >= 3 && m.phone.replaceAll(RegExp(r'\D'), '').contains(q)) return true;
      return m.cardToken.toLowerCase() == q;
    }).toList();
  }

  /// قراءة محتوى رمز QR أو باركود بطاقة العضو
  Member? resolveScan(String raw) {
    var s = raw.trim();
    if (s.toUpperCase().startsWith('NADI:')) s = s.substring(5);
    final byToken = d.memberByToken(s.toUpperCase());
    if (byToken != null) return byToken;
    final code = int.tryParse(s);
    if (code != null) return d.memberByCode(code);
    return null;
  }

  // ---------------------------------------------------------------------------
  // الاشتراكات
  // ---------------------------------------------------------------------------

  /// اشتراكات الدخول للنادي (بدون التدريب الشخصي)
  List<Subscription> accessSubs(String memberId) =>
      d.subsOf(memberId).where((s) => s.kind != PlanKind.pt && !s.cancelled).toList();

  List<Subscription> ptSubs(String memberId) =>
      d.subsOf(memberId).where((s) => s.kind == PlanKind.pt && !s.cancelled).toList();

  /// الاشتراك الذي يحدد حالة العضو اليوم
  Subscription? currentSub(String memberId, [DateTime? day]) {
    day ??= d.today;
    final list = accessSubs(memberId);
    if (list.isEmpty) return null;
    Subscription? pick(SubStatus st, {bool latestEnd = true}) {
      Subscription? best;
      for (final s in list) {
        if (s.statusOn(day!) != st) continue;
        if (best == null || (latestEnd ? s.end.isAfter(best.end) : s.start.isBefore(best.start))) best = s;
      }
      return best;
    }

    return pick(SubStatus.active) ??
        pick(SubStatus.frozen) ??
        pick(SubStatus.pending, latestEnd: false) ??
        list.reduce((a, b) => a.end.isAfter(b.end) ? a : b);
  }

  /// اشتراك يبدأ بعد الحالي (تجديد مسبق)
  Subscription? nextSub(String memberId, Subscription current) {
    for (final s in accessSubs(memberId)) {
      if (s.id != current.id && s.start.isAfter(current.end.subtract(const Duration(days: 1)))) return s;
    }
    return null;
  }

  /// هل جدّد العضو بعد هذا الاشتراك؟ (لإيقاف تذكيرات الانتهاء)
  bool renewedAfter(Subscription s) {
    for (final o in accessSubs(s.memberId)) {
      if (o.id != s.id && o.end.isAfter(s.end)) return true;
    }
    return false;
  }

  MemberState stateOf(String memberId, [DateTime? day]) {
    day ??= d.today;
    final s = currentSub(memberId, day);
    if (s == null) return MemberState.none;
    switch (s.statusOn(day)) {
      case SubStatus.active:
        final left = s.visitsLeft;
        if (s.daysLeft(day) <= 7 || (left != null && left <= 2)) {
          return renewedAfter(s) ? MemberState.active : MemberState.expiring;
        }
        return MemberState.active;
      case SubStatus.frozen:
        return MemberState.frozen;
      case SubStatus.pending:
        return MemberState.pending;
      default:
        return MemberState.expired;
    }
  }

  /// تاريخ بداية التجديد المقترح: من نهاية الاشتراك الحالي إن لم ينتهِ بعد، وإلا من اليوم
  DateTime suggestedStart(String memberId) {
    final today = d.today;
    if (!d.settings.renewFromEnd) return today;
    DateTime? lastEnd;
    for (final s in accessSubs(memberId)) {
      if (lastEnd == null || s.end.isAfter(lastEnd)) lastEnd = s.end;
    }
    if (lastEnd != null && !lastEnd.isBefore(today)) return addDays(lastEnd, 1);
    return today;
  }

  bool isNewMember(String memberId) => d.subsOf(memberId).isEmpty;

  int activeMemberCount([DateTime? day]) {
    var n = 0;
    for (final m in d.members.all) {
      if (m.archived) continue;
      final st = stateOf(m.id, day);
      if (st != MemberState.none && st != MemberState.expired) n++;
    }
    return n;
  }

  /// النسخة المجانية: حد أقصى للأعضاء الفعّالين (تجديد عضو فعّال مسموح دائماً)
  void _checkMemberLimit(String memberId) {
    final limit = d.license.memberLimit;
    if (limit >= 1 << 30) return;
    final st = stateOf(memberId);
    if (st != MemberState.none && st != MemberState.expired) return;
    if (activeMemberCount() >= limit) {
      throw LicenseException(tr('النسخة المجانية تتسع لـ {n} عضواً فعّالاً. رقِّ إلى Plus لأعضاء بلا حد', {'n': limit}));
    }
  }

  Coupon? findCoupon(String code) {
    final c = code.trim().toUpperCase();
    for (final x in d.coupons.all) {
      if (x.code.toUpperCase() == c) return x;
    }
    return null;
  }

  /// ضريبة الفاتورة حسب الإعدادات
  Invoice newInvoice({String? memberId, String? customerName, required List<InvoiceItem> items, double discount = 0}) {
    final s = d.settings;
    return Invoice(
      id: newId(),
      number: d.nextNumber('invoice', s.invoicePrefix),
      memberId: memberId,
      customerName: customerName,
      date: d.now(),
      items: items,
      discount: roundMoney(discount),
      taxRate: s.taxEnabled ? s.taxRate / 100 : 0,
      taxInclusive: s.taxInclusive,
      createdBy: d.userName,
    );
  }

  Payment newPayment(Invoice inv, PayInput p, {String? note}) => Payment(
        id: newId(),
        number: d.nextNumber('receipt', 'RC'),
        invoiceId: inv.id,
        memberId: inv.memberId,
        date: d.now(),
        amount: roundMoney(p.amount),
        method: p.method,
        reference: p.reference,
        note: note,
        by: d.userName,
      );

  /// حساب سعر البيع قبل التنفيذ (لعرضه في شاشة البيع)
  ({double price, double fee, double couponDiscount, double total}) quote(SaleRequest r) {
    final plan = d.plans[r.planId];
    if (plan == null) throw GymException(tr('الباقة غير موجودة'));
    final fee = r.registrationFee ? plan.registrationFee : 0.0;
    var couponDiscount = 0.0;
    if (r.couponCode != null && r.couponCode!.trim().isNotEmpty) {
      final c = findCoupon(r.couponCode!);
      if (c == null || !c.usableOn(d.today, plan.id)) throw GymException(tr('كوبون الخصم غير صالح'));
      couponDiscount = roundMoney(c.discountFor(plan.price));
    }
    final extras = r.extraItems.fold(0.0, (s, i) => s + i.total);
    final total = roundMoney(plan.price + fee + extras - couponDiscount - r.discount);
    return (price: plan.price, fee: fee, couponDiscount: couponDiscount, total: total < 0 ? 0 : total);
  }

  /// بيع أو تجديد اشتراك: اشتراك + فاتورة + دفعات + أقساط في عملية واحدة
  Future<SaleResult> sell(SaleRequest r) async {
    final member = d.members[r.memberId];
    final plan = d.plans[r.planId];
    if (member == null) throw GymException(tr('العضو غير موجود'));
    if (plan == null) throw GymException(tr('الباقة غير موجودة'));
    if (plan.gender != null && member.gender != null && plan.gender != member.gender) {
      throw GymException(tr('هذه الباقة مخصصة لـ {g} فقط', {'g': plan.gender == Gender.male ? tr('الرجال') : tr('السيدات')}));
    }
    if (plan.kind == PlanKind.pt) d.require(Feature.personalTraining);
    if (r.installments.isNotEmpty) d.require(Feature.installments);
    if (r.couponCode != null && r.couponCode!.trim().isNotEmpty) d.require(Feature.offers);
    _checkMemberLimit(member.id);
    if (plan.kind == PlanKind.pt && r.trainerId == null) throw GymException(tr('اختر المدرب للتدريب الشخصي'));
    final q = quote(r);
    final totalDiscount = r.discount + q.couponDiscount;
    if (r.discount > 0 && !d.can(Perm.discount)) {
      final pct = (plan.price + q.fee) <= 0 ? 0 : r.discount / (plan.price + q.fee) * 100;
      if (pct > d.settings.maxDiscountPct + 0.001) {
        throw GymException(tr('الخصم أعلى من المسموح ({p}%). يحتاج موافقة المدير', {'p': fmtNum(d.settings.maxDiscountPct)}));
      }
    }
    final paidNow = r.payments.fold(0.0, (s, p) => s + p.amount);
    if (paidNow - q.total > 0.001) throw GymException(tr('المبلغ المدفوع أكبر من الإجمالي'));
    final scheduled = r.installments.fold(0.0, (s, i) => s + i.amount);
    if (r.installments.isNotEmpty && (paidNow + scheduled - q.total).abs() > 0.01) {
      throw GymException(tr('مجموع الأقساط والمدفوع الآن يجب أن يساوي الإجمالي ({t})', {'t': fmtMoney(q.total)}));
    }

    final start = dateOnly(r.start ?? (plan.kind == PlanKind.pt ? d.today : suggestedStart(member.id)));
    final end = periodEnd(start, plan.durationValue, plan.durationUnit);
    final sub = Subscription(
      id: newId(),
      memberId: member.id,
      planId: plan.id,
      planName: plan.name,
      kind: plan.kind,
      start: start,
      end: end,
      visitsTotal: plan.visits,
      price: plan.price,
      discount: roundMoney(totalDiscount),
      freezeDaysAllowed: plan.freezeDays,
      freezeTimesAllowed: plan.freezeTimes,
      trainerId: r.trainerId,
      notes: r.notes,
      createdAt: d.now(),
      createdBy: d.userName,
    );
    final items = <InvoiceItem>[
      InvoiceItem(
        kind: plan.kind == PlanKind.pt ? ItemKind.pt : ItemKind.subscription,
        refId: sub.id,
        description: '${plan.name} (${dayKey(start)} – ${dayKey(end)})',
        unitPrice: plan.price,
      ),
      if (q.fee > 0) InvoiceItem(kind: ItemKind.registration, description: tr('رسوم التسجيل'), unitPrice: q.fee),
      ...r.extraItems,
    ];
    final inv = newInvoice(memberId: member.id, items: items, discount: totalDiscount)
      ..installments = List.of(r.installments)
      ..notes = r.notes;
    sub.invoiceId = inv.id;
    final pays = <Payment>[];
    for (final p in r.payments.where((p) => p.amount > 0)) {
      pays.add(newPayment(inv, p));
    }
    inv.paid = roundMoney(pays.fold(0.0, (s, p) => s + p.amount));

    final toSave = <Entity>[sub, inv, ...pays];
    if (r.couponCode != null && r.couponCode!.trim().isNotEmpty) {
      toSave.add(findCoupon(r.couponCode!)!..uses += 1);
    }
    // مكافأة الترشيح: أيام مجانية لمن رشّح العضو عند أول اشتراك له
    if (member.referredBy != null && isNewMember(member.id) && d.settings.referralRewardDays > 0) {
      final refSub = currentSub(member.referredBy!);
      if (refSub != null && refSub.statusOn(d.today) != SubStatus.expired) {
        refSub.end = addDays(refSub.end, d.settings.referralRewardDays);
        toSave.add(refSub);
        toSave.add(d.auditEntry('referral', '${member.name} › +${d.settings.referralRewardDays}'));
      }
    }
    if (r.discount > 0) {
      toSave.add(d.auditEntry('discount', '${inv.number}: ${fmtMoney(r.discount)} (${member.name})'));
    }
    await d.putAll(toSave);
    return SaleResult(sub, inv, pays);
  }

  // ---------------------------------------------------------------------------
  // التجميد
  // ---------------------------------------------------------------------------

  /// تجميد الاشتراك [days] يوماً من [start]، وتمديد نهايته بنفس المدة
  Future<Freeze> freeze(Subscription s, {required DateTime start, required int days, String? reason}) async {
    start = dateOnly(start);
    if (days <= 0) throw GymException(tr('عدد أيام التجميد غير صحيح'));
    if (s.cancelled) throw GymException(tr('الاشتراك ملغي'));
    if (start.isBefore(d.today)) throw GymException(tr('لا يمكن التجميد بتاريخ سابق'));
    if (start.isAfter(s.end)) throw GymException(tr('تاريخ التجميد بعد نهاية الاشتراك'));
    final end = addDays(start, days - 1);
    for (final f in s.freezes) {
      if (!(end.isBefore(f.start) || start.isAfter(f.end))) throw GymException(tr('يتداخل مع تجميد آخر'));
    }
    final overLimit = days > s.freezeDaysLeft || s.freezeTimesLeft <= 0;
    if (overLimit && !d.can(Perm.override)) {
      throw GymException(tr('تجاوز المسموح: متبقي {d} يوم و{t} مرة. يحتاج موافقة المدير',
          {'d': s.freezeDaysLeft, 't': s.freezeTimesLeft}));
    }
    final f = Freeze(id: newId(), start: start, end: end, reason: reason, createdAt: d.now());
    s.freezes.add(f);
    s.end = addDays(s.end, days);
    await d.putAll([
      s,
      d.auditEntry('freeze', '${d.members[s.memberId]?.name}: ${dayKey(start)} +$days${overLimit ? ' (override)' : ''}'),
    ]);
    return f;
  }

  /// إنهاء التجميد مبكراً: يعود العضو اليوم وتُرجع الأيام غير المستخدمة
  Future<void> unfreeze(Subscription s, [DateTime? day]) async {
    day = dateOnly(day ?? d.today);
    final f = s.upcomingFreeze(day);
    if (f == null) throw GymException(tr('لا يوجد تجميد حالي'));
    if (!f.start.isBefore(day)) {
      // لم يبدأ بعد: يُلغى كاملاً
      s.freezes.remove(f);
      s.end = addDays(s.end, -f.days);
    } else {
      final used = daysBetween(f.start, day);
      final returned = f.days - used;
      f.end = addDays(day, -1);
      s.end = addDays(s.end, -returned);
    }
    await d.putAll([s, d.auditEntry('unfreeze', '${d.members[s.memberId]?.name}: ${dayKey(day)}')]);
  }

  // ---------------------------------------------------------------------------
  // الإلغاء والتعديل
  // ---------------------------------------------------------------------------

  /// إلغاء اشتراك مع استرداد اختياري. الفاتورة تُخفَّض بحيث لا يبقى على العضو شيء.
  Future<void> cancel(Subscription s, {required String reason, double refund = 0, PayMethod method = PayMethod.cash}) async {
    if (!d.can(Perm.refund)) throw GymException(tr('ليست لديك صلاحية الإلغاء والاسترداد'));
    final inv = d.invoices[s.invoiceId];
    if (inv != null && refund > inv.paid + 0.001) throw GymException(tr('الاسترداد أكبر من المدفوع'));
    s.cancelled = true;
    s.cancelledAt = d.now();
    s.cancelReason = reason;
    final toSave = <Entity>[s];
    if (inv != null) {
      if (refund > 0) {
        final p = newPayment(inv, PayInput(-refund, method), note: tr('استرداد: {r}', {'r': reason}));
        inv.paid = roundMoney(inv.paid - refund);
        toSave.add(p);
      }
      // تخفيض الفاتورة للمبلغ المحتفظ به فعلاً
      final credit = roundMoney(inv.total - inv.paid);
      if (credit > 0) {
        inv.items.add(InvoiceItem(
            kind: ItemKind.other, refId: s.id, description: tr('إلغاء اشتراك: {r}', {'r': reason}), unitPrice: -credit));
        if (!inv.taxInclusive && inv.taxRate > 0) {
          // عند الضريبة المضافة: البند السالب يُحسب قبل الضريبة
          inv.items.last.unitPrice = -roundMoney(credit / (1 + inv.taxRate));
        }
      }
      inv.installments.clear();
      toSave.add(inv);
    }
    toSave.add(d.auditEntry('cancel', '${d.members[s.memberId]?.name}: ${s.planName} — $reason — ${fmtMoney(refund)}'));
    await d.putAll(toSave);
  }

  /// تعديل تاريخ نهاية الاشتراك يدوياً (تعويض، خطأ إدخال)
  Future<void> adjustEnd(Subscription s, DateTime newEnd, String reason) async {
    if (!d.can(Perm.override)) throw GymException(tr('يحتاج صلاحية المدير'));
    final old = s.end;
    s.end = dateOnly(newEnd);
    await d.putAll([s, d.auditEntry('adjust', '${d.members[s.memberId]?.name}: ${dayKey(old)} – ${dayKey(s.end)} — $reason')]);
  }

  Future<void> adjustVisits(Subscription s, int used, String reason) async {
    if (!d.can(Perm.override)) throw GymException(tr('يحتاج صلاحية المدير'));
    final old = s.visitsUsed;
    s.visitsUsed = used < 0 ? 0 : used;
    await d.putAll([s, d.auditEntry('adjust', '${d.members[s.memberId]?.name}: $old – $used — $reason')]);
  }

  /// استيراد عضو باشتراك قائم من دفتر أو برنامج قديم (بدون فاتورة)
  Subscription importedSub(Member m, Plan plan, DateTime start, DateTime end, {int? visitsLeft}) => Subscription(
        id: newId(),
        memberId: m.id,
        planId: plan.id,
        planName: plan.name,
        kind: plan.kind,
        start: dateOnly(start),
        end: dateOnly(end),
        visitsTotal: visitsLeft ?? plan.visits,
        freezeDaysAllowed: plan.freezeDays,
        freezeTimesAllowed: plan.freezeTimes,
        imported: true,
        createdAt: d.now(),
      );
}
