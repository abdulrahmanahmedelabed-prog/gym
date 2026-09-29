import 'reminder_models.dart';

/// Remembers which reminders were already delivered, so running the
/// service again (after a crash, twice in one day, on two devices sharing
/// one backend) never sends the same reminder twice.
abstract class ReminderLog {
  Future<bool> wasSent(String key);

  Future<void> markSent(String key, ReminderChannel channel, DateTime at,
      {String? providerMessageId});
}

class InMemoryReminderLog implements ReminderLog {
  final Map<String, ReminderChannel> _sent = {};

  Map<String, ReminderChannel> get entries => Map.unmodifiable(_sent);

  @override
  Future<bool> wasSent(String key) async => _sent.containsKey(key);

  @override
  Future<void> markSent(String key, ReminderChannel channel, DateTime at,
      {String? providerMessageId}) async {
    _sent[key] = channel;
  }
}
