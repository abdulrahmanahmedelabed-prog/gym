import '../core/dates.dart';
import 'base.dart';

enum Gender { male, female }

Gender? genderFrom(Object? v) => switch (v) {
      'm' || 'male' => Gender.male,
      'f' || 'female' => Gender.female,
      _ => null,
    };

String? genderCode(Gender? g) => g == null ? null : (g == Gender.male ? 'm' : 'f');

/// قناة الرسائل المفضلة للعضو
enum Channel { whatsapp, sms }

Channel channelFrom(Object? v) => v == 'sms' ? Channel.sms : Channel.whatsapp;

class Member implements Entity {
  @override
  final String id;
  int code; // رقم العضوية الظاهر على البطاقة
  String name;
  String phone;
  String? phone2;
  Gender? gender;
  DateTime? birthDate;
  String? email;
  String? nationalId;
  String? address;
  String? emergencyName;
  String? emergencyPhone;
  String? medicalNotes;
  String? notes;
  String? photo; // صورة مصغرة base64
  String? source; // من أين عرف النادي
  String? referredBy; // معرّف العضو الذي رشّحه
  String cardToken; // محتوى رمز QR على البطاقة
  Channel channel;
  bool optOut; // لا يريد رسائل تذكير/تسويق (الفواتير تُرسل عند الطلب فقط)
  List<String> tags;
  bool archived;
  DateTime createdAt;

  Member({
    required this.id,
    required this.code,
    required this.name,
    required this.phone,
    required this.cardToken,
    required this.createdAt,
    this.phone2,
    this.gender,
    this.birthDate,
    this.email,
    this.nationalId,
    this.address,
    this.emergencyName,
    this.emergencyPhone,
    this.medicalNotes,
    this.notes,
    this.photo,
    this.source,
    this.referredBy,
    this.channel = Channel.whatsapp,
    this.optOut = false,
    List<String>? tags,
    this.archived = false,
  }) : tags = tags ?? [];

  String get firstName => name.trim().split(RegExp(r'\s+')).first;

  /// محتوى رمز QR: البادئة تمنع قراءة أي رمز QR عشوائي على أنه عضو
  String get qrData => 'NADI:$cardToken';

  int? ageOn(DateTime day) {
    final b = birthDate;
    if (b == null) return null;
    var age = day.year - b.year;
    if (day.month < b.month || (day.month == b.month && day.day < b.day)) age--;
    return age;
  }

  bool isBirthday(DateTime day) =>
      birthDate != null && birthDate!.month == day.month && birthDate!.day == day.day;

  @override
  Map<String, Object?> toMap() => compact({
        'id': id,
        'code': code,
        'name': name,
        'phone': phone,
        'phone2': phone2,
        'gender': genderCode(gender),
        'birthDate': birthDate == null ? null : dayKey(birthDate!),
        'email': email,
        'nationalId': nationalId,
        'address': address,
        'emergencyName': emergencyName,
        'emergencyPhone': emergencyPhone,
        'medicalNotes': medicalNotes,
        'notes': notes,
        'photo': photo,
        'source': source,
        'referredBy': referredBy,
        'cardToken': cardToken,
        'channel': channel.name,
        'optOut': optOut ? true : null,
        'tags': tags.isEmpty ? null : tags,
        'archived': archived ? true : null,
        'createdAt': createdAt.toIso8601String(),
      });

  factory Member.fromMap(Map<String, Object?> m) => Member(
        id: asStr(m['id']),
        code: asInt(m['code']),
        name: asStr(m['name']),
        phone: asStr(m['phone']),
        phone2: asStrOrNull(m['phone2']),
        gender: genderFrom(m['gender']),
        birthDate: tryParseDay(asStrOrNull(m['birthDate'])),
        email: asStrOrNull(m['email']),
        nationalId: asStrOrNull(m['nationalId']),
        address: asStrOrNull(m['address']),
        emergencyName: asStrOrNull(m['emergencyName']),
        emergencyPhone: asStrOrNull(m['emergencyPhone']),
        medicalNotes: asStrOrNull(m['medicalNotes']),
        notes: asStrOrNull(m['notes']),
        photo: asStrOrNull(m['photo']),
        source: asStrOrNull(m['source']),
        referredBy: asStrOrNull(m['referredBy']),
        cardToken: asStr(m['cardToken']),
        channel: channelFrom(m['channel']),
        optOut: asBool(m['optOut']),
        tags: asStrList(m['tags']),
        archived: asBool(m['archived']),
        createdAt: asTime(m['createdAt']) ?? DateTime.now(),
      );
}
