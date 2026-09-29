import '../core/dates.dart';
import 'base.dart';
import 'member.dart';

/// مراحل العميل المحتمل حتى يشترك أو يُغلق
enum LeadStage { fresh, contacted, trial, negotiating, won, lost }

LeadStage leadStageFrom(Object? v) =>
    LeadStage.values.firstWhere((s) => s.name == v, orElse: () => LeadStage.fresh);

enum LeadNoteKind { call, whatsapp, visit, note }

/// متابعة مسجلة على العميل المحتمل
class LeadNote {
  final DateTime time;
  final LeadNoteKind kind;
  final String text;
  final String? by;

  LeadNote({required this.time, required this.kind, required this.text, this.by});

  Map<String, Object?> toMap() =>
      compact({'time': time.toIso8601String(), 'kind': kind.name, 'text': text, 'by': by});

  factory LeadNote.fromMap(Map<String, Object?> m) => LeadNote(
        time: asTime(m['time']) ?? DateTime.now(),
        kind: LeadNoteKind.values.firstWhere((k) => k.name == m['kind'], orElse: () => LeadNoteKind.note),
        text: asStr(m['text']),
        by: asStrOrNull(m['by']),
      );
}

/// عميل محتمل: سأل عن الأسعار أو جاء لحصة تجريبية ولم يشترك بعد
class Lead implements Entity {
  @override
  final String id;
  String name;
  String phone;
  Gender? gender;
  String? source; // فيسبوك، ترشيح، مرّ من أمام النادي...
  String? referredBy; // معرّف العضو الذي رشّحه
  String? interestPlanId;
  LeadStage stage;
  String? assignedTo; // معرّف الموظف المسؤول عن المتابعة
  DateTime? followUpAt; // موعد المتابعة القادمة
  DateTime? trialDate;
  String? lostReason;
  String? memberId; // بعد تحويله لعضو
  Channel channel;
  bool optOut;
  List<LeadNote> history;
  String? notes;
  final DateTime createdAt;

  Lead({
    required this.id,
    required this.name,
    required this.phone,
    required this.createdAt,
    this.gender,
    this.source,
    this.referredBy,
    this.interestPlanId,
    this.stage = LeadStage.fresh,
    this.assignedTo,
    this.followUpAt,
    this.trialDate,
    this.lostReason,
    this.memberId,
    this.channel = Channel.whatsapp,
    this.optOut = false,
    List<LeadNote>? history,
    this.notes,
  }) : history = history ?? [];

  bool get open => stage != LeadStage.won && stage != LeadStage.lost;

  /// متأخر في المتابعة
  bool isOverdue(DateTime now) => open && followUpAt != null && followUpAt!.isBefore(now);

  @override
  Map<String, Object?> toMap() => compact({
        'id': id,
        'name': name,
        'phone': phone,
        'gender': genderCode(gender),
        'source': source,
        'referredBy': referredBy,
        'interestPlanId': interestPlanId,
        'stage': stage.name,
        'assignedTo': assignedTo,
        'followUpAt': followUpAt?.toIso8601String(),
        'trialDate': trialDate == null ? null : dayKey(trialDate!),
        'lostReason': lostReason,
        'memberId': memberId,
        'channel': channel.name,
        'optOut': optOut ? true : null,
        'history': history.isEmpty ? null : history.map((h) => h.toMap()).toList(),
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
      });

  factory Lead.fromMap(Map<String, Object?> m) => Lead(
        id: asStr(m['id']),
        name: asStr(m['name']),
        phone: asStr(m['phone']),
        gender: genderFrom(m['gender']),
        source: asStrOrNull(m['source']),
        referredBy: asStrOrNull(m['referredBy']),
        interestPlanId: asStrOrNull(m['interestPlanId']),
        stage: leadStageFrom(m['stage']),
        assignedTo: asStrOrNull(m['assignedTo']),
        followUpAt: asTime(m['followUpAt']),
        trialDate: tryParseDay(asStrOrNull(m['trialDate'])),
        lostReason: asStrOrNull(m['lostReason']),
        memberId: asStrOrNull(m['memberId']),
        channel: channelFrom(m['channel']),
        optOut: asBool(m['optOut']),
        history: asMapList(m['history']).map(LeadNote.fromMap).toList(),
        notes: asStrOrNull(m['notes']),
        createdAt: asTime(m['createdAt']) ?? DateTime.now(),
      );
}
