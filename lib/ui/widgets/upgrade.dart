import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../services/license.dart';
import '../screens/license_screen.dart';
import 'common.dart';

const plusColor = Color(0xFF2563EB);
const proColor = Color(0xFF7C3AED);

Color tierColor(Tier t) => switch (t) { Tier.free => const Color(0xFF64748B), Tier.plus => plusColor, Tier.pro => proColor };

/// شارة صغيرة Plus / Pro بجانب الميزة المقفلة
class TierBadge extends StatelessWidget {
  final Tier tier;
  const TierBadge(this.tier, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: tierColor(tier), borderRadius: BorderRadius.circular(6)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.lock, size: 10, color: Colors.white),
          const SizedBox(width: 3),
          Text(tierName(tier), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
        ]),
      );
}

/// شارة القفل إن كانت الميزة غير متاحة في النسخة الحالية
Widget? lockFor(BuildContext context, Feature f) => context.gymWatch.has(f) ? null : TierBadge(featureTier[f]!);

Future<void> showUpgradeDialog(BuildContext context, {Feature? feature, String? message}) async {
  final tier = feature == null ? Tier.plus : featureTier[feature]!;
  final go = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      icon: Icon(Icons.workspace_premium, size: 40, color: tierColor(tier)),
      title: Text(feature == null ? tr('ميزة مدفوعة') : tr('متاحة في نسخة {t}', {'t': tierName(tier)})),
      content: Text(message ?? (feature == null ? '' : featureName(feature)), textAlign: TextAlign.center),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('لاحقاً'))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: tierColor(tier)),
          onPressed: () => Navigator.pop(c, true),
          child: Text(tr('عرض الباقات')),
        ),
      ],
    ),
  );
  if (go == true && context.mounted) await context.push(const LicenseScreen());
}

/// يتحقق من الميزة؛ إن كانت مقفلة يعرض الترقية ويرجع false
Future<bool> ensureFeature(BuildContext context, Feature f) async {
  if (context.gym.has(f)) return true;
  await showUpgradeDialog(context, feature: f);
  return false;
}
