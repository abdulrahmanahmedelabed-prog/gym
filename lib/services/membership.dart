import '../core/dates.dart';
import '../core/i18n.dart';
import '../core/phone.dart';
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
  final String? account; // المحفظة/الحساب المستلم
  final bool verified;
  const PayInput(this.amount, this.method, [this.reference, this.account, this.verified = true]);
}

/// طلب بيع/تجديد اشتراك
class SaleRequest {
  final String memberId;
  final String planId;
  final DateTime? start;
  final double discount; // خصم يدوي بالمبلغ
  final double discountPct; // خصم يدوي بالنسبة المئوية من سعر الباقة
  final bool useOffer; // تطبيق أفضل عرض ساري تلقائياً
  final String? offerId; // عرض محدد بدل الأفضل
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
    this.discountPct = 0,
    this.useOffer = true,
    this.offerId,
    this.couponCode,
    this.registrationFee = false,
    this.trainerId,
    this.payments = const [],
    this.installments = const [],
    this.notes,
    this.extraItems = const [],
  });
}

/// [total] هو ما سيُكتب في الفاتورة بالضبط (مع الضريبة المضافة إن كانت الأسعار غير شاملة لها)،
/// و[tax] قيمة الضريبة المضافة فوق السعر (صفر إن كانت شاملة أو معطلة)
typedef SaleQuote = ({double price, double fee, double couponDiscount, double offerDiscount, double manualDiscount, Offer? offer, double tax, double total});

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
    m.phone = normalizeDigits(m.phone).trim();
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
    m.phone = normalizeDigits(m.phone).trim();
    final dup = findByPhone(m.phone);
    if (dup != null && dup.id != m.id) {
      throw GymException(tr('رقم الجوال مسجل للعضو {name} (رقم {code})', {'name': dup.name, 'code': dup.code}));
    }
    await d.put(m);
  }

  Member? findByPhone(String phone) {
    final digits = digitsOnly(phone);
    if (digits.length < 7) return null;
    final tail = digits.substring(digits.length - 9 < 0 ? 0 : digits.length - 9);
    for (final m in d.members.all) {
      final md = digitsOnly(m.phone);
      if (md.length >= 7 && md.endsWith(tail)) return m;
    }
    return null;
  }

  /// بحث بالاسم أو الجوال أو رقم العضوية أو رمز البطاقة
  List<Member> search(String q, {bool includeArchived = false}) {
    q = normalizeDigits(q).trim().toLowerCase();
    final list = d.members.all.where((m) => includeArchived || !m.archived);
    if (q.isEmpty) return list.toList();
    final code = int.tryParse(q);
    return list.where((m) {
      if (code != null && m.code == code) return true;
      if (m.name.toLowerCase().contains(q)) return true;
      if (q.length >= 3 && digitsOnly(m.phone).contains(q)) return true;
      return m.cardToken.toLowerCase() == q;
    }).toList();
  }

  /// قراءة محتوى رمز QR أو باركود بطاقة العضو
  Member? resolveScan(String raw) {
    var s = normalizeDigits(raw).trim();
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
  /// ما سيدفعه العميل فعلاً لمبلغ قبل الضريبة (بنفس حساب الفاتورة): تُضاف الضريبة فقط إن كانت الأسعار غير شاملة لها
  double totalWithTax(double taxable) {
    final st = d.settings;
    if (!st.taxEnabled || st.taxInclusive || st.taxRate <= 0) return roundMoney(taxable);
    return roundMoney(taxable + roundMoney(taxable * (st.taxRate / 100)));
  }

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
        account: p.account,
        verified: p.verified || p.amount < 0 || p.method == PayMethod.cash || p.method == PayMethod.card,
        verifiedAt: p.verified ? d.now() : null,
      );

  /// العروض السارية على باقة لهذا العضو اليوم
  List<Offer> offersFor(Plan plan, String memberId, [DateTime? day]) {
    if (!d.has(Feature.offers)) return const [];
    final isNew = isNewMember(memberId);
    return d.offers.all.where((o) => o.validOn(day ?? d.today, plan.id, newMember: isNew)).toList();
  }

  /// أفضل عرض للعضو: الأكبر خصماً، ثم الأكثر أياماً مجانية
  Offer? bestOffer(Plan plan, String memberId) {
    Offer? best;
    for (final o in offersFor(plan, memberId)) {
      if (best == null) {
        best = o;
        continue;
      }
      final a = o.discountFor(plan.price), b = best.discountFor(plan.price);
      if (a > b + 0.001 || ((a - b).abs() <= 0.001 && o.bonusDays > best.bonusDays)) best = o;
    }
    return best;
  }

  Offer? offerOf(SaleRequest r, Plan plan) {
    if (!r.useOffer) return null;
    if (r.offerId != null) {
      final o = d.offers[r.offerId];
      if (o != null && offersFor(plan, r.memberId).contains(o)) return o;
      return null;
    }
    return bestOffer(plan, r.memberId);
  }

  /// حساب سعر البيع قبل التنفيذ (لعرضه في شاشة البيع)
  SaleQuote quote(SaleRequest r) {
    final plan = d.plans[r.planId];
    if (plan == null) throw GymException(tr('الباقة غير موجودة'));
    if (r.discount < 0 || r.discountPct < 0) throw GymException(tr('الخصم لا يكون سالباً'));
    if (r.discountPct > 100) throw GymException(tr('نسبة الخصم لا تزيد عن 100%'));
    final fee = r.registrationFee ? plan.registrationFee : 0.0;
    final offer = offerOf(r, plan);
    final offerDiscount = offer == null ? 0.0 : roundMoney(offer.discountFor(plan.price));
    final manual = roundMoney(r.discount + plan.price * r.discountPct / 100);
    var couponDiscount = 0.0;
    if (r.couponCode != null && r.couponCode!.trim().isNotEmpty) {
      final c = findCoupon(r.couponCode!);
      if (c == null || !c.usableOn(d.today, plan.id)) throw GymException(tr('كوبون الخصم غير صالح'));
      couponDiscount = roundMoney(c.discountFor(plan.price));
    }
    final extras = r.extraItems.fold(0.0, (s, i) => s + i.total);
    final gross = roundMoney(plan.price + fee + extras);
    final discounts = roundMoney(couponDiscount + offerDiscount + manual);
    final taxable = roundMoney(gross - (discounts > gross ? gross : discounts));
    // نفس حساب الفاتورة: الضريبة المضافة تُضاف فوق السعر، والشاملة داخله
    final total = totalWithTax(taxable);
    return (
      price: plan.price,
      fee: fee,
      couponDiscount: couponDiscount,
      offerDiscount: offerDiscount,
      manualDiscount: manual,
      offer: offer,
      tax: roundMoney(total - taxable),
      total: total,
    );
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
    final totalDiscount = q.manualDiscount + q.couponDiscount + q.offerDiscount;
    if (q.manualDiscount > 0 && !d.can(Perm.discount)) {
      final pct = (plan.price + q.fee) <= 0 ? 0 : q.manualDiscount / (plan.price + q.fee) * 100;
      if (pct > d.settings.maxDiscountPct + 0.001) {
        throw GymException(tr('الخصم أعلى من المسموح ({p}%). يحتاج موافقة المدير', {'p': fmtNum(d.settings.maxDiscountPct)}));
      }
    }
    if (r.payments.any((p) => p.amount < 0)) throw GymException(tr('المبلغ المدفوع لا يكون سالباً'));
    if (r.installments.any((i) => i.amount <= 0)) throw GymException(tr('كل قسط يجب أن يكون أكبر من صفر'));
    final paidNow = r.payments.fold(0.0, (s, p) => s + p.amount);
    if (paidNow - q.total > 0.001) throw GymException(tr('المبلغ المدفوع أكبر من الإجمالي'));
    final scheduled = r.installments.fold(0.0, (s, i) => s + i.amount);
    if (r.installments.isNotEmpty && (paidNow + scheduled - q.total).abs() > 0.01) {
      throw GymException(tr('مجموع الأقساط والمدفوع الآن يجب أن يساوي الإجمالي ({t})', {'t': fmtMoney(q.total)}));
    }

    final start = dateOnly(r.start ?? (plan.kind == PlanKind.pt ? d.today : suggestedStart(member.id)));
    final bonus = q.offer?.bonusDays ?? 0;
    final end = addDays(periodEnd(start, plan.durationValue, plan.durationUnit), bonus);
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
      discount: roundMoney(totalDiscount > plan.price + q.fee ? plan.price + q.fee : totalDiscount),
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
        description: '${plan.name} (${dayKey(start)} – ${dayKey(end)})${q.offer == null ? '' : ' — ${q.offer!.name}'}',
        unitPrice: plan.price,
      ),
      if (q.fee > 0) InvoiceItem(kind: ItemKind.registration, description: tr('رسوم التسجيل'), unitPrice: q.fee),
      ...r.extraItems,
    ];
    // مجموع الخصومات لا يتجاوز قيمة الفاتورة (فلا يصبح الإجمالي سالباً)
    final gross = items.fold(0.0, (s, i) => s + i.total);
    final inv = newInvoice(memberId: member.id, items: items, discount: roundMoney(totalDiscount > gross ? gross : totalDiscount))
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
    if (q.manualDiscount > 0) {
      toSave.add(d.auditEntry('discount', '${inv.number}: ${fmtMoney(q.manualDiscount)} (${member.name})'));
    }
    await d.putAll(toSave);
    return SaleResult(sub, inv, pays);
  }

  // ---------------------------------------------------------------------------
  // التجديد شبه التلقائي: فاتورة تجديد تتحول لاشتراك عند اكتمال دفعها
  // ---------------------------------------------------------------------------

  Invoice? openRenewalInvoice(String memberId) {
    for (final inv in d.invoicesOf(memberId)) {
      if (inv.pendingPlanId != null && !inv.voided && inv.balance > 0) return inv;
    }
    return null;
  }

  /// فاتورة تجديد بسعر الباقة (مع العرض الساري إن وجد)؛ لا تُنشأ مرتين
  Future<Invoice> createRenewalInvoice(Member m, Plan plan) async {
    d.require(Feature.autoRenew);
    final existing = openRenewalInvoice(m.id);
    if (existing != null) return existing;
    _checkMemberLimit(m.id);
    final q = quote(SaleRequest(memberId: m.id, planId: plan.id));
    final start = suggestedStart(m.id);
    final end = periodEnd(start, plan.durationValue, plan.durationUnit);
    final inv = newInvoice(memberId: m.id, discount: roundMoney(q.offerDiscount), items: [
      InvoiceItem(
        kind: plan.kind == PlanKind.pt ? ItemKind.pt : ItemKind.subscription,
        description: '${plan.name} — ${tr('تجديد')} (${dayKey(start)} – ${dayKey(end)})',
        unitPrice: plan.price,
      ),
    ])
      ..pendingPlanId = plan.id
      ..notes = tr('فاتورة تجديد: يتجدد الاشتراك تلقائياً عند اكتمال الدفع');
    await d.putAll([inv]);
    return inv;
  }

  /// عند اكتمال دفع فاتورة تجديد: إنشاء الاشتراك وربطه بها
  Future<Subscription?> completePendingSale(Invoice inv) async {
    final planId = inv.pendingPlanId;
    if (planId == null || inv.voided || inv.balance > 0.001 || inv.memberId == null) return null;
    final plan = d.plans[planId];
    final member = d.members[inv.memberId];
    if (plan == null || member == null) return null;
    final start = suggestedStart(member.id);
    final item = inv.items.first;
    final sub = Subscription(
      id: newId(),
      memberId: member.id,
      planId: plan.id,
      planName: plan.name,
      kind: plan.kind,
      start: start,
      end: addDays(periodEnd(start, plan.durationValue, plan.durationUnit), bonusDaysFor(plan, member.id)),
      visitsTotal: plan.visits,
      price: plan.price,
      discount: inv.discount,
      freezeDaysAllowed: plan.freezeDays,
      freezeTimesAllowed: plan.freezeTimes,
      invoiceId: inv.id,
      createdAt: d.now(),
      createdBy: d.userName,
    );
    item.refId = sub.id;
    inv.pendingPlanId = null;
    await d.putAll([sub, inv, d.auditEntry('auto_renew', '${member.name}: ${plan.name} ${dayKey(start)}')]);
    return sub;
  }

  /// أيام إضافية مجانية من العرض الساري
  int bonusDaysFor(Plan plan, String memberId) => bestOffer(plan, memberId)?.bonusDays ?? 0;

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
    if (dateOnly(newEnd).isBefore(s.start)) throw GymException(tr('تاريخ النهاية قبل بداية الاشتراك ({d})', {'d': dayKey(s.start)}));
    final old = s.end;
    s.end = dateOnly(newEnd);
    await d.putAll([s, d.auditEntry('adjust', '${d.members[s.memberId]?.name}: ${dayKey(old)} – ${dayKey(s.end)} — $reason')]);
  }

  Future<void> adjustVisits(Subscription s, int used, String reason) async {
    if (!d.can(Perm.override)) throw GymException(tr('يحتاج صلاحية المدير'));
    if (used < 0 || (s.visitsTotal != null && used > s.visitsTotal!)) {
      throw GymException(tr('الحصص المستخدمة بين 0 و{t}', {'t': s.visitsTotal ?? 0}));
    }
    final old = s.visitsUsed;
    s.visitsUsed = used;
    s.visitsAdjust = s.visitsUsed - d.countedVisits(s.id);
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
