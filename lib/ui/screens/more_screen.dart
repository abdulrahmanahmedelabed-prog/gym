import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../models/business.dart';
import '../widgets/common.dart';
import 'audit_screen.dart';
import 'classes_screen.dart';
import 'kiosk_screen.dart';
import 'leads_screen.dart';
import 'lock_screen.dart';
import 'messages_screen.dart';
import 'plans_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import 'shop_screen.dart';
import 'staff_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    final pending = context.services.pendingManual;
    final items = <(IconData, String, Color, Widget, bool, String?)>[
      (Icons.chat_outlined, tr('الرسائل والتذكيرات'), const Color(0xFF16A34A), const MessagesScreen(), g.can(Perm.messages), pending > 0 ? '$pending' : null),
      (Icons.card_membership, tr('الباقات والأسعار'), const Color(0xFF2563EB), const PlansScreen(), true, null),
      (Icons.event_note, tr('الحصص والحجوزات'), const Color(0xFFEA580C), const ClassesScreen(), g.can(Perm.classes), null),
      (Icons.person_search_outlined, tr('العملاء المحتملون'), const Color(0xFFDB2777), const LeadsScreen(), g.can(Perm.members), null),
      (Icons.shopping_bag_outlined, tr('المتجر والمخزون'), const Color(0xFFD97706), const ShopScreen(), g.can(Perm.sell), null),
      (Icons.insights_outlined, tr('التقارير'), const Color(0xFF7C3AED), const ReportsScreen(), g.can(Perm.reports), null),
      (Icons.badge_outlined, tr('الموظفون والمدربون'), const Color(0xFF0891B2), const StaffScreen(), g.can(Perm.staff), null),
      (Icons.tablet_android, tr('شاشة الدخول الذاتي'), const Color(0xFF0F766E), const KioskScreen(), g.can(Perm.checkin), null),
      (Icons.history, tr('سجل العمليات'), const Color(0xFF64748B), const AuditScreen(), g.can(Perm.reports), null),
      (Icons.settings_outlined, tr('الإعدادات'), const Color(0xFF475569), const SettingsScreen(), true, null),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(tr('المزيد'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (g.user != null)
          Card(
            child: ListTile(
              leading: CircleAvatar(backgroundColor: Color(g.user!.colorValue), child: Text(g.user!.name.characters.first, style: const TextStyle(color: Colors.white))),
              title: Text(g.user!.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(roleName(g.user!.role)),
              trailing: TextButton(
                onPressed: () {
                  g.user = null;
                  g.touch();
                },
                child: Text(tr('خروج')),
              ),
            ),
          ),
        if (g.user != null) const SizedBox(height: 12),
        ResponsiveGrid(minWidth: 150, children: [
          for (final it in items.where((x) => x.$5))
            Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => context.push(it.$4),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Badge(
                      isLabelVisible: it.$6 != null,
                      label: Text(it.$6 ?? ''),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: it.$3.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                        child: Icon(it.$1, color: it.$3),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(it.$2, style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 2),
                  ]),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 24),
        Center(child: Text('نادي جيم • Nadi Gym 1.0', style: context.text.bodySmall)),
      ]),
    );
  }
}
