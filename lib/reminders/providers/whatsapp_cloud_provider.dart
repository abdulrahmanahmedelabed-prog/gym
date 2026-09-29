import 'dart:convert';

import 'package:http/http.dart' as http;

import '../message_provider.dart';
import '../reminder_models.dart';

/// Sends automatically through Meta's WhatsApp Business Cloud API.
///
/// WhatsApp only allows free text within 24 hours of the member's last
/// message, so reminders should use approved templates: set
/// [templateNames] per reminder kind. Each template's body receives the
/// reminder's [Reminder.templateParams] as {{1}}, {{2}}, ... in order:
///
/// - subscription expiring: name, plan, end date, days left
/// - expires today / expired: name, plan, end date
/// - invoice unpaid: name, invoice number, amount, due date
///
/// Kinds without a template are sent as free text.
class WhatsAppCloudProvider implements MessageProvider {
  WhatsAppCloudProvider({
    required this.phoneNumberId,
    required this.accessToken,
    this.templateNames = const {},
    this.languageCode = 'ar',
    this.apiVersion = 'v21.0',
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String phoneNumberId;
  final String accessToken;
  final Map<ReminderKind, String> templateNames;
  final String languageCode;
  final String apiVersion;
  final http.Client _client;

  @override
  ReminderChannel get channel => ReminderChannel.whatsapp;

  @override
  String get name => 'WhatsApp Cloud API';

  @override
  Future<SendResult> send(Reminder reminder) async {
    final template = templateNames[reminder.kind];
    final body = <String, Object>{
      'messaging_product': 'whatsapp',
      'to': reminder.phone,
      if (template == null) ...{
        'type': 'text',
        'text': {'body': reminder.message},
      } else ...{
        'type': 'template',
        'template': {
          'name': template,
          'language': {'code': languageCode},
          'components': [
            {
              'type': 'body',
              'parameters': [
                for (final p in reminder.templateParams)
                  {'type': 'text', 'text': p},
              ],
            },
          ],
        },
      },
    };
    final res = await _client.post(
      Uri.parse(
          'https://graph.facebook.com/$apiVersion/$phoneNumberId/messages'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json'
      },
      body: jsonEncode(body),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      return SendResult.failed(
          'WhatsApp ${res.statusCode}: ${_errorMessage(res.body)}');
    }
    final messages =
        (jsonDecode(res.body) as Map<String, dynamic>)['messages'] as List?;
    final id = messages != null && messages.isNotEmpty
        ? (messages.first as Map)['id'] as String?
        : null;
    return SendResult.sent(providerMessageId: id);
  }

  static String _errorMessage(String body) {
    try {
      final err = (jsonDecode(body) as Map<String, dynamic>)['error']
          as Map<String, dynamic>?;
      return err?['message'] as String? ?? body;
    } catch (_) {
      return body;
    }
  }
}
