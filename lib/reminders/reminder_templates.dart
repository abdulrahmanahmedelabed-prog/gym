import 'reminder_models.dart';

/// Message texts for each reminder kind. Placeholders in `{braces}` are
/// filled by [ReminderTemplates.render]:
///
/// `{name}` `{club}` `{plan}` `{date}` `{days}` `{amount}` `{invoice}` `{currency}`
class ReminderTemplates {
  const ReminderTemplates(this.texts);

  final Map<ReminderKind, String> texts;

  static const arabic = ReminderTemplates({
    ReminderKind.subscriptionExpiring:
        'مرحباً {name}،\nنذكّرك بأن اشتراكك ({plan}) في {club} ينتهي بعد {days} يوم بتاريخ {date}.\nجدّد الآن لتستمر في التمرين دون انقطاع 💪',
    ReminderKind.subscriptionExpiresToday:
        'مرحباً {name}،\nاشتراكك ({plan}) في {club} ينتهي اليوم {date}.\nنسعد بتجديده في أي وقت 💪',
    ReminderKind.subscriptionExpired:
        'مرحباً {name}،\nانتهى اشتراكك ({plan}) في {club} بتاريخ {date}.\nاشتقنا لك! جدّد اشتراكك وعُد للتمرين 💪',
    ReminderKind.invoiceUnpaid:
        'مرحباً {name}،\nنود تذكيرك بأن الفاتورة رقم {invoice} لدى {club} عليها مبلغ مستحق {amount} {currency} منذ {date}.\nشكراً لتعاونك 🌷',
  });

  static const english = ReminderTemplates({
    ReminderKind.subscriptionExpiring:
        'Hi {name},\nYour {plan} membership at {club} ends in {days} days, on {date}.\nRenew now to keep training without a break 💪',
    ReminderKind.subscriptionExpiresToday:
        'Hi {name},\nYour {plan} membership at {club} ends today, {date}.\nRenew any time 💪',
    ReminderKind.subscriptionExpired:
        'Hi {name},\nYour {plan} membership at {club} ended on {date}.\nWe miss you! Renew and come back 💪',
    ReminderKind.invoiceUnpaid:
        'Hi {name},\nA friendly reminder that invoice {invoice} at {club} has {amount} {currency} due since {date}.\nThank you 🌷',
  });

  String render(ReminderKind kind, Map<String, String> values) {
    var text = texts[kind] ?? arabic.texts[kind]!;
    values.forEach((k, v) => text = text.replaceAll('{$k}', v));
    return text;
  }
}
