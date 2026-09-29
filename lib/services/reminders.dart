import '../core/dates.dart';
import '../core/i18n.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../core/phone.dart';
import '../data/gym_data.dart';
import '../models/activity.dart';
import '../models/billing.dart';
import '../models/business.dart';
import '../models/member.dart';
import '../models/settings.dart';
import '../models/subscription.dart';
import 'license.dart';
import 'membership.dart';
import 'reports.dart';
import 'templates.dart';

/// محرك التذكيرات الآلية: يقرر من يجب تذكيره اليوم وبماذا، ويضع الرسائل في صندوق الصادر.
/// كل تذكير له مفتاح فريد فلا يُرسل مرتين، ويُرسل حتى لو لم يُفتح التطبيق في اليوم المحدد بالضبط.
class ReminderEngine {
  final GymData d;
  final MembershipService ms;
  final TemplateContext ctx;

  ReminderEngine(this.d)
      : ms = MembershipService(d),
        ctx = TemplateContext(d);

  GymSettings get s => d.settings;

  /// القناة وطريقة الإرسال لعضو
  ({Channel channel, bool auto}) route(Channel preferred) {
    final mode = preferred == Channel.whatsapp ? s.waMode : s.smsMode;
    return (channel: preferred, auto: mode != 'phone');
  }

  Message? build({
    Member? member,
    String? phone,
    String? name,
    required String kind,
    required String body,
    String? dedupKey,
    String? invoiceId,
    String? leadId,
    Channel? channel,
  }) {
    final p = phone ?? member?.phone;
    if (p == null || !looksLikePhone(p) || body.trim().isEmpty) return null;
    final r = route(channel ?? member?.channel ?? Channel.whatsapp);
    return Message(
      id: newId(),
      memberId: member?.id,
      leadId: leadId,
      name: name ?? member?.name ?? '',
      phone: p,
      channel: r.channel,
      kind: kind,
      body: body,
      status: r.auto ? MsgStatus.queued : MsgStatus.manual,
      dedupKey: dedupKey,
      createdAt: d.now(),
      invoiceId: invoiceId,
    );
  }

  /// يختار العتبة المناسبة من قائمة أيام مرتبة تنازلياً: مع [7،3،1] والمتبقي 5 أيام ← 7
  static int? bucketBefore(int value, List<int> days) {
    final sorted = [...days]..sort((a, b) => b.compareTo(a));
    for (var i = 0; i < sorted.length; i++) {
      final n = sorted[i];
      final lower = i + 1 < sorted.length ? sorted[i + 1] : -1;
      if (value <= n && value > lower) return n;
    }
    return null;
  }

  /// للتذكير بعد حدث: مع [3،10] والتأخير 5 أيام ← 3، والتأخير 12 ← 10
  static int? bucketAfter(int value, List<int> days) {
    final sorted = [...days]..sort();
    int? hit;
    for (final n in sorted) {
      if (value >= n) hit = n;
    }
    return hit;
  }

  /// كل رسائل اليوم المقترحة (قبل استبعاد ما أُرسل سابقاً)
  List<Message> plan([DateTime? at]) {
    final day = dateOnly(at ?? d.now());
    final out = <Message>[];
    void add(Message? m) {
      if (m != null) out.add(m);
    }

    for (final m in d.members.all) {
      if (m.archived) continue;
      final sub = ms.currentSub(m.id, day);
      final marketingOk = !m.optOut;

      if (sub != null && marketingOk) {
        final st = sub.statusOn(day);
        final renewed = ms.renewedAfter(sub);
        final vars = ctx.forSub(m, sub);
        if (st == SubStatus.active && !renewed) {
          final dl = sub.daysLeft(day);
          if (s.reminderOn(Rk.expirySoon)) {
            final n = bucketBefore(dl, s.reminderDays(Rk.expirySoon));
            if (n != null) {
              add(build(
                  member: m,
                  kind: Rk.expirySoon,
                  body: renderTemplate(s.template(Rk.expirySoon), {...vars, 'days': '$dl'}),
                  dedupKey: 'exp:${sub.id}:$n'));
            }
          }
          final vl = sub.visitsLeft;
          final lowAt = s.reminderDays(Rk.visitsLow).isEmpty ? 2 : s.reminderDays(Rk.visitsLow).first;
          if (s.reminderOn(Rk.visitsLow) && vl != null && vl > 0 && vl <= lowAt) {
            add(build(
                member: m, kind: Rk.visitsLow, body: renderTemplate(s.template(Rk.visitsLow), vars), dedupKey: 'vl:${sub.id}'));
          }
        }
        if ((st == SubStatus.expired || st == SubStatus.exhausted) && !renewed) {
          final since = st == SubStatus.expired ? daysBetween(sub.end, day) : 1;
          if (s.reminderOn(Rk.expired) && since >= 1 && since <= 3) {
            add(build(
                member: m, kind: Rk.expired, body: renderTemplate(s.template(Rk.expired), vars), dedupKey: 'expd:${sub.id}'));
          }
          if (s.reminderOn(Rk.winback) && st == SubStatus.expired) {
            final n = bucketAfter(since, s.reminderDays(Rk.winback));
            if (n != null && since <= n + 2) {
              add(build(
                  member: m,
                  kind: Rk.winback,
                  body: renderTemplate(s.template(Rk.winback), {...vars, 'days': '$since'}),
                  dedupKey: 'wb:${sub.id}:$n'));
            }
          }
        }
        if (st == SubStatus.active && s.reminderOn(Rk.inactive)) {
          final n = s.reminderDays(Rk.inactive).isEmpty ? 10 : s.reminderDays(Rk.inactive).first;
          final lv = d.lastVisit(m.id);
          final last = lv == null ? sub.start : dateOnly(lv.time);
          final gap = daysBetween(last, day);
          if (gap >= n && sub.daysLeft(day) > 3) {
            add(build(
                member: m,
                kind: Rk.inactive,
                body: renderTemplate(s.template(Rk.inactive), {...vars, 'days': '$gap'}),
                dedupKey: 'in:${m.id}:${dayKey(last)}'));
          }
        }
        if (s.reminderOn(Rk.freezeEnd)) {
          final f = sub.freezeOn(day);
          if (f != null && daysBetween(day, f.end) == 0) {
            add(build(
                member: m, kind: Rk.freezeEnd, body: renderTemplate(s.template(Rk.freezeEnd), vars), dedupKey: 'fz:${f.id}'));
          }
        }
      }

      if (marketingOk && s.reminderOn(Rk.birthday) && m.isBirthday(day) && d.subsOf(m.id).isNotEmpty) {
        add(build(
            member: m,
            kind: Rk.birthday,
            body: renderTemplate(s.template(Rk.birthday), ctx.base(m)),
            dedupKey: 'bd:${m.id}:${day.year}'));
      }
    }

    // الأقساط: تذكيرات مالية تُرسل حتى لمن أوقف الرسائل التسويقية
    for (final inv in d.invoices.all) {
      if (inv.voided || inv.installments.isEmpty || inv.balance <= 0 || inv.memberId == null) continue;
      final m = d.members[inv.memberId];
      if (m == null || m.archived) continue;
      final st = inv.installmentStatus();
      for (var i = 0; i < st.length; i++) {
        final x = st[i];
        if (x.left <= 0.001) continue;
        final dd = daysBetween(day, x.inst.due);
        if (dd >= 0 && s.reminderOn(Rk.installmentDue)) {
          final n = bucketBefore(dd, s.reminderDays(Rk.installmentDue));
          if (n != null) {
            add(build(
                member: m,
                kind: Rk.installmentDue,
                body: renderTemplate(s.template(Rk.installmentDue), ctx.forInvoice(m, inv, amount: x.left, due: x.inst.due)),
                dedupKey: 'ind:${inv.id}:$i:$n',
                invoiceId: inv.id));
          }
        } else if (dd < 0 && s.reminderOn(Rk.installmentLate)) {
          final n = bucketAfter(-dd, s.reminderDays(Rk.installmentLate));
          if (n != null) {
            add(build(
                member: m,
                kind: Rk.installmentLate,
                body: renderTemplate(s.template(Rk.installmentLate), ctx.forInvoice(m, inv, amount: x.left, due: x.inst.due)),
                dedupKey: 'inl:${inv.id}:$i:$n',
                invoiceId: inv.id));
          }
        }
      }
    }

    // تذكير الحصص المحجوزة اليوم
    if (s.reminderOn(Rk.classReminder)) {
      final now = at ?? d.now();
      for (final b in d.bookings.all) {
        if (b.status != BookingStatus.booked || dateOnly(b.sessionStart) != day || b.sessionStart.isBefore(now)) continue;
        final m = d.members[b.memberId];
        final c = d.classes[b.classId];
        if (m == null || c == null || m.optOut) continue;
        add(build(
            member: m,
            kind: Rk.classReminder,
            body: renderTemplate(s.template(Rk.classReminder),
                {...ctx.base(m), 'class': c.name, 'time': hhmm(minutesOfDay(b.sessionStart))}),
            dedupKey: 'cl:${b.id}'));
      }
    }

    // ملخص يومي لصاحب النادي عن أمس
    if (s.reminderOn(Rk.ownerDaily) && d.has(Feature.ownerSummary) && looksLikePhone(s.ownerPhone)) {
      final y = addDays(day, -1);
      add(build(
          phone: s.ownerPhone,
          name: tr('صاحب النادي'),
          kind: Rk.ownerDaily,
          body: renderTemplate(s.template(Rk.ownerDaily),
              {'gym': s.gymName, 'date': dayKey(y), 'summary': Reports(d).dailySummaryText(y)}),
          dedupKey: 'own:${dayKey(y)}'));
    }
    return out;
  }

  /// تشغيل التذكيرات (مرة يومياً تلقائياً، أو يدوياً بـ force). يرجع عدد الرسائل الجديدة.
  Future<int> run({bool force = false, DateTime? at}) async {
    final now = at ?? d.now();
    final today = dayKey(now);
    if (!d.has(Feature.autoReminders)) return 0;
    if (!force) {
      if (!s.autoReminders) return 0;
      if (s.lastReminderRun == today) return 0;
      if (minutesOfDay(now) < s.sendFrom) return 0; // لا نبدأ قبل وقت الإرسال
    }
    final seen = d.dedupKeys;
    final fresh = <Message>[];
    for (final m in plan(now)) {
      if (m.dedupKey != null && (seen.contains(m.dedupKey) || fresh.any((x) => x.dedupKey == m.dedupKey))) continue;
      fresh.add(m);
    }
    s.lastReminderRun = today;
    await d.putAll(fresh, withSettings: true);
    return fresh.length;
  }

  // ---------------------------------------------------------------------------
  // رسائل الأحداث
  // ---------------------------------------------------------------------------

  Message? welcome(Member m, Subscription sub) {
    if (!s.reminderOn(Rk.welcome)) return null;
    return build(
        member: m, kind: Rk.welcome, body: renderTemplate(s.template(Rk.welcome), ctx.forSub(m, sub)), dedupKey: 'wel:${m.id}');
  }

  Message? receipt(Invoice inv, Payment p) {
    final m = d.members[inv.memberId];
    if (m == null || !s.reminderOn(Rk.receipt)) return null;
    return build(
        member: m,
        kind: Rk.receipt,
        body: renderTemplate(s.template(Rk.receipt), {...ctx.forInvoice(m, inv, amount: p.amount), 'balance': fmtMoney(inv.balance)}),
        dedupKey: 'rc:${p.id}',
        invoiceId: inv.id);
  }

  /// رسالة حرة لعضو أو حملة
  Message? custom(Member m, String text, {String kind = 'custom', Channel? channel}) =>
      build(member: m, kind: kind, body: renderTemplate(text, ctx.base(m)), channel: channel);

  /// نص الفاتورة لإرساله برسالة
  String invoiceText(Invoice inv) {
    final m = d.members[inv.memberId];
    final b = StringBuffer()
      ..writeln('🧾 ${s.gymName}')
      ..writeln(tr('فاتورة رقم {n}', {'n': inv.number}))
      ..writeln(dayKey(inv.date));
    if (m != null) b.writeln('${m.name} (#${m.code})');
    b.writeln();
    for (final i in inv.items) {
      b.writeln('• ${i.description}${i.qty != 1 ? ' ×${fmtNum(i.qty)}' : ''} = ${fmtMoney(i.total)}');
    }
    if (inv.discount > 0) b.writeln(tr('الخصم: {a}', {'a': fmtMoney(inv.discount)}));
    if (inv.tax > 0) b.writeln(tr('الضريبة: {a}', {'a': fmtMoney(inv.tax)}));
    b
      ..writeln(tr('الإجمالي: {a}', {'a': fmtMoney(inv.total)}))
      ..writeln(tr('المدفوع: {a}', {'a': fmtMoney(inv.paid)}));
    if (inv.balance > 0) {
      b.writeln(tr('المتبقي: {a}', {'a': fmtMoney(inv.balance)}));
      for (final x in inv.installmentStatus().where((x) => x.left > 0)) {
        b.writeln('  - ${dayKey(x.inst.due)}: ${fmtMoney(x.left)}');
      }
      final pay = ctx.payInfo(inv);
      if (pay.isNotEmpty) b.writeln(pay);
    }
    if (s.invoiceFooter.isNotEmpty) b..writeln()..writeln(s.invoiceFooter);
    return b.toString().trim();
  }

  Message? invoiceMessage(Invoice inv) {
    final m = d.members[inv.memberId];
    if (m == null) return null;
    return build(member: m, kind: 'invoice', body: invoiceText(inv), invoiceId: inv.id);
  }
}
