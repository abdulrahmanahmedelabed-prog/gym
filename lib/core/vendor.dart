/// إعدادات البائع (أنت): الأسعار، طرق استلام ثمن النسخ المدفوعة، ورقم واتساب التفعيل.
/// ✏️ عدّل هذا الملف ثم ابنِ التطبيق من جديد (يكفي رفع التعديل إلى GitHub).
library;

class VendorAccount {
  final String name; // جوال باي، بال باي، بنك فلسطين...
  final String number; // رقم المحفظة أو الحساب أو IBAN أو المعرّف
  final String holder; // اسم المستلم
  const VendorAccount(this.name, this.number, [this.holder = '']);
}

class VendorPrice {
  final String period; // monthly / yearly / lifetime
  final double amount;
  const VendorPrice(this.period, this.amount);
}

class Vendor {
  /// رقم واتساب لاستلام طلبات التفعيل (دولي بدون +)
  static const whatsapp = '970590000000';

  static const name = 'نادي جيم';

  /// عملة أسعار النسخ المدفوعة
  static const currency = '₪';

  /// أسعار الباقات (أمثلة — عدّلها)
  static const plusPrices = [VendorPrice('monthly', 49), VendorPrice('yearly', 450)];
  static const proPrices = [VendorPrice('monthly', 89), VendorPrice('yearly', 850)];

  /// أين يحوّل الزبون ثمن النسخة (أمثلة — عدّلها)
  static const accounts = [
    VendorAccount('جوال باي', '0590000000', 'اسم المستلم'),
    VendorAccount('بال باي', '0590000000', 'اسم المستلم'),
    VendorAccount('تحويل بنكي / iBuraq', 'PS00 XXXX 0000 0000 0000 0000 000', 'اسم صاحب الحساب'),
  ];

  /// محتوى رمز QR الموحد (iBuraq QR Quick) لحسابك — امسحه من تطبيق بنكك بأي قارئ QR والصق النص هنا.
  /// فارغ = لا يظهر رمز.
  static const qrPayload = '';

  /// عدد الأعضاء الفعّالين المسموح في النسخة المجانية
  static const freeMemberLimit = 100;

  /// أيام تجربة كل مزايا Pro مجاناً عند أول تشغيل
  static const trialDays = 30;

  /// خادم المزامنة السحابية (Supabase): أنشئ مشروعاً مجانياً على supabase.com، ونفّذ الملف
  /// server/supabase_sync.sql في SQL Editor، ثم ضع هنا Project URL و anon public key
  /// (Settings › API). إن تُركا فارغين يستطيع كل نادٍ إدخال خادمه في شاشة المزامنة.
  static const syncUrl = '';
  static const syncKey = '';
}
