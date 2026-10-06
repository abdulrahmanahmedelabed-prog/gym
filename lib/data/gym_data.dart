import 'dart:convert';
import 'dart:math' as math;

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
import '../services/membership.dart' show GymException;

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

/// سجل قادم من السحابة: data = null يعني أنه حُذف
class RemoteRecord {
  final String coll;
  final String id;
  final Map<String, Object?>? data;
  final int ts;
  final String dev;
  const RemoteRecord(this.coll, this.id, this.data, this.ts, this.dev);
  String get key => '$coll/$id';
}

/// إعدادات خاصة بكل جهاز ولا تُزامن (المظهر، الإرسال من شريحة هذا الجوال، مواعيد المهام المحلية)
const localSettingKeys = {'themeMode', 'smsMode', 'lastReminderRun', 'lastPrune'};

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
  final closes = Coll<CashClose>('cash_closes', CashClose.fromMap);
  final moves = Coll<MoneyMove>('money_moves', MoneyMove.fromMap);
  final locks = Coll<PeriodLock>('period_locks', PeriodLock.fromMap);

  late final Map<Type, Coll> _tables = {
    Member: members, Plan: plans, Subscription: subs, Invoice: invoices, Payment: payments,
    Checkin: checkins, Message: messages, Measurement: measurements, AuditEntry: audit, Staff: staff,
    GymClass: classes, Booking: bookings, Lead: leads, Product: products, Expense: expenses, Coupon: coupons,
    Offer: offers, CashClose: closes, MoneyMove: moves, PeriodLock: locks,
  };

  List<Coll> get tables => _tables.values.toList();

  static final _meta = StoreRef<String, Object?>('meta');

  // ---------------------------------------------------------------------------
  // المزامنة: كل تعديل محلي يُسجَّل في «صندوق الإرسال» ضمن نفس المعاملة،
  // فلا يضيع تعديل حتى لو انقطع النت أو أُغلق التطبيق. التطبيق يعمل كاملاً بدون نت.
  // ---------------------------------------------------------------------------

  static final outbox = StoreRef<String, Map<String, Object?>>('sync_outbox');

  /// معرّف هذا الجهاز عند تفعيل المزامنة (null = المزامنة غير مفعلة، لا يُسجَّل شيء)
  String? syncDevice;

  /// عند تعدد الأجهزة: كل جهاز يأخذ أرقاماً تنتهي برقمه (1..9، 0) فلا تتكرر أرقام الفواتير والعضوية
  int syncSlot = 1;
  bool syncSlotted = false;

  /// ساعة منطقية: أكبر من كل ما رآه الجهاز، فتعديلك بعد رؤية تعديل غيرك يغلبه حتى لو كانت ساعة جوالك متأخرة
  int _hlc = 0;
  int get hlc => _hlc;

  void observeStamp(int ts) {
    if (ts > _hlc) _hlc = ts;
  }

  int nextStamp() {
    _hlc = math.max(clock().millisecondsSinceEpoch, _hlc + 1);
    return _hlc;
  }

  /// يُستدعى بعد كل تعديل محلي (لبدء مزامنة قريبة)
  VoidCallback? onLocalChange;

  final Set<String> _dirtyCounters = {};
  Map<String, String> _settingsSnap = {};

  Map<String, String> _snapSettings() => {for (final e in settings.data.entries) e.key: jsonEncode(e.value)};

  Map<String, Coll> get _byName => {for (final t in _tables.values) t.name: t};

  Future<void> _enqueue(DatabaseClient txn, Iterable<String> keys) async {
    for (final k in keys) {
      await outbox.record(k).put(txn, {'ts': nextStamp()});
    }
  }

  List<String> _settingsChangedKeys() {
    final now = _snapSettings();
    final keys = <String>[
      for (final k in {...now.keys, ..._settingsSnap.keys})
        if (!localSettingKeys.contains(k) && now[k] != _settingsSnap[k]) 'settings/$k',
    ];
    _settingsSnap = now;
    return keys;
  }

  List<String> _counterKeys() => [for (final n in _dirtyCounters) 'counters/$n@$syncDevice'];

  /// عدد التعديلات التي لم تُرفع بعد
  Future<int> pendingCount() => outbox.count(db);

  /// نسخة السجل الحالية للرفع (null = محذوف)
  Map<String, Object?>? snapshotOf(String coll, String id) {
    if (coll == 'settings') {
      return settings.data.containsKey(id) && settings.data[id] != null ? {'v': settings.data[id]} : null;
    }
    if (coll == 'counters') {
      final name = id.split('@').first;
      final v = _counters[name];
      return v == null ? null : {'v': v};
    }
    return _byName[coll]?.items[id]?.toMap();
  }

  /// تسجيل كل البيانات للرفع (أول تفعيل للسحابة، أو بعد استعادة نسخة احتياطية)
  Future<void> enqueueAll() async {
    if (syncDevice == null) return;
    await db.transaction((txn) async {
      for (final t in _tables.values) {
        await _enqueue(txn, t.items.keys.map((id) => '${t.name}/$id'));
      }
      await _enqueue(txn, [
        for (final k in settings.data.keys)
          if (!localSettingKeys.contains(k)) 'settings/$k'
      ]);
      await _enqueue(txn, [
        for (final k in _counters.keys)
          if (!k.contains('@')) 'counters/$k@$syncDevice'
      ]);
    });
    _settingsSnap = _snapSettings();
    onLocalChange?.call();
  }

  /// تطبيق ما وصل من السحابة. التعديل الأحدث يفوز (لكل سجل)، والتعديل المحلي الذي لم يُرفع
  /// ويكون أحدث لا يُستبدل. ثم تُعاد الحسابات المشتقة (المدفوع في الفاتورة، الحصص المستخدمة).
  Future<int> applyRemote(List<RemoteRecord> recs) async {
    if (recs.isEmpty) return 0;
    final byName = _byName;
    final pending = await outbox.records(recs.map((r) => r.key)).get(db);
    final touchedInv = <String>{};
    final touchedSubs = <String>{};
    var applied = 0;
    var settingsChanged = false;
    var countersChanged = false;
    await db.transaction((txn) async {
      for (var i = 0; i < recs.length; i++) {
        final r = recs[i];
        observeStamp(r.ts);
        final p = pending[i];
        if (p != null) {
          if (asInt(p['ts']) >= r.ts) continue; // تعديلنا أحدث وسيُرفع
          await outbox.record(r.key).delete(txn);
        }
        final data = r.data;
        if (r.coll == 'settings') {
          if (localSettingKeys.contains(r.id)) continue;
          if (data == null || data['v'] == null) {
            settings.data.remove(r.id);
          } else {
            settings.data[r.id] = data['v'];
          }
          settingsChanged = true;
        } else if (r.coll == 'counters') {
          if (!r.id.contains('@') || r.id.endsWith('@$syncDevice')) continue;
          _counters[r.id] = asInt(data?['v']);
          countersChanged = true;
        } else {
          final t = byName[r.coll];
          if (t == null) continue;
          final old = t.items[r.id];
          if (data == null) {
            await t.store.record(r.id).delete(txn);
            t.items.remove(r.id);
          } else {
            final e = t.fromMap(data);
            await t.store.record(e.id).put(txn, e.toMap());
            t.items[e.id] = e;
          }
          for (final e in [old, t.items[r.id]]) {
            switch (e) {
              case Payment pay:
                touchedInv.add(pay.invoiceId);
              case Invoice inv:
                touchedInv.add(inv.id);
              case Checkin c when c.subscriptionId != null:
                touchedSubs.add(c.subscriptionId!);
              case Subscription s:
                touchedSubs.add(s.id);
            }
          }
        }
        applied++;
      }
      if (settingsChanged) {
        await _meta.record('settings').put(txn, settings.toMap());
        _settingsSnap = _snapSettings();
      }
      if (countersChanged) await _meta.record('counters').put(txn, _counters);
    });
    _idx.clear();
    await _recomputeDerived(touchedInv, touchedSubs);
    if (settingsChanged) applySettings();
    _changed();
    return applied;
  }

  /// عدد مرات الدخول المسموحة المرتبطة باشتراك
  int countedVisits(String subId) =>
      (_group<Checkin>('chkBySub', checkins.all, (c) => c.subscriptionId)[subId] ?? const <Checkin>[])
          .where((c) => c.allowed)
          .length;

  /// الحقول المحسوبة تُعاد من أصلها بعد دمج بيانات عدة أجهزة (بدون رفع: كل جهاز يحسبها بنفسه)
  Future<void> _recomputeDerived(Set<String> invIds, Set<String> subIds) async {
    final fixes = <Entity>[];
    for (final id in invIds) {
      final inv = invoices[id];
      if (inv == null) continue;
      final sum = roundMoney(paymentsOf(id).fold(0.0, (s, p) => s + p.amount));
      if ((sum - inv.paid).abs() > 0.001) {
        inv.paid = sum;
        fixes.add(inv);
      }
    }
    for (final id in subIds) {
      final s = subs[id];
      final total = s?.visitsTotal;
      if (s == null || total == null) continue;
      // اشتراك انتهى منذ مدة: قد تكون سجلات دخوله القديمة حُذفت للتخفيف، فلا يُعاد حسابه
      if (s.end.isBefore(addDays(today, -60))) continue;
      final n = countedVisits(id);
      final used = s.visitsAdjust == null ? math.max(s.visitsUsed, math.min(n, total)) : (n + s.visitsAdjust!).clamp(0, total);
      if (used != s.visitsUsed) {
        s.visitsUsed = used;
        fixes.add(s);
      }
    }
    if (fixes.isEmpty) return;
    await db.transaction((txn) async {
      for (final e in fixes) {
        await _tables[e.runtimeType]!.store.record(e.id).put(txn, e.toMap());
      }
    });
  }

  /// مسح البيانات المحلية قبل الانضمام لنادٍ على السحابة (بدون تسجيل حذف للرفع)
  Future<void> clearForJoin() async {
    await db.transaction((txn) async {
      for (final t in _tables.values) {
        await t.store.delete(txn);
      }
      await _meta.delete(txn);
      await outbox.delete(txn);
    });
    await reload();
  }

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
    _settingsSnap = _snapSettings();
    await _migrateVisits();
    applySettings();
    _changed();
  }

  /// بيانات من نسخة سابقة: حساب تعديل الحصص مرة واحدة ليصبح المستخدم قابلاً لإعادة الحساب
  Future<void> _migrateVisits() async {
    final old = subs.all.where((s) => s.visitsTotal != null && s.visitsAdjust == null).toList();
    if (old.isEmpty) return;
    _idx.clear();
    await db.transaction((txn) async {
      for (final s in old) {
        s.visitsAdjust = s.visitsUsed - countedVisits(s.id);
        await subs.store.record(s.id).put(txn, s.toMap());
      }
    });
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
    final sync = syncDevice != null;
    await db.transaction((txn) async {
      for (final e in items) {
        final t = _tables[e.runtimeType]!;
        await t.store.record(e.id).put(txn, e.toMap());
      }
      if (_countersDirty) await _meta.record('counters').put(txn, _counters);
      if (withSettings) await _meta.record('settings').put(txn, settings.toMap());
      if (sync) {
        await _enqueue(txn, items.map((e) => '${_tables[e.runtimeType]!.name}/${e.id}'));
        await _enqueue(txn, _counterKeys());
        if (withSettings) await _enqueue(txn, _settingsChangedKeys());
      }
    });
    _countersDirty = false;
    _dirtyCounters.clear();
    for (final e in items) {
      _tables[e.runtimeType]!.items[e.id] = e;
    }
    _changed();
    if (sync) onLocalChange?.call();
  }

  Future<void> remove(Entity e) async {
    final t = _tables[e.runtimeType]!;
    await _deleteIds(t, [e.id]);
  }

  Future<void> removeWhere<T extends Entity>(bool Function(T) test) async {
    final t = table<T>();
    final ids = t.items.values.where(test).map((e) => e.id).toList();
    if (ids.isEmpty) return;
    await _deleteIds(t, ids);
  }

  Future<void> _deleteIds(Coll t, List<String> ids) async {
    final sync = syncDevice != null;
    await db.transaction((txn) async {
      await t.store.records(ids).delete(txn);
      if (sync) await _enqueue(txn, ids.map((id) => '${t.name}/$id'));
    });
    for (final id in ids) {
      t.items.remove(id);
    }
    _changed();
    if (sync) onLocalChange?.call();
  }

  Future<void> saveSettings() async {
    final sync = syncDevice != null;
    await db.transaction((txn) async {
      await _meta.record('settings').put(txn, settings.toMap());
      if (sync) await _enqueue(txn, _settingsChangedKeys());
    });
    if (!sync) _settingsSnap = _snapSettings();
    applySettings();
    _changed();
    if (sync) onLocalChange?.call();
  }

  /// ترقيم تسلسلي لا يتكرر (الفواتير، الإيصالات، أرقام العضوية). يُحفظ مع أول putAll بعده.
  int nextCounter(String name, {int start = 1}) {
    var base = _counters[name] ?? (start - 1);
    // أعلى رقم استخدمه أي جهاز آخر في النادي
    for (final e in _counters.entries) {
      if (e.key.startsWith('$name@') && e.value > base) base = e.value;
    }
    var v = base + 1;
    if (syncSlotted) {
      while (v % 10 != syncSlot % 10) {
        v++;
      }
    }
    _counters[name] = v;
    _countersDirty = true;
    _dirtyCounters.add(name);
    return v;
  }

  String nextNumber(String name, String prefix) => '$prefix-${nextCounter(name).toString().padLeft(6, '0')}';

  int peekCounter(String name) => _counters[name] ?? 0;

  /// عدادات هذا الجهاز فقط (بدون نسخ الأجهزة الأخرى)
  Map<String, int> get localCounters => {for (final e in _counters.entries) if (!e.key.contains('@')) e.key: e.value};

  // ---------------------------------------------------------------------------
  // الصلاحيات وسجل العمليات
  // ---------------------------------------------------------------------------

  bool can(Perm p) => user == null || user!.can(p);

  String? get userName => user?.name;

  AuditEntry auditEntry(String action, String details) =>
      AuditEntry(id: newId(), time: now(), user: userName, action: action, details: details);

  Future<void> log(String action, String details) => put(auditEntry(action, details));

  /// آخر يوم في الفترات المقفلة محاسبياً (null = لا إقفال)
  DateTime? get lockedUntil {
    DateTime? out;
    for (final l in locks.all) {
      if (out == null || l.until.isAfter(out)) out = l.until;
    }
    return out;
  }

  /// يمنع إضافة أو حذف عملية بتاريخ داخل فترة مقفلة
  void requireOpen(DateTime date) {
    final l = lockedUntil;
    if (l != null && !dateOnly(date).isAfter(l)) {
      throw GymException(tr('الفترة حتى {d} مقفلة محاسبياً. سجّل العملية بتاريخ بعدها', {'d': dayKey(l)}));
    }
  }

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
      await outbox.delete(txn);
    });
    await reload();
    // مع المزامنة: النسخة المستعادة تُرفع لتصبح هي الأحدث على كل الأجهزة
    await enqueueAll();
  }

  /// يُستدعى قبل مسح كل البيانات (لإيقاف المزامنة على هذا الجهاز فلا يُمسح النادي من السحابة)
  Future<void> Function()? beforeWipe;

  /// مسح كل البيانات (بعد تأكيد المالك). لا يمس بيانات النادي على السحابة.
  Future<void> wipe() async {
    await beforeWipe?.call();
    await db.transaction((txn) async {
      for (final t in _tables.values) {
        await t.store.delete(txn);
      }
      await _meta.delete(txn);
      await outbox.delete(txn);
    });
    await reload();
  }
}
