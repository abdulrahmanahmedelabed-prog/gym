import 'dart:convert';

import 'package:http/http.dart' as http;

import '../message_provider.dart';
import '../reminder_models.dart';

/// Sends SMS through any gateway with a simple HTTP API, which covers most
/// local SMS companies. Configure it with the gateway's URL and use
/// `{phone}` and `{message}` placeholders. Values are URL-encoded in
/// [urlTemplate], and in [bodyTemplate] they are JSON-escaped when the
/// Content-Type header is JSON and form-encoded otherwise.
///
/// ```dart
/// HttpSmsGatewayProvider(
///   urlTemplate: 'https://sms.example.com/send?user=club&pass=secret&to={phone}&text={message}',
///   successPattern: RegExp('^OK'),
/// )
/// ```
class HttpSmsGatewayProvider implements MessageProvider {
  HttpSmsGatewayProvider({
    required this.urlTemplate,
    this.bodyTemplate,
    this.headers = const {},
    this.successPattern,
    this.name = 'SMS gateway',
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String urlTemplate;

  /// When set, the request is a POST with this body; otherwise a GET.
  final String? bodyTemplate;
  final Map<String, String> headers;

  /// Some gateways answer 200 even on errors; when set, the response body
  /// must match this for the message to count as sent.
  final Pattern? successPattern;

  @override
  final String name;

  final http.Client _client;

  @override
  ReminderChannel get channel => ReminderChannel.sms;

  String Function(String) get _bodyEncoder {
    final type = headers.entries
        .where((e) => e.key.toLowerCase() == 'content-type')
        .map((e) => e.value.toLowerCase())
        .firstOrNull;
    if (type != null && type.contains('json')) {
      return (v) {
        final e = jsonEncode(v);
        return e.substring(1, e.length - 1);
      };
    }
    return Uri.encodeQueryComponent;
  }

  @override
  Future<SendResult> send(Reminder reminder) async {
    String fill(String t, String Function(String) enc) => t
        .replaceAll('{phone}', enc(reminder.phone))
        .replaceAll('{message}', enc(reminder.message));
    final url = Uri.parse(fill(urlTemplate, Uri.encodeQueryComponent));
    final res = bodyTemplate == null
        ? await _client.get(url, headers: headers)
        : await _client.post(url,
            headers: headers, body: fill(bodyTemplate!, _bodyEncoder));
    final ok = res.statusCode >= 200 &&
        res.statusCode < 300 &&
        (successPattern == null ||
            successPattern!.allMatches(res.body).isNotEmpty);
    return ok
        ? const SendResult.sent()
        : SendResult.failed('SMS gateway ${res.statusCode}: ${res.body}');
  }
}
