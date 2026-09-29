import 'reminder_models.dart';

/// Where the reminder service reads subscriptions and invoices from.
/// The app implements this over its own database or API.
abstract class ReminderDataSource {
  /// Subscriptions whose end date falls within [from]..[to] (inclusive dates)
  /// and that have not been renewed.
  Future<List<SubscriptionDue>> subscriptionsEndingBetween(
      DateTime from, DateTime to);

  /// Invoices with an unpaid balance whose due date is on or before [date].
  Future<List<UnpaidInvoice>> unpaidInvoicesDueBy(DateTime date);
}
