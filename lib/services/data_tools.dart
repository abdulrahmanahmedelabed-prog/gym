import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../core/dates.dart';
import '../core/i18n.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../core/phone.dart';
import '../data/db_factory.dart' as files;
import '../data/gym_data.dart';
import '../models/activity.dart';
import '../models/base.dart';
import '../models/billing.dart';
import '../models/business.dart';
import '../models/member.dart';
import '../models/plan.dart';
import 'license.dart';
import 'membership.dart';

// -----------------------------------------------------------------------------
// الرقم السري للموظفين
// -----------------------------------------------------------------------------

String hashPin(String pin, String staffId) => sha256.convert(utf8.encode('nadi|$staffId|$pin')).toString();

bool checkPin(Staff s, String pin) => s.pinHash != null && s.pinHash == hashPin(pin, s.id);

// -----------------------------------------------------------------------------
// صيانة: إبقاء البيانات خفيفة على الجوالات القديمة
// -----------------------------------------------------------------------------

/// يحذف السجلات القديمة التي لا يحتاجها العمل اليومي، فيبقى فتح التطبيق سريعاً والذاكرة قليلة
/// حتى بعد سنوات. لا يمس الأعضاء والاشتراكات والفواتير والدفعات وسجل العمليات أبداً.
/// النسخ الاحتياطية اليومية تحفظ كل شيء قبل الحذف.
class Maintenance {
  final GymData d;
  Maintenance(this.d);

  /// سجل الدخول: يُحتفظ به سنتين (وأكثر إن كان اشتراكه ما زال قريباً)
  static const checkinDays = 730;

  /// الرسائل المرسلة أو الملغاة: 6 أشهر
  static const messageDays = 180;

  Future<int> prune() async {
    final today = d.today;
    final chkCut = addDays(today, -checkinDays);
    final subCut = addDays(today, -60);
    final msgCut = addDays(today, -messageDays);
    var n = 0;
    final oldChk = d.checkins.all.where((c) {
      if (!c.time.isBefore(chkCut)) return false;
      final s = d.subs[c.subscriptionId];
      return s == null || s.end.isBefore(subCut);
    }).length;
    if (oldChk > 0) {
      await d.removeWhere<Checkin>((c) {
        if (!c.time.isBefore(chkCut)) return false;
        final s = d.subs[c.subscriptionId];
        return s == null || s.end.isBefore(subCut);
      });
      n += oldChk;
    }
    bool oldMsg(Message m) =>
        m.createdAt.isBefore(msgCut) && (m.status == MsgStatus.sent || m.status == MsgStatus.cancelled || m.status == MsgStatus.failed);
    final msgs = d.messages.all.where(oldMsg).length;
    if (msgs > 0) {
      await d.removeWhere<Message>(oldMsg);
      n += msgs;
    }
    return n;
  }

  /// مرة في اليوم على الأكثر
  Future<int> pruneDaily() async {
    final key = dayKey(d.today);
    if (d.settings.str('lastPrune') == key) return 0;
    final n = await prune();
    d.settings.setStr('lastPrune', key);
    await d.saveSettings();
    return n;
  }
}

// -----------------------------------------------------------------------------
// النسخ الاحتياطي
// -----------------------------------------------------------------------------

class BackupService {
  final GymData d;
  BackupService(this.d);

  Future<Uint8List> exportBytes() async => Uint8List.fromList(utf8.encode(jsonEncode(await d.exportAll())));

  String fileName() {
    final n = d.now();
    return 'nadi-gym-backup-${dayKey(n)}-${n.hour.toString().padLeft(2, '0')}${n.minute.toString().padLeft(2, '0')}.json';
  }

  Future<void> restore(Uint8List bytes) async {
    final data = jsonDecode(utf8.decode(bytes));
    if (data is! Map) throw FormatException(tr('ملف غير صالح'));
    await d.importAll(Map<String, Object?>.from(data));
  }

  /// نسخة تلقائية يومية داخل الجوال (آخر 10 نسخ)
  Future<String?> autoDaily() async {
    final dir = await files.backupDirectory();
    if (dir == null) return null;
    final today = dayKey(d.now());
    final existing = await files.listFiles(dir);
    if (existing.any((p) => p.contains('auto-$today'))) return null;
    final path = '$dir/nadi-gym-auto-$today.json';
    await files.writeFile(path, await exportBytes());
    final autos = (await files.listFiles(dir)).where((p) => p.contains('nadi-gym-auto-')).toList();
    while (autos.length > 10) {
      await files.deleteFile(autos.removeAt(0));
    }
    return path;
  }
}

// -----------------------------------------------------------------------------
// استيراد الأعضاء من Excel/CSV
// -----------------------------------------------------------------------------

/// قراءة CSV (يدعم علامات التنصيص والفاصلة المنقوطة التي يصدّرها Excel العربي)
List<List<String>> parseCsv(String text) {
  if (text.startsWith('﻿')) text = text.substring(1);
  final firstLine = text.split('\n').first;
  final sep = ';'.allMatches(firstLine).length > ','.allMatches(firstLine).length
      ? ';'
      : ('\t'.allMatches(firstLine).length > ','.allMatches(firstLine).length ? '\t' : ',');
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(ch);
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == sep) {
      row.add(cell.toString().trim());
      cell.clear();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(cell.toString().trim());
      cell.clear();
      if (row.any((c) => c.isNotEmpty)) rows.add(row);
      row = <String>[];
    } else {
      cell.write(ch);
    }
  }
  row.add(cell.toString().trim());
  if (row.any((c) => c.isNotEmpty)) rows.add(row);
  return rows;
}

String toCsv(List<List<Object?>> rows) {
  String esc(Object? v) {
    final s = v?.toString() ?? '';
    return s.contains(RegExp('[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
  }

  return '﻿${rows.map((r) => r.map(esc).join(',')).join('\n')}';
}

class ImportResult {
  int members = 0;
  int subscriptions = 0;
  int skipped = 0;
  final List<String> errors = [];
}

class MemberImporter {
  final GymData d;
  final MembershipService ms;
  MemberImporter(this.d) : ms = MembershipService(d);

  static const _aliases = {
    'name': ['name', 'الاسم', 'اسم العضو', 'الإسم', 'full name'],
    'phone': ['phone', 'mobile', 'الجوال', 'الهاتف', 'الموبايل', 'رقم الجوال', 'رقم الهاتف', 'التليفون'],
    'gender': ['gender', 'sex', 'الجنس', 'النوع'],
    'birth': ['birth', 'birthdate', 'birth date', 'تاريخ الميلاد', 'الميلاد'],
    'plan': ['plan', 'package', 'الباقة', 'الاشتراك', 'نوع الاشتراك'],
    'start': ['start', 'start date', 'البداية', 'تاريخ البداية', 'من'],
    'end': ['end', 'end date', 'expiry', 'الانتهاء', 'تاريخ الانتهاء', 'النهاية', 'إلى'],
    'visits': ['visits', 'visits left', 'sessions', 'الحصص', 'الحصص المتبقية'],
    'code': ['code', 'id', 'member no', 'رقم العضوية', 'الرقم', 'كود'],
    'notes': ['notes', 'ملاحظات'],
    'balance': ['balance', 'debt', 'الرصيد', 'المتبقي', 'الدين'],
  };

  static Map<String, int> mapHeader(List<String> header) {
    final out = <String, int>{};
    for (var i = 0; i < header.length; i++) {
      final h = header[i].trim().toLowerCase();
      for (final e in _aliases.entries) {
        if (e.value.contains(h) && !out.containsKey(e.key)) out[e.key] = i;
      }
    }
    return out;
  }

  static DateTime? parseAnyDate(String s) {
    s = digitsOnly(s).isEmpty ? '' : s.trim();
    if (s.isEmpty) return null;
    final iso = tryParseDay(s.replaceAll('/', '-'));
    if (iso != null && s.indexOf(RegExp(r'[-/]')) == 4) return iso;
    final p = s.split(RegExp(r'[-/.]'));
    if (p.length == 3) {
      final a = int.tryParse(digitsOnly(p[0])), b = int.tryParse(digitsOnly(p[1])), c = int.tryParse(digitsOnly(p[2]));
      if (a != null && b != null && c != null) {
        final y = c < 100 ? 2000 + c : c;
        return DateTime(y, b, a); // يوم/شهر/سنة كما هو شائع عربياً
      }
    }
    return null;
  }

  Future<ImportResult> importCsv(String text) async {
    d.require(Feature.importExport);
    final rows = parseCsv(text);
    final res = ImportResult();
    if (rows.length < 2) {
      res.errors.add(tr('الملف فارغ'));
      return res;
    }
    final map = mapHeader(rows.first);
    if (!map.containsKey('name') || !map.containsKey('phone')) {
      res.errors.add(tr('يجب أن يحتوي الصف الأول على عمودي الاسم والجوال'));
      return res;
    }
    String cell(List<String> r, String k) => map[k] != null && map[k]! < r.length ? r[map[k]!] : '';
    final save = <Entity>[];
    final plansByName = {for (final p in d.plans.all) p.name.trim(): p};
    final phones = <String>{};
    for (var i = 1; i < rows.length; i++) {
      final r = rows[i];
      final name = cell(r, 'name');
      final phone = cell(r, 'phone');
      if (name.isEmpty) {
        res.skipped++;
        continue;
      }
      final key = digitsOnly(phone);
      if ((key.isNotEmpty && ms.findByPhone(phone) != null) || (key.isNotEmpty && !phones.add(key))) {
        res.skipped++;
        res.errors.add(tr('صف {n}: الرقم مكرر ({p})', {'n': i + 1, 'p': phone}));
        continue;
      }
      final g = cell(r, 'gender').toLowerCase();
      final m = ms.newMember(name: name, phone: phone)
        ..gender = (g.startsWith('f') || g.contains('أنث') || g.contains('انث') || g.contains('سيد'))
            ? Gender.female
            : (g.startsWith('m') || g.contains('ذكر') || g.contains('رجل') ? Gender.male : null)
        ..birthDate = parseAnyDate(cell(r, 'birth'))
        ..notes = cell(r, 'notes').isEmpty ? null : cell(r, 'notes');
      final code = int.tryParse(digitsOnly(cell(r, 'code')));
      m.code = (code != null && d.memberByCode(code) == null) ? code : d.nextCounter('member', start: 1001);
      save.add(m);
      res.members++;
      final end = parseAnyDate(cell(r, 'end'));
      if (end != null) {
        final planName = cell(r, 'plan').isEmpty ? tr('اشتراك مستورد') : cell(r, 'plan');
        final plan = plansByName[planName] ??= Plan(id: newId(), name: planName, active: false);
        if (!d.plans.items.containsKey(plan.id) && !save.contains(plan)) save.add(plan);
        final start = parseAnyDate(cell(r, 'start')) ?? addDays(end, -29);
        final visits = int.tryParse(digitsOnly(cell(r, 'visits')));
        save.add(ms.importedSub(m, plan, start, end, visitsLeft: visits));
        res.subscriptions++;
      }
      final bal = parseAmount(cell(r, 'balance'));
      if (bal != null && bal > 0) {
        // رصيد سابق من الدفتر القديم
        save.add(ms.newInvoice(
            memberId: m.id,
            items: [InvoiceItem(kind: ItemKind.other, description: tr('رصيد سابق'), unitPrice: bal)]));
      }
    }
    await d.putAll(save);
    return res;
  }
}
