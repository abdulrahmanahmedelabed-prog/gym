import '../core/dates.dart';
import '../core/money.dart';
import '../data/gym_data.dart';
import '../models/billing.dart';
import '../models/member.dart';
import '../models/subscription.dart';

/// المتغيرات المتاحة في قوالب الرسائل (تظهر للمستخدم في شاشة تعديل القوالب)
const templateVars = <String, String>{
  '{name}': 'اسم العضو كاملاً',
  '{first_name}': 'الاسم الأول',
  '{code}': 'رقم العضوية',
  '{gym}': 'اسم النادي',
  '{gym_phone}': 'هاتف النادي',
  '{plan}': 'اسم الباقة',
  '{end_date}': 'تاريخ انتهاء الاشتراك',
  '{days}': 'عدد الأيام',
  '{visits_left}': 'الحصص المتبقية',
  '{amount}': 'المبلغ',
  '{balance}': 'المتبقي على العضو',
  '{due_date}': 'تاريخ الاستحقاق',
  '{invoice_no}': 'رقم الفاتورة',
  '{pay_link}': 'رابط أو بيانات الدفع',
  '{class}': 'اسم الحصة',
  '{time}': 'وقت الحصة',
  '{date}': 'التاريخ',
};

/// تعبئة القالب. السطر الذي فيه متغير وأصبح فارغاً (مثل رابط دفع غير موجود) يُحذف،
/// أما الأسطر الفارغة المقصودة في القالب فتبقى.
String renderTemplate(String tpl, Map<String, String?> vars) {
  final out = <String>[];
  for (final line in tpl.split('\n')) {
    var l = line;
    vars.forEach((k, v) => l = l.replaceAll('{$k}', v ?? ''));
    l = l.trimRight();
    if (l.trim().isEmpty && line.contains('{')) continue;
    if (l.trim().isEmpty && out.isNotEmpty && out.last.trim().isEmpty) continue;
    out.add(l);
  }
  while (out.isNotEmpty && out.last.trim().isEmpty) {
    out.removeLast();
  }
  return out.join('\n');
}

class TemplateContext {
  final GymData d;
  TemplateContext(this.d);

  Map<String, String?> base(Member? m) => {
        'name': m?.name,
        'first_name': m?.firstName,
        'code': m == null ? null : '${m.code}',
        'gym': d.settings.gymName,
        'gym_phone': d.settings.gymPhone,
        'balance': m == null ? null : fmtMoney(d.balanceOf(m.id)),
        'date': dayKey(d.today),
        'pay_link': payInfo(),
      };

  Map<String, String?> forSub(Member m, Subscription s) => {
        ...base(m),
        'plan': s.planName,
        'end_date': dayKey(s.end),
        'days': '${s.daysLeft(d.today).abs()}',
        'visits_left': s.visitsLeft == null ? '' : '${s.visitsLeft}',
      };

  Map<String, String?> forInvoice(Member? m, Invoice inv, {double? amount, DateTime? due}) => {
        ...base(m),
        'invoice_no': inv.number,
        'amount': fmtMoney(amount ?? inv.balance),
        'due_date': due == null ? '' : dayKey(due),
        'pay_link': payInfo(inv),
      };

  /// رابط الدفع: رابط بوابة معلّق للفاتورة، أو رابط ثابت، أو بيانات التحويل (محفظة/بنك)
  String payInfo([Invoice? inv]) {
    if (inv != null) {
      for (final l in inv.links.reversed) {
        if (l.status == LinkStatus.pending) return l.url;
      }
    }
    final s = d.settings;
    if (s.payProvider == 'link' && s.payLinkTemplate.isNotEmpty) {
      return s.payLinkTemplate
          .replaceAll('{amount}', inv == null ? '' : roundMoney(inv.balance).toString())
          .replaceAll('{invoice}', inv?.number ?? '');
    }
    return s.paymentInstructions;
  }
}
