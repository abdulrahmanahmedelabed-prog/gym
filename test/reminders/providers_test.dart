import 'dart:convert';

import 'package:nadi_gym/reminders.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const reminder = Reminder(
  kind: ReminderKind.invoiceUnpaid,
  referenceId: 'inv1',
  stage: 'overdue:1',
  memberId: 'm1',
  memberName: 'سارة',
  phone: '970599000111',
  message: 'مرحباً سارة\n"50.00" مستحق',
  templateParams: ['سارة', 'INV-1', '50.00', '2026-09-30'],
);

void main() {
  group('WhatsAppCloudProvider', () {
    test('sends a template with ordered params', () async {
      late http.Request req;
      final p = WhatsAppCloudProvider(
        phoneNumberId: '123',
        accessToken: 'tok',
        templateNames: {ReminderKind.invoiceUnpaid: 'invoice_due'},
        client: MockClient((r) async {
          req = r;
          return http.Response('{"messages":[{"id":"wamid.1"}]}', 200);
        }),
      );
      final res = await p.send(reminder);
      expect(res.isSent, isTrue);
      expect(res.providerMessageId, 'wamid.1');
      expect(
          req.url.toString(), 'https://graph.facebook.com/v21.0/123/messages');
      expect(req.headers['Authorization'], 'Bearer tok');
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      expect(body['to'], '970599000111');
      expect(body['template']['name'], 'invoice_due');
      expect(
        (body['template']['components'][0]['parameters'] as List)
            .map((p) => p['text']),
        ['سارة', 'INV-1', '50.00', '2026-09-30'],
      );
    });

    test('falls back to free text without a template and reports API errors',
        () async {
      late Map<String, dynamic> body;
      final p = WhatsAppCloudProvider(
        phoneNumberId: '123',
        accessToken: 'tok',
        client: MockClient((r) async {
          body = jsonDecode(r.body) as Map<String, dynamic>;
          return http.Response(
              '{"error":{"message":"Re-engagement message"}}', 400);
        }),
      );
      final res = await p.send(reminder);
      expect(body['text']['body'], reminder.message);
      expect(res.status, SendStatus.failed);
      expect(res.error, contains('Re-engagement message'));
    });
  });

  test('TwilioSmsProvider posts the form with basic auth', () async {
    late http.Request req;
    final p = TwilioSmsProvider(
      accountSid: 'AC1',
      authToken: 'secret',
      from: 'GymClub',
      client: MockClient((r) async {
        req = r;
        return http.Response('{"sid":"SM1"}', 201);
      }),
    );
    final res = await p.send(reminder);
    expect(res.providerMessageId, 'SM1');
    expect(req.url.path, '/2010-04-01/Accounts/AC1/Messages.json');
    expect(req.headers['Authorization'],
        'Basic ${base64Encode(utf8.encode('AC1:secret'))}');
    expect(req.bodyFields,
        {'To': '+970599000111', 'From': 'GymClub', 'Body': reminder.message});
  });

  group('HttpSmsGatewayProvider', () {
    test('GET with URL-encoded placeholders and a success pattern', () async {
      late Uri url;
      final p = HttpSmsGatewayProvider(
        urlTemplate: 'https://sms.example.com/send?to={phone}&text={message}',
        successPattern: RegExp('^OK'),
        client: MockClient((r) async {
          url = r.url;
          return http.Response('ERR 22', 200);
        }),
      );
      final res = await p.send(reminder);
      expect(url.queryParameters['text'], reminder.message);
      expect(url.queryParameters['to'], '970599000111');
      expect(res.status, SendStatus.failed);
    });

    test('POST with a JSON body escapes the message', () async {
      late String sentBody;
      final p = HttpSmsGatewayProvider(
        urlTemplate: 'https://sms.example.com/api',
        bodyTemplate: '{"to":"{phone}","text":"{message}"}',
        headers: {'Content-Type': 'application/json'},
        client: MockClient((r) async {
          sentBody = r.body;
          return http.Response('{"ok":true}', 200);
        }),
      );
      expect((await p.send(reminder)).isSent, isTrue);
      expect(jsonDecode(sentBody),
          {'to': '970599000111', 'text': reminder.message});
    });
  });

  test('WhatsAppLinkProvider returns a wa.me link for manual sending',
      () async {
    final res = await const WhatsAppLinkProvider().send(reminder);
    expect(res.status, SendStatus.needsManualSend);
    expect(Uri.parse(res.link!).queryParameters['text'], reminder.message);
  });
}
