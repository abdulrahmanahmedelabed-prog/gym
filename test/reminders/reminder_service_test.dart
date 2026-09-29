import 'package:nadi_gym/reminders.dart';
import 'package:test/test.dart';

class FakeData implements ReminderDataSource {
  FakeData({this.subs = const [], this.invoices = const []});

  final List<SubscriptionDue> subs;
  final List<UnpaidInvoice> invoices;

  @override
  Future<List<SubscriptionDue>> subscriptionsEndingBetween(
          DateTime from, DateTime to) async =>
      subs
          .where((s) => !s.endDate.isBefore(from) && !s.endDate.isAfter(to))
          .toList();

  @override
  Future<List<UnpaidInvoice>> unpaidInvoicesDueBy(DateTime date) async =>
      invoices.where((i) => !i.dueDate.isAfter(date)).toList();
}

class FakeProvider implements MessageProvider {
  FakeProvider(this.channel, {this.fail = false});

  @override
  final ReminderChannel channel;
  final bool fail;
  final sent = <Reminder>[];

  @override
  String get name => 'fake ${channel.name}';

  @override
  Future<SendResult> send(Reminder reminder) async {
    if (fail) return const SendResult.failed('down');
    sent.add(reminder);
    return const SendResult.sent(providerMessageId: 'x');
  }
}

final today = DateTime.utc(2026, 10, 1, 9);

SubscriptionDue sub(String id, int daysLeft,
        {String? phone = '0599123456', bool optedOut = false}) =>
    SubscriptionDue(
      subscriptionId: id,
      memberId: 'm$id',
      memberName: 'أحمد',
      phone: phone,
      planName: 'شهري',
      endDate: DateTime.utc(2026, 10, 1).add(Duration(days: daysLeft)),
      optedOut: optedOut,
    );

UnpaidInvoice invoice(String id, int daysOverdue, {double balance = 50}) =>
    UnpaidInvoice(
      invoiceId: id,
      invoiceNumber: 'INV-$id',
      memberId: 'm$id',
      memberName: 'سارة',
      phone: '0599000111',
      balance: balance,
      dueDate: DateTime.utc(2026, 10, 1).subtract(Duration(days: daysOverdue)),
    );

ReminderService service(FakeData data, List<MessageProvider> providers,
        {ReminderLog? log}) =>
    ReminderService(
      dataSource: data,
      providers: providers,
      log: log ?? InMemoryReminderLog(),
      settings: const ReminderSettings(clubName: 'نادي القوة'),
    );

void main() {
  group('collectDue', () {
    test('picks the right step for each subscription', () async {
      final data = FakeData(subs: [
        sub('a', 7),
        sub('b', 5), // between steps: the 7-day step is still due
        sub('c', 3),
        sub('d', 1),
        sub('e', 0),
        sub('f', -3),
        sub('g', 10), // too early
        sub('h', -20), // too late
        sub('i', 3, optedOut: true),
      ]);
      final due = await service(data, []).collectDue(today);
      expect({
        for (final r in due) r.referenceId: '${r.kind.name} ${r.stage}'
      }, {
        'a': 'subscriptionExpiring before:7',
        'b': 'subscriptionExpiring before:7',
        'c': 'subscriptionExpiring before:3',
        'd': 'subscriptionExpiring before:1',
        'e': 'subscriptionExpiresToday on',
        'f': 'subscriptionExpired after:3',
      });
    });

    test('fills the message and template params', () async {
      final due =
          await service(FakeData(subs: [sub('a', 3)]), []).collectDue(today);
      final r = due.single;
      expect(r.phone, '970599123456');
      expect(r.message, contains('أحمد'));
      expect(r.message, contains('نادي القوة'));
      expect(r.message, contains('2026-10-04'));
      expect(r.message, contains('3 يوم'));
      expect(r.templateParams, ['أحمد', 'شهري', '2026-10-04', '3']);
    });

    test('unpaid invoices follow the overdue steps with catch-up', () async {
      final data = FakeData(invoices: [
        invoice('a', 0), // not overdue yet
        invoice('b', 1),
        invoice('c', 8), // 7-day step, one day late
        invoice('d', 14),
        invoice('e', 30), // stopped reminding
        invoice('f', 7, balance: 0),
      ]);
      final due = await service(data, []).collectDue(today);
      expect({
        for (final r in due) r.referenceId: r.stage
      }, {
        'b': 'overdue:1',
        'c': 'overdue:7',
        'd': 'overdue:14',
      });
      expect(due.first.message, contains('INV-b'));
      expect(due.first.message, contains('50.00'));
    });
  });

  group('run', () {
    test('sends each step once', () async {
      final wa = FakeProvider(ReminderChannel.whatsapp);
      final log = InMemoryReminderLog();
      final s = service(FakeData(subs: [sub('a', 3)]), [wa], log: log);

      final first = await s.run(today);
      expect(first.single.status, ReminderOutcomeStatus.sent);
      expect(first.single.channel, ReminderChannel.whatsapp);

      final again = await s.run(today.add(const Duration(hours: 5)));
      expect(again.single.status, ReminderOutcomeStatus.alreadySent);
      expect(wa.sent, hasLength(1));
    });

    test('falls back to SMS when WhatsApp fails', () async {
      final wa = FakeProvider(ReminderChannel.whatsapp, fail: true);
      final sms = FakeProvider(ReminderChannel.sms);
      final out =
          await service(FakeData(subs: [sub('a', 1)]), [wa, sms]).run(today);
      expect(out.single.status, ReminderOutcomeStatus.sent);
      expect(out.single.channel, ReminderChannel.sms);
      expect(out.single.errors, {ReminderChannel.whatsapp: 'down'});
    });

    test('reports failure when every channel fails, and retries next run',
        () async {
      final wa = FakeProvider(ReminderChannel.whatsapp, fail: true);
      final log = InMemoryReminderLog();
      final s = service(FakeData(subs: [sub('a', 1)]), [wa], log: log);
      expect((await s.run(today)).single.status, ReminderOutcomeStatus.failed);
      expect(log.entries, isEmpty);
    });

    test('skips members without a phone number', () async {
      final wa = FakeProvider(ReminderChannel.whatsapp);
      final out =
          await service(FakeData(subs: [sub('a', 1, phone: null)]), [wa])
              .run(today);
      expect(out.single.status, ReminderOutcomeStatus.skipped);
      expect(wa.sent, isEmpty);
    });

    test('manual wa.me links are logged only after staff confirm', () async {
      final log = InMemoryReminderLog();
      final s = service(
          FakeData(subs: [sub('a', 1)]), [const WhatsAppLinkProvider()],
          log: log);
      final out = (await s.run(today)).single;
      expect(out.status, ReminderOutcomeStatus.needsManualSend);
      expect(out.result!.link, startsWith('https://wa.me/970599123456?text='));
      expect(log.entries, isEmpty);

      await s.markManuallySent(out.reminder, ReminderChannel.whatsapp, today);
      expect((await s.run(today)).single.status,
          ReminderOutcomeStatus.alreadySent);
    });
  });
}
