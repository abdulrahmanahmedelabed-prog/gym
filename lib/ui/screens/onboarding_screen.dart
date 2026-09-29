import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/ids.dart';
import '../../core/dates.dart';
import '../../models/business.dart';
import '../../models/plan.dart';
import '../../services/demo_data.dart';
import 'sync_screen.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// الدول الشائعة: رمز الاتصال والعملة ونسبة الضريبة الافتراضية
class CountryPreset {
  final String ar, en, dial, currency, symbol;
  final double vat;
  const CountryPreset(this.ar, this.en, this.dial, this.currency, this.symbol, this.vat);
}

const countryPresets = [
  CountryPreset('فلسطين', 'Palestine', '970', 'ILS', '₪', 16),
  CountryPreset('مصر', 'Egypt', '20', 'EGP', 'ج.م', 14),
  CountryPreset('السعودية', 'Saudi Arabia', '966', 'SAR', 'ر.س', 15),
  CountryPreset('الإمارات', 'UAE', '971', 'AED', 'د.إ', 5),
  CountryPreset('الكويت', 'Kuwait', '965', 'KWD', 'د.ك', 0),
  CountryPreset('قطر', 'Qatar', '974', 'QAR', 'ر.ق', 0),
  CountryPreset('البحرين', 'Bahrain', '973', 'BHD', 'د.ب', 10),
  CountryPreset('عُمان', 'Oman', '968', 'OMR', 'ر.ع', 5),
  CountryPreset('الأردن', 'Jordan', '962', 'JOD', 'د.أ', 16),
  CountryPreset('العراق', 'Iraq', '964', 'IQD', 'د.ع', 0),
  CountryPreset('لبنان', 'Lebanon', '961', 'USD', r'$', 11),
  CountryPreset('سوريا', 'Syria', '963', 'SYP', 'ل.س', 0),
  CountryPreset('المغرب', 'Morocco', '212', 'MAD', 'د.م', 20),
  CountryPreset('الجزائر', 'Algeria', '213', 'DZD', 'د.ج', 19),
  CountryPreset('تونس', 'Tunisia', '216', 'TND', 'د.ت', 19),
  CountryPreset('ليبيا', 'Libya', '218', 'LYD', 'د.ل', 0),
  CountryPreset('السودان', 'Sudan', '249', 'SDG', 'ج.س', 0),
  CountryPreset('اليمن', 'Yemen', '967', 'YER', 'ر.ي', 0),
  CountryPreset('أخرى (دولار)', 'Other (USD)', '1', 'USD', r'$', 0),
];

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _owner = TextEditingController();
  CountryPreset _country = countryPresets.first;
  String _lang = 'ar';
  bool _busy = false;

  void _applyBasics() {
    final s = context.gym.settings
      ..language = _lang
      ..gymName = _name.text.trim().isEmpty ? tr('نادي اللياقة') : _name.text.trim()
      ..gymPhone = _phone.text.trim()
      ..countryCode = _country.dial
      ..currencyCode = _country.currency
      ..currencySymbol = _country.symbol
      ..taxRate = _country.vat
      ..zatcaQr = _country.currency == 'SAR';
    context.gym.applySettings();
    s.onboarded = false;
  }

  Future<void> _startEmpty() async {
    setState(() => _busy = true);
    final g = context.gym;
    _applyBasics();
    final plans = [
      Plan(id: newId(), name: tr('شهري'), price: 0, freezeDays: 7, freezeTimes: 1, colorValue: 0xFF1E88E5, sort: 1),
      Plan(id: newId(), name: tr('3 أشهر'), durationValue: 3, price: 0, freezeDays: 15, freezeTimes: 2, colorValue: 0xFF43A047, sort: 2),
      Plan(id: newId(), name: tr('6 أشهر'), durationValue: 6, price: 0, freezeDays: 30, freezeTimes: 2, colorValue: 0xFFFB8C00, sort: 3),
      Plan(id: newId(), name: tr('سنوي'), durationUnit: DurationUnit.year, price: 0, freezeDays: 60, freezeTimes: 3, colorValue: 0xFFE53935, sort: 4),
      Plan(id: newId(), name: tr('12 حصة'), kind: PlanKind.visits, durationValue: 2, visits: 12, price: 0, colorValue: 0xFF8E24AA, sort: 5),
      Plan(id: newId(), name: tr('يوم واحد'), durationUnit: DurationUnit.day, price: 0, colorValue: 0xFF757575, sort: 6),
    ];
    final owner = Staff(id: newId(), name: _owner.text.trim().isEmpty ? tr('المالك') : _owner.text.trim(), role: Role.owner);
    g.settings.onboarded = true;
    await g.putAll([...plans, owner], withSettings: true);
    g.applySettings();
    if (mounted) context.toast(tr('جاهز! حدّد أسعار الباقات من «المزيد › الباقات»'));
  }

  Future<void> _startDemo() async {
    setState(() => _busy = true);
    final g = context.gym;
    _applyBasics();
    await DemoData(g).generate();
    g.settings
      ..language = _lang
      ..onboarded = true;
    await g.saveSettings();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(padding: const EdgeInsets.all(24), children: [
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(color: brandSeed, borderRadius: BorderRadius.circular(24)),
                  child: const Icon(Icons.fitness_center, color: Colors.white, size: 46),
                ),
              ),
              const SizedBox(height: 16),
              Text(tr('أهلاً بك في نادي جيم'), textAlign: TextAlign.center, style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(tr('إدارة الأعضاء والاشتراكات والدفع والتذكيرات بواتساب والرسائل — من جوالك وبدون إنترنت'),
                  textAlign: TextAlign.center, style: TextStyle(color: c.onSurfaceVariant)),
              const SizedBox(height: 24),
              SegmentedButton<String>(
                segments: const [ButtonSegment(value: 'ar', label: Text('العربية')), ButtonSegment(value: 'en', label: Text('English'))],
                selected: {_lang},
                onSelectionChanged: (v) => setState(() {
                  _lang = v.first;
                  I18n.lang = _lang;
                }),
              ),
              const SizedBox(height: 16),
              TextField(controller: _name, decoration: InputDecoration(labelText: tr('اسم النادي'), prefixIcon: const Icon(Icons.storefront))),
              const SizedBox(height: 12),
              TextField(controller: _owner, decoration: InputDecoration(labelText: tr('اسمك (المالك)'), prefixIcon: const Icon(Icons.person))),
              const SizedBox(height: 12),
              DropdownButtonFormField<CountryPreset>(
                initialValue: _country,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('الدولة والعملة'), prefixIcon: const Icon(Icons.public)),
                items: [
                  for (final p in countryPresets)
                    DropdownMenuItem(value: p, child: Text('${I18n.isAr ? p.ar : p.en} — ${p.currency} (+${p.dial})')),
                ],
                onChanged: (v) => setState(() => _country = v!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: tr('هاتف النادي (للأعضاء)'), prefixIcon: const Icon(Icons.phone)),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(onPressed: _busy ? null : _startEmpty, icon: const Icon(Icons.rocket_launch), label: Text(tr('ابدأ'))),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _busy ? null : _startDemo,
                icon: const Icon(Icons.science_outlined),
                label: Text(tr('جرّب ببيانات نادٍ تجريبي')),
              ),
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: _busy ? null : () => context.push(const SyncScreen()),
                icon: const Icon(Icons.devices_outlined),
                label: Text(tr('ناديك مسجّل على جهاز آخر؟ اربط هذا الجهاز')),
              ),
              if (_busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
              const SizedBox(height: 16),
              Text(tr('بياناتك تُحفظ على هذا الجهاز ويعمل التطبيق كاملاً بدون إنترنت. خذ نسخة احتياطية بانتظام، أو فعّل المزامنة السحابية.'),
                  textAlign: TextAlign.center, style: context.text.bodySmall?.copyWith(color: c.onSurfaceVariant)),
            ]),
          ),
        ),
      ),
    );
  }
}
