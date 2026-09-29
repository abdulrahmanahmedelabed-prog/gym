import '../message_provider.dart';
import '../reminder_models.dart';

/// Free WhatsApp option: builds a `wa.me` link with the message already
/// typed. The app opens it and a staff member presses send. Fully automatic
/// sending needs a paid provider such as [WhatsAppCloudProvider].
class WhatsAppLinkProvider implements MessageProvider {
  const WhatsAppLinkProvider();

  @override
  ReminderChannel get channel => ReminderChannel.whatsapp;

  @override
  String get name => 'WhatsApp (manual link)';

  static String linkFor(String phone, String text) =>
      'https://wa.me/$phone?text=${Uri.encodeComponent(text)}';

  @override
  Future<SendResult> send(Reminder reminder) async =>
      SendResult.needsManualSend(linkFor(reminder.phone, reminder.message));
}
