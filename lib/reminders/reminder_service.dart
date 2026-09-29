import 'message_provider.dart';
import 'phone_number.dart';
import 'reminder_data_source.dart';
import 'reminder_log.dart';
import 'reminder_models.dart';
import 'reminder_templates.dart';

/// When and how reminders go out. Defaults match what most clubs do.
class ReminderSettings {
  const ReminderSettings({
    required this.clubName,
    this.currency = '₪',
    this.countryCode = '970',
    this.daysBeforeExpiry = const [7, 3, 1],
    this.remindOnExpiryDay = true,
    this.daysAfterExpiry = const [3],
    this.invoiceOverdueDays = const [1, 7, 14],
    this.catchUpDays = 3,
    this.channelOrder = const [ReminderChannel.whatsapp, ReminderChannel.sms],
    this.templates = ReminderTemplates.arabic,
    this.formatDate = _isoDate,
  });

  final String clubName;
  final String currency;

  /// Added to local numbers that start with 0.
  final String countryCode;

  /// Send "ends in N days" at each of these offsets.
  final List<int> daysBeforeExpiry;
  final bool remindOnExpiryDay;

  /// Send "your subscription ended" this many days after the end date.
  final List<int> daysAfterExpiry;

  /// Send "invoice unpaid" this many days after the due date.
  final List<int> invoiceOverdueDays;

  /// If the service did not run on the exact day of an after-date step
  /// (device off, no internet), it still sends that step up to this many
  /// days late instead of skipping it.
  final int catchUpDays;

  /// Channels to try in order. When one fails the next is tried, so
  /// WhatsApp first with SMS as fallback is the default.
  final List<ReminderChannel> channelOrder;

  final ReminderTemplates templates;
  final String Function(DateTime) formatDate;
}

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime _day(DateTime d) => DateTime.utc(d.year, d.month, d.day);

int _daysBetween(DateTime from, DateTime to) =>
    _day(to).difference(_day(from)).inDays;

/// Builds subscription-expiry and unpaid-invoice reminders and delivers them
/// through the configured [MessageProvider]s.
///
/// Call [run] once or more a day (on app start, from a background task, or
/// from a server cron). Each schedule step is sent at most once per
/// subscription or invoice, tracked in the [ReminderLog].
class ReminderService {
  ReminderService({
    required this.dataSource,
    required List<MessageProvider> providers,
    required this.log,
    required this.settings,
  }) : providers = {for (final p in providers) p.channel: p};

  final ReminderDataSource dataSource;
  final Map<ReminderChannel, MessageProvider> providers;
  final ReminderLog log;
  final ReminderSettings settings;

  /// Every reminder due on [now]'s date, whether or not it was sent before.
  Future<List<Reminder>> collectDue(DateTime now) async {
    final today = _day(now);
    final reminders = <Reminder>[];

    final before = settings.daysBeforeExpiry.where((d) => d > 0).toList()
      ..sort();
    final after = settings.daysAfterExpiry.where((d) => d > 0).toList()..sort();
    final maxBefore = before.isEmpty ? 0 : before.last;
    final maxAfter = after.isEmpty ? 0 : after.last + settings.catchUpDays;
    final subs = await dataSource.subscriptionsEndingBetween(
      today.subtract(Duration(days: maxAfter)),
      today.add(Duration(days: maxBefore)),
    );
    for (final s in subs) {
      if (s.optedOut) continue;
      final daysLeft = _daysBetween(today, s.endDate);
      ReminderKind? kind;
      String? stage;
      if (daysLeft > 0) {
        // Tightest step that has been reached: with steps 7,3,1 and 5 days
        // left, the "7 days" step is due (once), so a missed day never
        // loses a reminder.
        final step = before.where((d) => d >= daysLeft).firstOrNull;
        if (step != null) {
          kind = ReminderKind.subscriptionExpiring;
          stage = 'before:$step';
        }
      } else if (daysLeft == 0) {
        if (settings.remindOnExpiryDay) {
          kind = ReminderKind.subscriptionExpiresToday;
          stage = 'on';
        }
      } else {
        final step = _latestStep(after, -daysLeft);
        if (step != null) {
          kind = ReminderKind.subscriptionExpired;
          stage = 'after:$step';
        }
      }
      if (kind == null) continue;
      final date = settings.formatDate(s.endDate);
      final values = {
        'name': s.memberName,
        'club': settings.clubName,
        'plan': s.planName,
        'date': date,
        'days': '$daysLeft',
        'amount': s.renewalPrice?.toStringAsFixed(2) ?? '',
        'currency': settings.currency,
      };
      reminders.add(_build(
        kind: kind,
        referenceId: s.subscriptionId,
        stage: stage!,
        memberId: s.memberId,
        memberName: s.memberName,
        phone: s.phone,
        values: values,
        params: kind == ReminderKind.subscriptionExpiring
            ? [s.memberName, s.planName, date, '$daysLeft']
            : [s.memberName, s.planName, date],
      ));
    }

    final overdueSteps =
        settings.invoiceOverdueDays.where((d) => d >= 0).toList()..sort();
    if (overdueSteps.isNotEmpty) {
      final invoices = await dataSource.unpaidInvoicesDueBy(
          today.subtract(Duration(days: overdueSteps.first)));
      for (final inv in invoices) {
        if (inv.optedOut || inv.balance <= 0) continue;
        final step =
            _latestStep(overdueSteps, _daysBetween(inv.dueDate, today));
        if (step == null) continue;
        final date = settings.formatDate(inv.dueDate);
        final amount = inv.balance.toStringAsFixed(2);
        reminders.add(_build(
          kind: ReminderKind.invoiceUnpaid,
          referenceId: inv.invoiceId,
          stage: 'overdue:$step',
          memberId: inv.memberId,
          memberName: inv.memberName,
          phone: inv.phone,
          values: {
            'name': inv.memberName,
            'club': settings.clubName,
            'invoice': inv.invoiceNumber,
            'amount': amount,
            'currency': settings.currency,
            'date': date,
          },
          params: [inv.memberName, inv.invoiceNumber, amount, date],
        ));
      }
    }
    return reminders;
  }

  /// Sends every due reminder that has not been sent yet.
  Future<List<ReminderOutcome>> run(DateTime now) async {
    final outcomes = <ReminderOutcome>[];
    for (final r in await collectDue(now)) {
      outcomes.add(await send(r, now));
    }
    return outcomes;
  }

  /// Sends one reminder, trying each channel in [ReminderSettings.channelOrder].
  Future<ReminderOutcome> send(Reminder r, DateTime now) async {
    if (await log.wasSent(r.key)) {
      return ReminderOutcome(
          reminder: r, status: ReminderOutcomeStatus.alreadySent);
    }
    if (r.phone.isEmpty) {
      return ReminderOutcome(
          reminder: r, status: ReminderOutcomeStatus.skipped);
    }
    final errors = <ReminderChannel, String>{};
    for (final channel in settings.channelOrder) {
      final provider = providers[channel];
      if (provider == null) continue;
      SendResult result;
      try {
        result = await provider.send(r);
      } catch (e) {
        result = SendResult.failed('$e');
      }
      switch (result.status) {
        case SendStatus.sent:
          await log.markSent(r.key, channel, now,
              providerMessageId: result.providerMessageId);
          return ReminderOutcome(
            reminder: r,
            status: ReminderOutcomeStatus.sent,
            channel: channel,
            result: result,
            errors: errors,
          );
        case SendStatus.needsManualSend:
          // Not logged yet: the app calls markManuallySent once the
          // staff member actually pressed send.
          return ReminderOutcome(
            reminder: r,
            status: ReminderOutcomeStatus.needsManualSend,
            channel: channel,
            result: result,
            errors: errors,
          );
        case SendStatus.failed:
          errors[channel] = result.error ?? 'failed';
      }
    }
    return ReminderOutcome(
      reminder: r,
      status: errors.isEmpty
          ? ReminderOutcomeStatus.skipped
          : ReminderOutcomeStatus.failed,
      errors: errors,
    );
  }

  /// Records a reminder that a staff member sent by hand (e.g. from a
  /// `wa.me` link), so it is not offered again.
  Future<void> markManuallySent(
          Reminder r, ReminderChannel channel, DateTime at) =>
      log.markSent(r.key, channel, at);

  Reminder _build({
    required ReminderKind kind,
    required String referenceId,
    required String stage,
    required String memberId,
    required String memberName,
    required String? phone,
    required Map<String, String> values,
    required List<String> params,
  }) =>
      Reminder(
        kind: kind,
        referenceId: referenceId,
        stage: stage,
        memberId: memberId,
        memberName: memberName,
        phone: normalizePhone(phone, countryCode: settings.countryCode) ?? '',
        message: settings.templates.render(kind, values),
        templateParams: params,
      );

  /// Latest step already reached, if it was reached no more than
  /// [ReminderSettings.catchUpDays] ago.
  int? _latestStep(List<int> sortedSteps, int elapsed) {
    final step = sortedSteps.where((d) => d <= elapsed).lastOrNull;
    if (step == null ||
        elapsed - step >= settings.catchUpDays.clamp(1, 1 << 30)) return null;
    return step;
  }
}
