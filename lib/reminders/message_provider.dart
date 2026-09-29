import 'reminder_models.dart';

/// Sends a message over one channel. Implement this to plug in any SMS
/// gateway or WhatsApp service; the reminder service only talks to this
/// interface.
abstract class MessageProvider {
  ReminderChannel get channel;

  /// Human-readable name, shown in settings and logs.
  String get name;

  /// [reminder.phone] is already normalized to international digits.
  Future<SendResult> send(Reminder reminder);
}
