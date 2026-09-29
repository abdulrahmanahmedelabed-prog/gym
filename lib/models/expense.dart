import 'base.dart';
import 'billing.dart';

/// بند مصروفات (إيجار، رواتب، كهرباء، صيانة...)
class ExpenseCategory implements Entity {
  @override
  final String id;
  String name;
  int colorValue;
  bool active;
  int sort;

  ExpenseCategory({required this.id, required this.name, this.colorValue = 0xFF757575, this.active = true, this.sort = 0});

  @override
  Map<String, Object?> toMap() =>
      compact({'id': id, 'name': name, 'color': colorValue, 'active': active, 'sort': sort});

  factory ExpenseCategory.fromMap(Map<String, Object?> m) => ExpenseCategory(
        id: asStr(m['id']),
        name: asStr(m['name']),
        colorValue: asInt(m['color'], 0xFF757575),
        active: asBool(m['active'], true),
        sort: asInt(m['sort']),
      );
}

/// بنود افتراضية عند أول تشغيل
const defaultExpenseCategories = ['إيجار', 'رواتب', 'كهرباء ومياه', 'صيانة', 'تسويق', 'مشتريات المتجر', 'أخرى'];

class Expense implements Entity {
  @override
  final String id;
  final String number;
  DateTime date;
  String categoryId;
  double amount;
  PayMethod method;
  String? payee; // المستفيد: المؤجر، شركة الكهرباء...
  String? staffId; // لصرف راتب أو سلفة لموظف
  String? reference; // رقم الإيصال أو التحويل
  String? note;
  String? attachment; // صورة الإيصال (مسار أو base64 مصغّر)
  bool voided;
  String? voidReason;
  final DateTime createdAt;
  String? by;

  Expense({
    required this.id,
    required this.number,
    required this.date,
    required this.categoryId,
    required this.amount,
    this.method = PayMethod.cash,
    this.payee,
    this.staffId,
    this.reference,
    this.note,
    this.attachment,
    this.voided = false,
    this.voidReason,
    required this.createdAt,
    this.by,
  });

  /// المبلغ المحتسب في التقارير
  double get effective => voided ? 0 : amount;

  @override
  Map<String, Object?> toMap() => compact({
        'id': id,
        'number': number,
        'date': date.toIso8601String(),
        'categoryId': categoryId,
        'amount': amount,
        'method': method.name,
        'payee': payee,
        'staffId': staffId,
        'reference': reference,
        'note': note,
        'attachment': attachment,
        'voided': voided ? true : null,
        'voidReason': voidReason,
        'createdAt': createdAt.toIso8601String(),
        'by': by,
      });

  factory Expense.fromMap(Map<String, Object?> m) => Expense(
        id: asStr(m['id']),
        number: asStr(m['number']),
        date: asTime(m['date']) ?? DateTime.now(),
        categoryId: asStr(m['categoryId']),
        amount: asDouble(m['amount']),
        method: payMethodFrom(m['method']),
        payee: asStrOrNull(m['payee']),
        staffId: asStrOrNull(m['staffId']),
        reference: asStrOrNull(m['reference']),
        note: asStrOrNull(m['note']),
        attachment: asStrOrNull(m['attachment']),
        voided: asBool(m['voided']),
        voidReason: asStrOrNull(m['voidReason']),
        createdAt: asTime(m['createdAt']) ?? DateTime.now(),
        by: asStrOrNull(m['by']),
      );
}
