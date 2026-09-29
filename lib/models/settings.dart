import 'base.dart';

/// أنواع الرسائل الآلية
class Rk {
  static const welcome = 'welcome';
  static const receipt = 'receipt';
  static const expirySoon = 'expiry_soon';
  static const expired = 'expired';
  static const winback = 'winback';
  static const visitsLow = 'visits_low';
  static const installmentDue = 'installment_due';
  static const installmentLate = 'installment_late';
  static const birthday = 'birthday';
  static const inactive = 'inactive';
  static const freezeEnd = 'freeze_end';
  static const classReminder = 'class_reminder';
  static const ownerDaily = 'owner_daily';
  static const renewalRequest = 'renewal_request';

  static const all = [
    welcome, receipt, expirySoon, expired, winback, visitsLow, installmentDue, installmentLate,
    birthday, inactive, freezeEnd, classReminder, renewalRequest, ownerDaily,
  ];
}

/// الإعدادات الافتراضية لكل تذكير: مفعل؟ وبعد/قبل كم يوم
const reminderDefaults = <String, ({bool on, List<int> days})>{
  Rk.welcome: (on: true, days: []),
  Rk.receipt: (on: true, days: []),
  Rk.expirySoon: (on: true, days: [7, 3, 1]),
  Rk.expired: (on: true, days: []),
  Rk.winback: (on: true, days: [7, 30]),
  Rk.visitsLow: (on: true, days: [2]), // عند بقاء حصتين
  Rk.installmentDue: (on: true, days: [2, 0]),
  Rk.installmentLate: (on: true, days: [3, 10]),
  Rk.birthday: (on: true, days: []),
  Rk.inactive: (on: true, days: [10]),
  Rk.freezeEnd: (on: true, days: []),
  Rk.classReminder: (on: true, days: []),
  Rk.ownerDaily: (on: false, days: []),
  Rk.renewalRequest: (on: true, days: [3]), // قبل الانتهاء بـ 3 أيام لمن فعّل التجديد التلقائي
};

const defaultTemplatesAr = <String, String>{
  Rk.welcome: 'أهلاً {first_name} 👋\nيسعدنا انضمامك إلى {gym}! رقم عضويتك {code}.\n'
      'اشتراكك: {plan} حتى {end_date}.\nنتمنى لك تمريناً ممتعاً 💪',
  Rk.receipt: 'شكراً {first_name} 🙏\nاستلمنا {amount} للفاتورة {invoice_no}.\nالمتبقي عليك: {balance}.\n{gym}',
  Rk.expirySoon: 'مرحباً {first_name} 👋\nاشتراكك في {gym} ({plan}) ينتهي بعد {days} يوم بتاريخ {end_date}.\n'
      'جدّد الآن لتستمر بدون انقطاع 💪\n{pay_link}',
  Rk.expired: 'مرحباً {first_name}\nانتهى اشتراكك في {gym} بتاريخ {end_date}.\n'
      'نفتقدك! جدّد اشتراكك وارجع لتمارينك 💪\nللاستفسار: {gym_phone}',
  Rk.winback: '{first_name}، مرّ {days} يوم على انتهاء اشتراكك في {gym} 😔\n'
      'عندنا عرض خاص لعودتك، تواصل معنا: {gym_phone}',
  Rk.visitsLow: 'تنبيه من {gym}: تبقّى {visits_left} حصة فقط في اشتراكك ({plan}). جدّد مبكراً لتحجز مكانك 💪',
  Rk.installmentDue: 'تذكير لطيف 🔔\nقسط بمبلغ {amount} مستحق بتاريخ {due_date} (فاتورة {invoice_no}).\n{pay_link}\n{gym}',
  Rk.installmentLate: 'مرحباً {first_name}\nالقسط بمبلغ {amount} المستحق بتاريخ {due_date} لم يُسدَّد بعد، '
      'نرجو السداد في أقرب وقت.\n{pay_link}\n{gym}',
  Rk.birthday: 'كل عام وأنت بخير يا {first_name} 🎂🎉\nفريق {gym} يتمنى لك سنة مليئة بالصحة والإنجازات!',
  Rk.inactive: '{first_name}، اشتقنا لك! 💪\nلم نرك في {gym} منذ {days} يوماً. '
      'اشتراكك فعّال حتى {end_date} — لا تضيّعه!',
  Rk.freezeEnd: 'مرحباً {first_name}، ينتهي تجميد اشتراكك غداً. بانتظارك في {gym} 💪',
  Rk.classReminder: 'تذكير: حصة {class} اليوم الساعة {time} في {gym}. نراك هناك! 🔥',
  Rk.ownerDaily: 'ملخص {gym} ليوم {date}:\n{summary}',
  Rk.renewalRequest: 'مرحباً {first_name} 👋\nاشتراكك ({plan}) في {gym} ينتهي {end_date}، وجهّزنا لك فاتورة التجديد {invoice_no} بمبلغ {amount}.\n'
      'للدفع:\n{pay_link}\nبعد الدفع أرسل لنا رقم العملية ويتجدد اشتراكك تلقائياً ✅',
};

const defaultTemplatesEn = <String, String>{
  Rk.welcome: 'Hi {first_name} 👋\nWelcome to {gym}! Your member number is {code}.\n'
      'Your plan: {plan} until {end_date}.\nEnjoy your workouts 💪',
  Rk.receipt: 'Thank you {first_name} 🙏\nWe received {amount} for invoice {invoice_no}.\nBalance due: {balance}.\n{gym}',
  Rk.expirySoon: 'Hi {first_name} 👋\nYour {gym} membership ({plan}) ends in {days} days on {end_date}.\n'
      'Renew now to keep going 💪\n{pay_link}',
  Rk.expired: 'Hi {first_name}\nYour {gym} membership ended on {end_date}.\n'
      'We miss you! Renew and get back to training 💪\nQuestions: {gym_phone}',
  Rk.winback: '{first_name}, it has been {days} days since your {gym} membership ended 😔\n'
      'We have a special comeback offer for you: {gym_phone}',
  Rk.visitsLow: '{gym}: only {visits_left} sessions left on your plan ({plan}). Renew early 💪',
  Rk.installmentDue: 'Friendly reminder 🔔\nAn installment of {amount} is due on {due_date} (invoice {invoice_no}).\n'
      '{pay_link}\n{gym}',
  Rk.installmentLate: 'Hi {first_name}\nThe installment of {amount} due on {due_date} is still unpaid. '
      'Please settle it soon.\n{pay_link}\n{gym}',
  Rk.birthday: 'Happy birthday {first_name} 🎂🎉\nThe {gym} team wishes you a year full of health and wins!',
  Rk.inactive: '{first_name}, we miss you! 💪\nWe have not seen you at {gym} for {days} days. '
      'Your membership is active until {end_date} — make the most of it!',
  Rk.freezeEnd: 'Hi {first_name}, your membership freeze ends tomorrow. See you at {gym} 💪',
  Rk.classReminder: 'Reminder: {class} today at {time} at {gym}. See you there! 🔥',
  Rk.ownerDaily: '{gym} summary for {date}:\n{summary}',
  Rk.renewalRequest: 'Hi {first_name} 👋\nYour {gym} membership ({plan}) ends on {end_date}. Your renewal invoice {invoice_no} for {amount} is ready.\n'
      'To pay:\n{pay_link}\nSend us the transaction number after paying and your membership renews automatically ✅',
};

/// طريقة إرسال واتساب
/// phone   = من تطبيق واتساب على الجوال بلمسة (مجاني)
/// cloud   = WhatsApp Cloud API الرسمي من Meta (آلي)
/// twilio  = عبر Twilio (آلي)
/// gateway = أي مزوّد له رابط HTTP (UltraMsg، Green API، مزوّد محلي...)
const waModes = ['phone', 'cloud', 'twilio', 'gateway'];

/// طريقة إرسال SMS
/// phone   = تطبيق الرسائل على الجوال بلمسة
/// sim     = من شريحة الجوال مباشرة وآلياً (أندرويد)
/// twilio / gateway كما في واتساب
const smsModes = ['phone', 'sim', 'twilio', 'gateway'];

/// بوابات الدفع الإلكتروني
const payProviders = ['none', 'stripe', 'moyasar', 'tap', 'link'];

/// حساب يستلم عليه النادي الدفع: محفظة (جوال باي، بال باي...) أو حساب بنكي أو معرّف iBuraq
class PayAccount {
  String id;
  String type; // wallet / bank
  String name;
  String number; // رقم المحفظة أو الحساب أو IBAN أو المعرّف
  String holder;
  String qr; // محتوى رمز QR الموحد لهذا الحساب (من تطبيق البنك/المحفظة)
  bool active;

  PayAccount({required this.id, this.type = 'wallet', required this.name, this.number = '', this.holder = '', this.qr = '', this.active = true});

  Map<String, Object?> toMap() => {'id': id, 'type': type, 'name': name, 'number': number, 'holder': holder, 'qr': qr, 'active': active};

  factory PayAccount.fromMap(Map<String, Object?> m) => PayAccount(
        id: asStr(m['id']),
        type: asStr(m['type'], 'wallet'),
        name: asStr(m['name']),
        number: asStr(m['number']),
        holder: asStr(m['holder']),
        qr: asStr(m['qr']),
        active: asBool(m['active'], true),
      );
}

/// أسماء جاهزة للاختيار
const walletPresets = ['جوال باي', 'بال باي', 'انستاباي', 'فودافون كاش', 'STC Pay', 'زين كاش'];
const bankPresets = ['iBuraq', 'بنك فلسطين', 'البنك العربي', 'البنك الإسلامي العربي', 'البنك الوطني', 'بنك القدس', 'البنك الأهلي'];

/// نافذة زمنية لجنس معين (ساعات السيدات مثلاً)
class GenderWindow {
  String gender; // m / f
  List<int> weekdays;
  int from;
  int to;

  GenderWindow({required this.gender, required this.weekdays, required this.from, required this.to});

  Map<String, Object?> toMap() => {'gender': gender, 'weekdays': weekdays, 'from': from, 'to': to};

  factory GenderWindow.fromMap(Map<String, Object?> m) => GenderWindow(
        gender: asStr(m['gender'], 'f'),
        weekdays: asIntList(m['weekdays']),
        from: asInt(m['from']),
        to: asInt(m['to']),
      );
}

/// إعدادات النادي كلها في سجل واحد.
class GymSettings {
  final Map<String, Object?> data;

  GymSettings([Map<String, Object?>? d]) : data = d ?? {};

  T _get<T>(String k, T def) {
    final v = data[k];
    if (v == null) return def;
    if (T == double) return asDouble(v, def as double) as T;
    if (T == int) return asInt(v, def as int) as T;
    if (T == bool) return asBool(v, def as bool) as T;
    if (T == String) return v.toString() as T;
    return v as T;
  }

  void set(String k, Object? v) => data[k] = v;

  // --- النادي
  String get gymName => _get('gymName', 'نادي اللياقة');
  set gymName(String v) => set('gymName', v);
  String get gymPhone => _get('gymPhone', '');
  set gymPhone(String v) => set('gymPhone', v);
  String get address => _get('address', '');
  set address(String v) => set('address', v);
  String? get logo => asStrOrNull(data['logo']);
  set logo(String? v) => set('logo', v);
  String get currencyCode => _get('currencyCode', 'EGP');
  set currencyCode(String v) => set('currencyCode', v);
  String get currencySymbol => _get('currencySymbol', 'ج.م');
  set currencySymbol(String v) => set('currencySymbol', v);
  String get countryCode => _get('countryCode', '20');
  set countryCode(String v) => set('countryCode', v);
  String get language => _get('language', 'ar');
  set language(String v) => set('language', v);
  String get themeMode => _get('themeMode', 'system');
  set themeMode(String v) => set('themeMode', v);
  bool get onboarded => _get('onboarded', false);
  set onboarded(bool v) => set('onboarded', v);

  // --- الضريبة والفواتير
  bool get taxEnabled => _get('taxEnabled', false);
  set taxEnabled(bool v) => set('taxEnabled', v);
  double get taxRate => _get('taxRate', 14.0); // بالنسبة المئوية
  set taxRate(double v) => set('taxRate', v.clamp(0, 100).toDouble());
  bool get taxInclusive => _get('taxInclusive', true);
  set taxInclusive(bool v) => set('taxInclusive', v);
  String get taxNumber => _get('taxNumber', '');
  set taxNumber(String v) => set('taxNumber', v);
  bool get zatcaQr => _get('zatcaQr', false); // رمز QR للفاتورة الضريبية المبسطة (السعودية)
  set zatcaQr(bool v) => set('zatcaQr', v);
  String get invoiceFooter => _get('invoiceFooter', 'شكراً لاختياركم ناديَنا 💪');
  set invoiceFooter(String v) => set('invoiceFooter', v);
  String get invoicePrefix => _get('invoicePrefix', 'INV');
  set invoicePrefix(String v) => set('invoicePrefix', v);
  bool get receiptThermal => _get('receiptThermal', false);
  set receiptThermal(bool v) => set('receiptThermal', v);
  double get maxDiscountPct => _get('maxDiscountPct', 20.0); // أعلى خصم لموظف الاستقبال بدون إذن
  set maxDiscountPct(double v) => set('maxDiscountPct', v.clamp(0, 100).toDouble());

  // --- الاشتراكات والدخول
  bool get renewFromEnd => _get('renewFromEnd', true);
  set renewFromEnd(bool v) => set('renewFromEnd', v);
  int get graceDays => _get('graceDays', 0); // أيام سماح بعد الانتهاء
  set graceDays(int v) => set('graceDays', v.clamp(0, 365));
  bool get blockOnDebt => _get('blockOnDebt', false);
  set blockOnDebt(bool v) => set('blockOnDebt', v);
  double get debtLimit => _get('debtLimit', 0.0); // يمنع الدخول إذا زاد المتأخر عن هذا الحد
  set debtLimit(double v) => set('debtLimit', v < 0 ? 0.0 : v);
  int get sessionMinutes => _get('sessionMinutes', 90); // متوسط مدة التمرين لحساب الموجودين الآن
  set sessionMinutes(int v) => set('sessionMinutes', v.clamp(10, 600));
  int get referralRewardDays => _get('referralRewardDays', 7);
  set referralRewardDays(int v) => set('referralRewardDays', v.clamp(0, 365));
  List<GenderWindow> get genderWindows =>
      asMapList(data['genderWindows']).map(GenderWindow.fromMap).toList();
  set genderWindows(List<GenderWindow> v) => set('genderWindows', v.map((w) => w.toMap()).toList());

  // --- الرسائل
  String get waMode => _get('waMode', 'phone');
  set waMode(String v) => set('waMode', v);
  String get smsMode => _get('smsMode', 'phone');
  set smsMode(String v) => set('smsMode', v);
  bool get fallbackToSms => _get('fallbackToSms', true);
  set fallbackToSms(bool v) => set('fallbackToSms', v);
  bool get autoReminders => _get('autoReminders', true);
  set autoReminders(bool v) => set('autoReminders', v);
  int get sendFrom => _get('sendFrom', 10 * 60); // لا ترسل قبل 10 صباحاً
  set sendFrom(int v) => set('sendFrom', v);
  int get sendTo => _get('sendTo', 21 * 60); // ولا بعد 9 مساءً
  set sendTo(int v) => set('sendTo', v);
  String get ownerPhone => _get('ownerPhone', '');
  set ownerPhone(String v) => set('ownerPhone', v);
  String get lastReminderRun => _get('lastReminderRun', '');
  set lastReminderRun(String v) => set('lastReminderRun', v);

  String str(String k, [String def = '']) => _get(k, def);
  void setStr(String k, String v) => set(k, v);

  bool reminderOn(String key) => _get('rem_${key}_on', reminderDefaults[key]?.on ?? false);
  void setReminderOn(String key, bool v) => set('rem_${key}_on', v);
  List<int> reminderDays(String key) {
    final v = data['rem_${key}_days'];
    return v is List ? asIntList(v) : List.of(reminderDefaults[key]?.days ?? const []);
  }

  /// أيام التذكير: بلا سالب ولا تكرار، مرتبة من الأكبر
  void setReminderDays(String key, List<int> v) => set('rem_${key}_days', ({...v.where((x) => x >= 0 && x <= 365)}.toList()..sort((a, b) => b.compareTo(a))));

  String template(String key) {
    final custom = asStrOrNull(data['tpl_$key']);
    if (custom != null) return custom;
    return (language == 'en' ? defaultTemplatesEn : defaultTemplatesAr)[key] ?? '';
  }

  void setTemplate(String key, String? v) => set('tpl_$key', v);

  // --- الدفع الإلكتروني
  String get payProvider => _get('payProvider', 'none');
  set payProvider(String v) => set('payProvider', v);
  String get paySecretKey => _get('paySecretKey', '');
  set paySecretKey(String v) => set('paySecretKey', v);
  String get payLinkTemplate => _get('payLinkTemplate', '');
  set payLinkTemplate(String v) => set('payLinkTemplate', v);
  String get payReturnUrl => _get('payReturnUrl', '');
  set payReturnUrl(String v) => set('payReturnUrl', v);
  String get walletInfo => _get('walletInfo', ''); // بيانات التحويل: انستاباي، فودافون كاش، STC Pay، IBAN
  set walletInfo(String v) => set('walletInfo', v);
  List<PayAccount> get payAccounts => asMapList(data['payAccounts']).map(PayAccount.fromMap).toList();
  set payAccounts(List<PayAccount> v) => set('payAccounts', v.map((a) => a.toMap()).toList());
  List<PayAccount> get activeAccounts => payAccounts.where((a) => a.active).toList();

  /// نص بيانات الدفع للرسائل: النص المكتوب يدوياً، وإلا يُبنى من حسابات الاستلام
  String get paymentInstructions {
    if (walletInfo.trim().isNotEmpty) return walletInfo;
    final acc = activeAccounts;
    if (acc.isEmpty) return '';
    return acc.map((a) => '${a.name}: ${a.number}${a.holder.isEmpty ? '' : ' (${a.holder})'}').join('\n');
  }

  // --- الأمان
  bool get requirePin => _get('requirePin', false);
  set requirePin(bool v) => set('requirePin', v);
  int get counter => _get('counter', 0);

  Map<String, Object?> toMap() => Map.of(data);
}
