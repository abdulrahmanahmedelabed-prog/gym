import '../core/dates.dart';
import 'base.dart';
import 'member.dart';

/// سبب رفض الدخول (أو ملاحظة عند السماح)
enum CheckinResult {
  allowed,
  override, // سمح به المدير رغم وجود مانع
  notFound,
  archived,
  noSubscription,
  expired,
  exhausted,
  frozen,
  notStarted,
  outsideHours,
  wrongDay,
  genderHours,
  genderPlan,
  dailyLimit,
  debt,
}

class Checkin implements Entity {
  @override
  final String id;
  final String memberId;
  final String? subscriptionId;
  final DateTime time;
  final CheckinResult result;
  final String method; // scan / manual / kiosk
  final String? by;
  final String? note;

  Checkin({
    required this.id,
    required this.memberId,
    this.subscriptionId,
    required this.time,
    required this.result,
    this.method = 'manual',
    this.by,
    this.note,
  });

  bool get allowed => result == CheckinResult.allowed || result == CheckinResult.override;

  @override
  Map<String, Object?> toMap() => compact({
        'id': id,
        'memberId': memberId,
        'subscriptionId': subscriptionId,
        'time': time.toIso8601String(),
        'result': result.name,
        'method': method,
        'by': by,
        'note': note,
      });

  factory Checkin.fromMap(Map<String, Object?> m) => Checkin(
        id: asStr(m['id']),
        memberId: asStr(m['memberId']),
        subscriptionId: asStrOrNull(m['subscriptionId']),
        time: asTime(m['time']) ?? DateTime.now(),
        result: CheckinResult.values.firstWhere((r) => r.name == m['result'], orElse: () => CheckinResult.allowed),
        method: asStr(m['method'], 'manual'),
        by: asStrOrNull(m['by']),
        note: asStrOrNull(m['note']),
      );
}

/// حالة الرسالة:
/// queued  = تنتظر الإرسال الآلي عبر مزوّد (API)
/// manual  = جاهزة للإرسال بلمسة من الجوال (واتساب/الرسائل)
enum MsgStatus { queued, manual, sent, failed, cancelled }

class Message implements Entity {
  @override
  final String id;
  final String? memberId;
  final String? leadId;
  final String name;
  String phone;
  Channel channel;
  final String kind; // نوع التذكير أو campaign / custom / invoice
  final String body;
  MsgStatus status;
  String? provider;
  String? error;
  final String? dedupKey; // يمنع إرسال نفس التذكير مرتين
  int attempts;
  final DateTime createdAt;
  DateTime? sentAt;
  final String? invoiceId; // لإرفاق الفاتورة PDF عند الإمكان

  Message({
    required this.id,
    this.memberId,
    this.leadId,
    required this.name,
    required this.phone,
    required this.channel,
    required this.kind,
    required this.body,
    required this.status,
    this.provider,
    this.error,
    this.dedupKey,
    this.attempts = 0,
    required this.createdAt,
    this.sentAt,
    this.invoiceId,
  });

  @override
  Map<String, Object?> toMap() => compact({
        'id': id,
        'memberId': memberId,
        'leadId': leadId,
        'name': name,
        'phone': phone,
        'channel': channel.name,
        'kind': kind,
        'body': body,
        'status': status.name,
        'provider': provider,
        'error': error,
        'dedupKey': dedupKey,
        'attempts': attempts,
        'createdAt': createdAt.toIso8601String(),
        'sentAt': sentAt?.toIso8601String(),
        'invoiceId': invoiceId,
      });

  factory Message.fromMap(Map<String, Object?> m) => Message(
        id: asStr(m['id']),
        memberId: asStrOrNull(m['memberId']),
        leadId: asStrOrNull(m['leadId']),
        name: asStr(m['name']),
        phone: asStr(m['phone']),
        channel: channelFrom(m['channel']),
        kind: asStr(m['kind']),
        body: asStr(m['body']),
        status: MsgStatus.values.firstWhere((s) => s.name == m['status'], orElse: () => MsgStatus.manual),
        provider: asStrOrNull(m['provider']),
        error: asStrOrNull(m['error']),
        dedupKey: asStrOrNull(m['dedupKey']),
        attempts: asInt(m['attempts']),
        createdAt: asTime(m['createdAt']) ?? DateTime.now(),
        sentAt: asTime(m['sentAt']),
        invoiceId: asStrOrNull(m['invoiceId']),
      );
}

/// قياسات الجسم لمتابعة تقدم العضو
class Measurement implements Entity {
  @override
  final String id;
  final String memberId;
  DateTime date;
  double? weight;
  double? height;
  double? bodyFat;
  double? muscle;
  double? waist;
  double? chest;
  double? arm;
  double? hip;
  double? thigh;
  String? notes;

  Measurement({
    required this.id,
    required this.memberId,
    required this.date,
    this.weight,
    this.height,
    this.bodyFat,
    this.muscle,
    this.waist,
    this.chest,
    this.arm,
    this.hip,
    this.thigh,
    this.notes,
  });

  double? get bmi {
    if (weight == null || height == null || height! <= 0) return null;
    final m = height! / 100;
    return weight! / (m * m);
  }

  @override
  Map<String, Object?> toMap() => compact({
        'id': id,
        'memberId': memberId,
        'date': dayKey(date),
        'weight': weight,
        'height': height,
        'bodyFat': bodyFat,
        'muscle': muscle,
        'waist': waist,
        'chest': chest,
        'arm': arm,
        'hip': hip,
        'thigh': thigh,
        'notes': notes,
      });

  factory Measurement.fromMap(Map<String, Object?> m) => Measurement(
        id: asStr(m['id']),
        memberId: asStr(m['memberId']),
        date: parseDay(asStr(m['date'])),
        weight: asDoubleOrNull(m['weight']),
        height: asDoubleOrNull(m['height']),
        bodyFat: asDoubleOrNull(m['bodyFat']),
        muscle: asDoubleOrNull(m['muscle']),
        waist: asDoubleOrNull(m['waist']),
        chest: asDoubleOrNull(m['chest']),
        arm: asDoubleOrNull(m['arm']),
        hip: asDoubleOrNull(m['hip']),
        thigh: asDoubleOrNull(m['thigh']),
        notes: asStrOrNull(m['notes']),
      );
}

/// سجل العمليات الحساسة (إلغاء فاتورة، استرداد، سماح استثنائي بالدخول...)
class AuditEntry implements Entity {
  @override
  final String id;
  final DateTime time;
  final String? user;
  final String action;
  final String details;

  AuditEntry({required this.id, required this.time, this.user, required this.action, required this.details});

  @override
  Map<String, Object?> toMap() =>
      compact({'id': id, 'time': time.toIso8601String(), 'user': user, 'action': action, 'details': details});

  factory AuditEntry.fromMap(Map<String, Object?> m) => AuditEntry(
        id: asStr(m['id']),
        time: asTime(m['time']) ?? DateTime.now(),
        user: asStrOrNull(m['user']),
        action: asStr(m['action']),
        details: asStr(m['details']),
      );
}
