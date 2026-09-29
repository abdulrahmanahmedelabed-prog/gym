/// Data types shared by the reminder service and its providers.
library;

/// How a reminder reaches the member.
enum ReminderChannel { whatsapp, sms }

/// Why a reminder is sent.
enum ReminderKind {
  /// The subscription ends in a few days.
  subscriptionExpiring,

  /// The subscription ends today.
  subscriptionExpiresToday,

  /// The subscription already ended and was not renewed.
  subscriptionExpired,

  /// An invoice is past its due date and still has an unpaid balance.
  invoiceUnpaid,
}

/// A member subscription that is close to (or past) its end date.
class SubscriptionDue {
  const SubscriptionDue({
    required this.subscriptionId,
    required this.memberId,
    required this.memberName,
    required this.phone,
    required this.planName,
    required this.endDate,
    this.renewalPrice,
    this.optedOut = false,
  });

  final String subscriptionId;
  final String memberId;
  final String memberName;
  final String? phone;
  final String planName;
  final DateTime endDate;
  final double? renewalPrice;

  /// The member asked not to receive reminders.
  final bool optedOut;
}

/// An invoice with an unpaid balance.
class UnpaidInvoice {
  const UnpaidInvoice({
    required this.invoiceId,
    required this.invoiceNumber,
    required this.memberId,
    required this.memberName,
    required this.phone,
    required this.balance,
    required this.dueDate,
    this.optedOut = false,
  });

  final String invoiceId;
  final String invoiceNumber;
  final String memberId;
  final String memberName;
  final String? phone;
  final double balance;
  final DateTime dueDate;
  final bool optedOut;
}

/// One reminder ready to send.
class Reminder {
  const Reminder({
    required this.kind,
    required this.referenceId,
    required this.stage,
    required this.memberId,
    required this.memberName,
    required this.phone,
    required this.message,
    this.templateParams = const [],
  });

  final ReminderKind kind;

  /// The subscription or invoice id this reminder is about.
  final String referenceId;

  /// Which step of the schedule this is, e.g. `before:3` or `overdue:7`.
  /// Together with [kind] and [referenceId] it makes the reminder unique, so
  /// the same step is never sent twice even if the service runs many times a day.
  final String stage;

  final String memberId;
  final String memberName;

  /// Phone number in international form, digits only (e.g. `970599123456`).
  final String phone;

  /// Full message text for providers that send free text.
  final String message;

  /// Ordered values for providers that send pre-approved templates
  /// (WhatsApp Business templates, some SMS gateways).
  final List<String> templateParams;

  String get key => '${kind.name}:$referenceId:$stage';
}

/// Result of one provider trying to deliver one message.
class SendResult {
  const SendResult._(this.status,
      {this.providerMessageId, this.error, this.link});

  const SendResult.sent({String? providerMessageId})
      : this._(SendStatus.sent, providerMessageId: providerMessageId);

  /// The provider prepared the message but a person has to press send
  /// (the free `wa.me` link flow).
  const SendResult.needsManualSend(String link)
      : this._(SendStatus.needsManualSend, link: link);

  const SendResult.failed(String error)
      : this._(SendStatus.failed, error: error);

  final SendStatus status;
  final String? providerMessageId;
  final String? error;
  final String? link;

  bool get isSent => status == SendStatus.sent;
}

enum SendStatus { sent, needsManualSend, failed }

/// What happened to one reminder after trying every channel.
class ReminderOutcome {
  const ReminderOutcome({
    required this.reminder,
    required this.status,
    this.channel,
    this.result,
    this.errors = const {},
  });

  final Reminder reminder;
  final ReminderOutcomeStatus status;

  /// The channel that delivered (or prepared) the message.
  final ReminderChannel? channel;
  final SendResult? result;

  /// Errors from channels that were tried and failed.
  final Map<ReminderChannel, String> errors;
}

enum ReminderOutcomeStatus {
  sent,
  needsManualSend,
  failed,

  /// Already sent earlier, so skipped.
  alreadySent,

  /// Not sent because the member has no usable phone number or no
  /// provider is configured.
  skipped,
}
