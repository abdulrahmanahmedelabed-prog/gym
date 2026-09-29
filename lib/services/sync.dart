import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sembast/sembast.dart';

import '../core/i18n.dart';
import '../core/ids.dart';
import '../core/vendor.dart';
import '../data/gym_data.dart';
import '../models/base.dart';
import 'license.dart';
import 'membership.dart';

/// بيانات الدخول لنادٍ على السحابة
class SyncCreds {
  final String gym;
  final String secret;
  final String url;
  final String key;
  const SyncCreds({required this.gym, required this.secret, required this.url, required this.key});
}

class SyncPush {
  final List<({String coll, String id, Map<String, Object?>? data, int ts})> records;
  const SyncPush(this.records);
}

class SyncPullResult {
  final List<RemoteRecord> records;
  final List<int> seqs;
  final int devices;
  const SyncPullResult(this.records, this.seqs, this.devices);
}

/// خطأ من الخادم يمنع المزامنة (كلمة سر خاطئة، تجاوز عدد الأجهزة...) — ليس انقطاع نت
class SyncRejected implements Exception {
  final String code;
  SyncRejected(this.code);
  @override
  String toString() => switch (code) {
        'auth' => tr('رمز الربط غير صحيح أو أُلغي'),
        'device_limit' => tr('تجاوزت عدد الأجهزة المسموح لهذا النادي'),
        _ => tr('رفض الخادم المزامنة: {c}', {'c': code}),
      };
}

/// الخادم: ثلاث عمليات فقط. التنفيذ الافتراضي Supabase، ويمكن استبداله بأي خادم يطبق نفس العمليات.
abstract class SyncBackend {
  /// يسجّل الجهاز (وينشئ النادي إن لم يوجد)، ويعيد رقم الجهاز في النادي وعدد الأجهزة
  Future<({int slot, int devices})> register(SyncCreds c, String device);

  /// يرفع التعديلات؛ الخادم يحتفظ بالأحدث لكل سجل. يعيد عدد الأجهزة.
  Future<int> push(SyncCreds c, String device, SyncPush p);

  /// كل ما تغيّر بعد المؤشر since بالترتيب
  Future<SyncPullResult> pull(SyncCreds c, String device, int since, int limit);
}

/// Supabase / PostgREST: دوال RPC فقط (الجداول نفسها مغلقة أمام التطبيق). انظر server/supabase_sync.sql
class SupabaseSyncBackend implements SyncBackend {
  final http.Client client;
  SupabaseSyncBackend([http.Client? c]) : client = c ?? http.Client();

  Future<Object?> _rpc(SyncCreds c, String fn, Map<String, Object?> body) async {
    final base = c.url.endsWith('/') ? c.url.substring(0, c.url.length - 1) : c.url;
    final r = await client
        .post(
          Uri.parse('$base/rest/v1/rpc/$fn'),
          headers: {
            'apikey': c.key,
            'Authorization': 'Bearer ${c.key}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 40));
    if (r.statusCode >= 200 && r.statusCode < 300) return r.body.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
    final msg = utf8.decode(r.bodyBytes);
    for (final code in ['device_limit', 'auth']) {
      if (msg.contains('nadi_$code')) throw SyncRejected(code);
    }
    if (r.statusCode >= 500 || r.statusCode == 429) throw http.ClientException('HTTP ${r.statusCode}');
    throw SyncRejected('HTTP ${r.statusCode}');
  }

  Map<String, Object?> _auth(SyncCreds c, String device) => {'p_gym': c.gym, 'p_secret': c.secret, 'p_device': device};

  @override
  Future<({int slot, int devices})> register(SyncCreds c, String device) async {
    final r = await _rpc(c, 'nadi_sync_register', _auth(c, device)) as Map;
    return (slot: asInt(r['slot'], 1), devices: asInt(r['devices'], 1));
  }

  @override
  Future<int> push(SyncCreds c, String device, SyncPush p) async {
    final r = await _rpc(c, 'nadi_sync_push', {
      ..._auth(c, device),
      'p_records': [
        for (final x in p.records) {'c': x.coll, 'i': x.id, 'd': x.data, 't': x.ts}
      ],
    }) as Map;
    return asInt(r['devices'], 1);
  }

  @override
  Future<SyncPullResult> pull(SyncCreds c, String device, int since, int limit) async {
    final r = await _rpc(c, 'nadi_sync_pull', {..._auth(c, device), 'p_since': since, 'p_limit': limit}) as Map;
    final recs = <RemoteRecord>[];
    final seqs = <int>[];
    for (final m in asMapList(r['records'])) {
      final d = m['d'];
      recs.add(RemoteRecord(asStr(m['c']), asStr(m['i']), d is Map ? Map<String, Object?>.from(d) : null, asInt(m['t']), asStr(m['v'])));
      seqs.add(asInt(m['s']));
    }
    return SyncPullResult(recs, seqs, asInt(r['devices'], 1));
  }
}

/// خادم في الذاكرة بنفس قواعد الخادم الحقيقي (للاختبارات والتجربة)
class MemorySyncBackend implements SyncBackend {
  final gyms = <String, String>{};
  final devices = <String, Map<String, int>>{};
  final rows = <String, Map<String, ({String coll, String id, Map<String, Object?>? data, int ts, String dev, int seq})>>{};
  int maxDevices = 10;
  int _seq = 0;
  bool online = true;

  void _check(SyncCreds c, String device) {
    if (!online) throw http.ClientException('offline');
    if (gyms[c.gym] != c.secret) throw SyncRejected('auth');
    final d = devices[c.gym]!;
    if (!d.containsKey(device)) {
      if (d.length >= maxDevices) throw SyncRejected('device_limit');
      d[device] = d.values.fold(0, (a, b) => a > b ? a : b) + 1;
    }
  }

  @override
  Future<({int slot, int devices})> register(SyncCreds c, String device) async {
    if (!online) throw http.ClientException('offline');
    gyms.putIfAbsent(c.gym, () => c.secret);
    devices.putIfAbsent(c.gym, () => {});
    rows.putIfAbsent(c.gym, () => {});
    _check(c, device);
    return (slot: devices[c.gym]![device]!, devices: devices[c.gym]!.length);
  }

  @override
  Future<int> push(SyncCreds c, String device, SyncPush p) async {
    _check(c, device);
    final g = rows[c.gym]!;
    for (final r in p.records) {
      final k = '${r.coll}/${r.id}';
      final old = g[k];
      if (old == null || old.ts < r.ts || (old.ts == r.ts && old.dev.compareTo(device) < 0)) {
        g[k] = (coll: r.coll, id: r.id, data: r.data == null ? null : jsonDecode(jsonEncode(r.data)) as Map<String, Object?>, ts: r.ts, dev: device, seq: ++_seq);
      }
    }
    return devices[c.gym]!.length;
  }

  @override
  Future<SyncPullResult> pull(SyncCreds c, String device, int since, int limit) async {
    _check(c, device);
    final l = rows[c.gym]!.values.where((r) => r.seq > since).toList()..sort((a, b) => a.seq.compareTo(b.seq));
    final page = l.take(limit).toList();
    return SyncPullResult(
      [for (final r in page) RemoteRecord(r.coll, r.id, r.data, r.ts, r.dev)],
      [for (final r in page) r.seq],
      devices[c.gym]!.length,
    );
  }
}

enum SyncPhase { off, synced, syncing, pending, offline, error, locked }

/// المزامنة السحابية مع العمل الكامل بدون نت:
/// - كل تعديل يُحفظ محلياً أولاً ويُسجّل في صندوق الإرسال (في نفس المعاملة).
/// - عند توفر النت: رفع ما في الصندوق ثم جلب تعديلات الأجهزة الأخرى، تلقائياً وبصمت.
/// - انقطاع النت لا يوقف أي شيء في التطبيق؛ تُعاد المحاولة لاحقاً.
class SyncService extends ChangeNotifier {
  final GymData d;
  final SyncBackend backend;
  SyncService(this.d, {SyncBackend? backend}) : backend = backend ?? SupabaseSyncBackend();

  static final _store = StoreRef<String, Map<String, Object?>>('sync');
  static const pushBatch = 200;
  static const pullBatch = 500;

  Map<String, Object?>? _cfg;
  SyncPhase phase = SyncPhase.off;
  String? lastError;
  int pending = 0;
  int devices = 0;
  bool _busy = false;
  bool _again = false;
  int _fails = 0;
  DateTime? _nextTry;
  Timer? _timer;
  Timer? _debounce;

  bool get enabled => _cfg != null;
  String get gym => asStr(_cfg?['gym']);
  String get device => asStr(_cfg?['device']);
  int get slot => asInt(_cfg?['slot'], 1);
  bool get isMain => asBool(_cfg?['main'], true);
  DateTime? get lastSync => asTime(_cfg?['lastSync']);
  String get serverUrl => asStr(_cfg?['url']);

  static bool get vendorServer => Vendor.syncUrl.isNotEmpty && Vendor.syncKey.isNotEmpty;

  SyncCreds get _creds => SyncCreds(gym: gym, secret: asStr(_cfg?['secret']), url: asStr(_cfg?['url']), key: asStr(_cfg?['key']));

  /// رمز ربط جهاز آخر بنفس النادي (يُعرض QR أو نصاً). من يملكه يستطيع الوصول لبيانات النادي.
  String get joinCode {
    final m = <String, Object?>{'g': gym, 's': _cfg?['secret']};
    if (_cfg?['url'] != Vendor.syncUrl) m['u'] = _cfg?['url'];
    if (_cfg?['key'] != Vendor.syncKey) m['k'] = _cfg?['key'];
    return 'NS1.${base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '')}';
  }

  static SyncCreds parseJoinCode(String code) {
    code = code.trim();
    if (!code.startsWith('NS1.')) throw GymException(tr('رمز الربط غير صحيح'));
    try {
      var b = code.substring(4);
      b = b.padRight((b.length + 3) ~/ 4 * 4, '=');
      final m = jsonDecode(utf8.decode(base64Url.decode(b))) as Map;
      final c = SyncCreds(
        gym: asStr(m['g']),
        secret: asStr(m['s']),
        url: asStr(m['u'], Vendor.syncUrl),
        key: asStr(m['k'], Vendor.syncKey),
      );
      if (c.gym.isEmpty || c.secret.isEmpty || c.url.isEmpty) throw const FormatException('');
      return c;
    } catch (_) {
      throw GymException(tr('رمز الربط غير صحيح'));
    }
  }

  bool _loaded = false;

  Future<void> ensureLoaded() async {
    if (!_loaded) await load();
  }

  Future<void> load() async {
    _loaded = true;
    _cfg = await _store.record('config').get(d.db);
    _attach();
    await _refreshPending();
  }

  void _attach() {
    if (_cfg == null) {
      d.syncDevice = null;
      d.onLocalChange = null;
      phase = SyncPhase.off;
      return;
    }
    d.syncDevice = device;
    d.syncSlot = slot;
    d.syncSlotted = asBool(_cfg!['slotted']);
    d.observeStamp(asInt(_cfg!['hlc']));
    d.onLocalChange = _onLocalChange;
    d.beforeWipe = leave;
  }

  Future<void> _save() async {
    if (_cfg == null) return;
    _cfg!['hlc'] = d.hlc;
    await _store.record('config').put(d.db, _cfg!);
  }

  Future<void> _refreshPending() async {
    pending = enabled ? await d.pendingCount() : 0;
    if (enabled && phase != SyncPhase.syncing && phase != SyncPhase.error && phase != SyncPhase.locked && phase != SyncPhase.offline) {
      phase = pending > 0 ? SyncPhase.pending : SyncPhase.synced;
    }
    notifyListeners();
  }

  /// أول جهاز: إنشاء النادي على السحابة ورفع كل بياناته
  Future<void> create({String? url, String? key}) async {
    d.require(Feature.cloudSync);
    final c = SyncCreds(gym: randomCode(12), secret: randomCode(28), url: url ?? Vendor.syncUrl, key: key ?? Vendor.syncKey);
    if (c.url.isEmpty || c.key.isEmpty) throw GymException(tr('أدخل عنوان خادم المزامنة ومفتاحه'));
    final dev = newId();
    final r = await backend.register(c, dev);
    _cfg = {'gym': c.gym, 'secret': c.secret, 'url': c.url, 'key': c.key, 'device': dev, 'slot': r.slot, 'slotted': r.devices > 1, 'cursor': 0, 'main': true};
    await _save();
    _attach();
    await d.enqueueAll();
    await syncNow();
  }

  /// جهاز إضافي: يستبدل بياناته المحلية ببيانات النادي من السحابة
  Future<void> join(String code) async {
    d.require(Feature.cloudSync);
    final c = parseJoinCode(code);
    final dev = newId();
    final r = await backend.register(c, dev);
    _checkLimit(r.devices);
    _cfg = {'gym': c.gym, 'secret': c.secret, 'url': c.url, 'key': c.key, 'device': dev, 'slot': r.slot, 'slotted': true, 'cursor': 0, 'main': false};
    d.beforeWipe = null;
    await d.clearForJoin();
    await _save();
    _attach();
    await syncNow();
    if (lastError != null) throw GymException(lastError!);
  }

  /// إيقاف المزامنة على هذا الجهاز فقط (البيانات تبقى على الجهاز وعلى السحابة)
  Future<void> leave() async {
    await _store.record('config').delete(d.db);
    await GymData.outbox.delete(d.db);
    _cfg = null;
    d.beforeWipe = null;
    _attach();
    lastError = null;
    await _refreshPending();
  }

  Future<void> setMain(bool v) async {
    _cfg!['main'] = v;
    await _save();
    notifyListeners();
  }

  void _checkLimit(int n) {
    devices = n;
    final limit = d.license.syncDeviceLimit;
    if (n > limit) {
      throw LicenseException(
          tr('عدد الأجهزة المتزامنة ({n}) أكبر من المسموح في نسختك ({l}). رقِّ إلى Pro للمزامنة حتى {p} أجهزة', {'n': n, 'l': limit, 'p': proSyncDevices}),
          Feature.multiDevice);
    }
  }

  /// يبدأ المزامنة الدورية (كل دقيقة عند توفر النت، ومباشرة بعد أي تعديل)
  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _auto());
    Future.delayed(const Duration(seconds: 2), _auto);
  }

  void stop() {
    _timer?.cancel();
    _debounce?.cancel();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }

  void _onLocalChange() {
    pending++;
    if (phase == SyncPhase.synced) phase = SyncPhase.pending;
    notifyListeners();
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 4), _auto);
  }

  Future<void> _auto() async {
    if (!enabled) return;
    if (_nextTry != null && DateTime.now().isBefore(_nextTry!)) return;
    await syncNow();
  }

  /// رفع ثم جلب. يعيد true إن اكتملت. لا يرمي أخطاء: الحالة في [phase] و[lastError].
  Future<bool> syncNow() async {
    if (!enabled) return false;
    if (_busy) {
      _again = true;
      return false;
    }
    if (!d.has(Feature.cloudSync)) {
      phase = SyncPhase.locked;
      lastError = tr('المزامنة السحابية متاحة في نسخة Plus. بياناتك محفوظة على الجهاز');
      notifyListeners();
      return false;
    }
    _busy = true;
    phase = SyncPhase.syncing;
    notifyListeners();
    try {
      do {
        _again = false;
        await _push();
        await _pull();
      } while (_again);
      _cfg!['lastSync'] = DateTime.now().toIso8601String();
      await _save();
      lastError = null;
      _fails = 0;
      _nextTry = null;
      phase = SyncPhase.synced;
      return true;
    } on LicenseException catch (e) {
      phase = SyncPhase.locked;
      lastError = e.message;
      return false;
    } on SyncRejected catch (e) {
      phase = SyncPhase.error;
      lastError = e.toString();
      _backoff();
      return false;
    } catch (e) {
      // انقطاع النت أو بطء الخادم: نكمل العمل محلياً ونحاول لاحقاً
      phase = SyncPhase.offline;
      lastError = tr('لا يوجد اتصال بالإنترنت. التطبيق يعمل عادياً وستتم المزامنة عند عودة النت');
      debugPrint('sync: $e');
      _backoff();
      return false;
    } finally {
      _busy = false;
      await _refreshPending();
    }
  }

  void _backoff() {
    _fails++;
    final secs = (30 * (1 << (_fails - 1).clamp(0, 4))).clamp(30, 300);
    _nextTry = DateTime.now().add(Duration(seconds: secs));
  }

  Future<void> _push() async {
    while (true) {
      final entries = await GymData.outbox.find(d.db, finder: Finder(limit: pushBatch));
      if (entries.isEmpty) return;
      final recs = <({String coll, String id, Map<String, Object?>? data, int ts})>[];
      for (final e in entries) {
        final i = e.key.indexOf('/');
        final coll = e.key.substring(0, i);
        final id = e.key.substring(i + 1);
        recs.add((coll: coll, id: id, data: d.snapshotOf(coll, id), ts: asInt(e.value['ts'])));
      }
      final n = await backend.push(_creds, device, SyncPush(recs));
      await _afterDevices(n);
      // حذف ما رُفع فقط إن لم يتعدل مرة أخرى أثناء الرفع
      await d.db.transaction((txn) async {
        for (final e in entries) {
          final cur = await GymData.outbox.record(e.key).get(txn);
          if (cur != null && asInt(cur['ts']) == asInt(e.value['ts'])) await GymData.outbox.record(e.key).delete(txn);
        }
      });
      if (entries.length < pushBatch) return;
    }
  }

  Future<void> _pull() async {
    while (true) {
      final cursor = asInt(_cfg!['cursor']);
      final r = await backend.pull(_creds, device, cursor, pullBatch);
      await _afterDevices(r.devices);
      if (r.records.isEmpty) return;
      await d.applyRemote([for (final x in r.records) if (x.dev != device) x]);
      _cfg!['cursor'] = r.seqs.last;
      await _save();
      if (r.records.length < pullBatch) return;
    }
  }

  Future<void> _afterDevices(int n) async {
    _checkLimit(n);
    if (n > 1 && !asBool(_cfg!['slotted'])) {
      _cfg!['slotted'] = true;
      d.syncSlotted = true;
      await _save();
    }
  }
}
