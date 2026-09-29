import 'dart:convert';

import 'package:http/http.dart' as http;

import '../message_provider.dart';
import '../reminder_models.dart';

/// Sends SMS through Twilio.
class TwilioSmsProvider implements MessageProvider {
  TwilioSmsProvider({
    required this.accountSid,
    required this.authToken,
    required this.from,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String accountSid;
  final String authToken;

  /// Twilio number or alphanumeric sender id.
  final String from;
  final http.Client _client;

  @override
  ReminderChannel get channel => ReminderChannel.sms;

  @override
  String get name => 'Twilio SMS';

  @override
  Future<SendResult> send(Reminder reminder) async {
    final res = await _client.post(
      Uri.parse(
          'https://api.twilio.com/2010-04-01/Accounts/$accountSid/Messages.json'),
      headers: {
        'Authorization':
            'Basic ${base64Encode(utf8.encode('$accountSid:$authToken'))}'
      },
      body: {
        'To': '+${reminder.phone}',
        'From': from,
        'Body': reminder.message
      },
    );
    Map<String, dynamic>? json;
    try {
      json = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}
    if (res.statusCode < 200 || res.statusCode >= 300) {
      return SendResult.failed(
          'Twilio ${res.statusCode}: ${json?['message'] ?? res.body}');
    }
    return SendResult.sent(providerMessageId: json?['sid'] as String?);
  }
}
