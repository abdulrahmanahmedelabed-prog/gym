import 'package:flutter/foundation.dart';
import 'package:sembast/sembast.dart';

import '../core/dates.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../core/i18n.dart';
import '../models/activity.dart';
import '../models/base.dart';
import '../models/billing.dart';
import '../models/business.dart';
import '../models/member.dart';
import '../models/plan.dart';
import '../models/settings.dart';
import '../models/subscription.dart';
import '../services/license.dart';

/// جدول: السجلات في الذاكرة (للسرعة) ونسخة دائمة في قاعدة البيانات.
class Coll<T extends Entity> {
  final String name;
  final T Function(Map<String, Object?>) fromMap;
  final StoreRef<String, Map<String, Object?>> store;
  final Map<String, T> items = {};

  Coll(this.name, this.fromMap) : store = stringMapStoreFactory.store(name);

  Iterable<T> get all => items.values;
  T? operator [](String? id) => id == null ? null : items[id];
}

/// كل بيانات النادي. أي تعديل يمر من هنا: يُحدّث الذاكرة ثم يحفظ في قاعدة البيانات ثم يُبلغ الشاشات.
class GymData extends ChangeNotifier {
  final Database db;
  DateTime Function() clock;

  final members = Coll<Member>('members', Member.fromMap);
  final plans = Coll<Plan>('plans', Plan.fromMap);
  final subs = Coll<Subscription>('subscriptions', Subscription.fromMap);
  final invoices = Coll<Invoice>('invoices', Invoice.fromMap);
  final payments = Coll<Payment>('payments', Payment.fromMap);
  final checkins = Coll<Checkin>('checkins', Checkin.fromMap);
  final messages = Coll<Message>('messages', Message.fromMap);
  final measurements = Coll<Measurement>('measurements', Measurement.fromMap);
  final audit = Coll<AuditEntry>('audit', AuditEntry.fromMap);
  final staff = Coll<Staff>('staff', Staff.fromMap);
  final classes = Coll<GymClass>('classes', GymClass.fromMap);
  final bookings = Coll<Booking>('bookings', Booking.fromMap);
  final leads = Coll<Lead>('leads', Lead.fromMap);
  final products = Coll<Product>('products', Product.fromMap);
  final expenses = Coll<Expense>('expenses', Expense.fromMap);
  final coupons = Coll<Coupon>('coupons', Coupon.fromMap);
  final offers = Coll<Offer>('offers', Offer.fromMap);

  late final Map<Type, Coll> _tables = {
    Member: members, Plan: plans, Subscription: subs, Invoice: invoices, Payment: payments,
    Checkin: checkins, Message: messages, Measurement: measurements, AuditEntry: audit, Staff: staff,
    GymClass: classes, Booking: bookings, Lead: leads, Product: products, Expense: expenses, Coupon: coupons,
    Offer: offers,
  };

  List<Coll> get tables => _tables.values.toList();

  static final _meta = StoreRef<String, Object?>('meta');

  GymSettings settings = GymSettings();
  Map<String, int> _counters = {};
  bool _countersDirty = false;

  /// المستخدم الحالي (null = لا توجد حسابات موظفين، أي المالك يعمل وحده)
  Staff? user;

  int _version = 0;

  /// الترخيص (مجاني / Plus / Pro) — خاص بهذا الجهاز ولا ينتقل مع النسخة الاحتياطية
  late final LicenseManager license;

  GymData(this.db, {DateTime Function()? clock}) : clock = clock ?? DateTime.now {
    license = LicenseManager(db, this.clock);
  }

  static Future<GymData> open(Database db, {DateTime Function()? clock}) async {
    final g = GymData(db, clock: clock);
    await g.license.load();
    await g.reload();
    return g;
  }

  bool has(Feature f) => license.has(f);

  void require(Feature f) => license.require(f);

  Future<void> reload() async {
    for (final t in _tables.values) {
      t.items.clear();
      final records = await t.store.find(db);
      for (final r in records) {
        final e = t.fromMap(Map<String, Object?>.from(r.value));
        t.items[e.id] = e;
      }
    }
    final s = await _meta.record('settings').get(db);
    settings = GymSettings(s is Map ? Map<String, Object?>.from(s) : {});
    final c = await _meta.record('counters').get(db);
    _counters = c is Map ? c.map((k, v) => MapEntry(k.toString(), asInt(v))) : {};
    applySettings();
    _changed();
  }

  /// ضبط اللغة والعملة من الإعدادات
  void applySettings() {
    I18n.lang = settings.language;
    Money.configure(code: settings.currencyCode, symbol: settings.currencySymbol);
  }

  DateTime now() => clock();
  DateTime get today => dateOnly(clock());

  int get version => _version;

  void _changed() {
    _version++;
    _idx.clear();
    notifyListeners();
  }

  /// إعادة رسم الشاشات بدون حفظ (بعد تغيير المستخدم مثلاً)
  void touch() => _changed();

  Coll<T> table<T extends Entity>() => _tables[T]! as Coll<T>;

  Future<void> put(Entity e) => putAll([e]);

  /// حفظ عدة سجلات معاً في معاملة واحدة: تنجح كلها أو لا يُحفظ شيء
  Future<void> putAll(Iterable<Entity> list, {bool withSettings = false}) async {
    final items = list.toList();
    await db.transaction((txn) async {
      for (final e in items) {
        final t = _tables[e.runtimeType]!;
        await t.store.record(e.id).put(txn, e.toMap());
      }
      if (_countersDirty) await _meta.record('counters').put(txn, _counters);
      if (withSettings) await _meta.record('settings').put(txn, settings.toMap());
    });
    _countersDirty = false;
    for (final e in items) {
      _tables[e.runtimeType]!.items[e.id] = e;
    }
    _changed();
  }

  Future<void> remove(Entity e) async {
    final t = _tables[e.runtimeType]!;
    await t.store.record(e.id).delete(db);
    t.items.remove(e.id);
    _changed();
  }

  Future<void> removeWhere<T extends Entity>(bool Function(T) test) async {
    final t = table<T>();
    final ids = t.items.values.where(test).map((e) => e.id).toList();
    if (ids.isEmpty) return;
    await t.store.records(ids).delete(db);
    for (final id in ids) {
      t.items.remove(id);
    }
    _changed();
  }

  Future<void> saveSettings() async {
    await _meta.record('settings').put(db, settings.toMap());
    applySettings();
    _changed();
  }

  /// ترقيم تسلسلي لا يتكرر (الفواتير، الإيصالات، أرقام العضوية). يُحفظ مع أول putAll بعده.
  int nextCounter(String name, {int start = 1}) {
    final v = (_counters[name] ?? (start - 1)) + 1;
    _counters[name] = v;
    _countersDirty = true;
    return v;
  }

  String nextNumber(String name, String prefix) => '$prefix-${nextCounter(name).toString().padLeft(6, '0')}';

  int peekCounter(String name) => _counters[name] ?? 0;

  // ---------------------------------------------------------------------------
  // الصلاحيات وسجل العمليات
  // ---------------------------------------------------------------------------

  bool can(Perm p) => user == null || user!.can(p);

  String? get userName => user?.name;

  AuditEntry auditEntry(String action, String details) =>
      AuditEntry(id: newId(), time: now(), user: userName, action: action, details: details);

  Future<void> log(String action, String details) => put(auditEntry(action, details));

  // ---------------------------------------------------------------------------
  // فهارس سريعة (تُبنى عند الحاجة وتُمسح مع أي تعديل)
  // ---------------------------------------------------------------------------

  final Map<String, Object> _idx = {};

  Map<String, List<X>> _group<X>(String key, Iterable<X> items, String? Function(X) by) {
    return _idx.putIfAbsent(key, () {
      final m = <String, List<X>>{};
      for (final i in items) {
        final k = by(i);
        if (k != null) (m[k] ??= []).add(i);
      }
      return m;
    }) as Map<String, List<X>>;
  }

  /// اشتراكات العضو من الأقدم للأحدث
  List<Subscription> subsOf(String memberId) {
    final m = _idx.putIfAbsent('subsSorted', () {
      final g = <String, List<Subscription>>{};
      for (final s in subs.all) {
        (g[s.memberId] ??= []).add(s);
      }
      for (final l in g.values) {
        l.sort((a, b) {
          final c = a.start.compareTo(b.start);
          return c != 0 ? c : a.createdAt.compareTo(b.createdAt);
        });
      }
      return g;
    }) as Map<String, List<Subscription>>;
    return m[memberId] ?? const [];
  }

  List<Invoice> invoicesOf(String memberId) =>
      _group<Invoice>('invByMember', invoices.all, (i) => i.memberId)[memberId] ?? const [];

  List<Payment> paymentsOf(String invoiceId) =>
      _group<Payment>('payByInvoice', payments.all, (p) => p.invoiceId)[invoiceId] ?? const [];

  List<Checkin> checkinsOf(String memberId) =>
      _group<Checkin>('chkByMember', checkins.all, (c) => c.memberId)[memberId] ?? const [];

  List<Measurement> measurementsOf(String memberId) {
    final l = List.of(
        _group<Measurement>('measByMember', measurements.all, (m) => m.memberId)[memberId] ?? const <Measurement>[]);
    l.sort((a, b) => a.date.compareTo(b.date));
    return l;
  }

  List<Message> messagesOf(String memberId) =>
      _group<Message>('msgByMember', messages.all, (m) => m.memberId)[memberId] ?? const [];

  Set<String> get dedupKeys => _idx.putIfAbsent(
      'dedup', () => messages.all.map((m) => m.dedupKey).whereType<String>().toSet()) as Set<String>;

  /// آخر دخول مسموح للعضو
  Checkin? lastVisit(String memberId) {
    final m = _idx.putIfAbsent('lastVisit', () {
      final r = <String, Checkin>{};
      for (final c in checkins.all) {
        if (!c.allowed) continue;
        final prev = r[c.memberId];
        if (prev == null || c.time.isAfter(prev.time)) r[c.memberId] = c;
      }
      return r;
    }) as Map<String, Checkin>;
    return m[memberId];
  }

  Member? memberByToken(String token) {
    final m = _idx.putIfAbsent('byToken', () => {for (final x in members.all) x.cardToken: x}) as Map<String, Member>;
    return m[token];
  }

  Member? memberByCode(int code) {
    final m = _idx.putIfAbsent('byCode', () => {for (final x in members.all) x.code: x}) as Map<int, Member>;
    return m[code];
  }

  /// الرصيد المستحق على العضو (مجموع المتبقي في فواتيره)
  double balanceOf(String memberId) =>
      roundMoney(invoicesOf(memberId).fold(0.0, (s, i) => s + i.balance));

  /// المتأخر فقط: الأقساط التي فات موعدها + الفواتير غير المقسطة
  double overdueOf(String memberId, [DateTime? day]) {
    day ??= today;
    var sum = 0.0;
    for (final inv in invoicesOf(memberId)) {
      if (inv.balance <= 0) continue;
      if (inv.installments.isEmpty) {
        sum += inv.balance;
        continue;
      }
      final scheduled = inv.installments.fold(0.0, (s, i) => s + i.amount);
      final upfrontLeft = (inv.total - scheduled) - inv.paid;
      if (upfrontLeft > 0) sum += upfrontLeft;
      for (final s in inv.installmentStatus()) {
        if (s.left > 0 && !s.inst.due.isAfter(day)) sum += s.left;
      }
    }
    return roundMoney(sum);
  }

  List<Staff> get trainers => staff.all.where((s) => s.isTrainer && s.active).toList();

  List<Plan> get activePlans => plans.all.where((p) => p.active).toList()..sort((a, b) => a.sort.compareTo(b.sort));

  bool get isEmpty => members.items.isEmpty && plans.items.isEmpty;

  /// كل البيانات كـ JSON (للنسخ الاحتياطي)
  Future<Map<String, Object?>> exportAll() async {
    final out = <String, Object?>{
      'app': 'nadi_gym',
      'format': 1,
      'exportedAt': now().toIso8601String(),
      'settings': settings.toMap(),
      'counters': _counters,
    };
    for (final t in _tables.values) {
      out[t.name] = t.items.values.map((e) => e.toMap()).toList();
    }
    return out;
  }

  /// استبدال كل البيانات بنسخة احتياطية
  Future<void> importAll(Map<String, Object?> data) async {
    if (data['app'] != 'nadi_gym') throw FormatException(tr('الملف ليس نسخة احتياطية من هذا التطبيق'));
    await db.transaction((txn) async {
      for (final t in _tables.values) {
        await t.store.delete(txn);
        for (final m in asMapList(data[t.name])) {
          final e = t.fromMap(m);
          await t.store.record(e.id).put(txn, e.toMap());
        }
      }
      await _meta.record('settings').put(txn, Map<String, Object?>.from(data['settings'] as Map? ?? {}));
      await _meta.record('counters').put(txn, Map<String, Object?>.from(data['counters'] as Map? ?? {}));
    });
    await reload();
  }

  /// مسح كل البيانات (بعد تأكيد المالك)
  Future<void> wipe() async {
    await db.transaction((txn) async {
      for (final t in _tables.values) {
        await t.store.delete(txn);
      }
      await _meta.delete(txn);
    });
    await reload();
  }
}
