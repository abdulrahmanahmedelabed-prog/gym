import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../models/business.dart';
import '../widgets/common.dart';
import 'checkin_screen.dart';
import 'dashboard_screen.dart';
import 'finance_screen.dart';
import 'members_screen.dart';
import 'more_screen.dart';

/// الهيكل الرئيسي: شريط سفلي على الجوال، وشريط جانبي على الأجهزة اللوحية
class Shell extends StatefulWidget {
  const Shell({super.key});

  static void goTo(BuildContext context, int index) => context.findAncestorStateOfType<_ShellState>()?.go(index);

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;

  void go(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    final canFinance = g.can(Perm.sell) || g.can(Perm.reports);
    final pages = <(Widget, IconData, IconData, String)>[
      (const DashboardScreen(), Icons.space_dashboard_outlined, Icons.space_dashboard, tr('الرئيسية')),
      (const MembersScreen(), Icons.people_outline, Icons.people, tr('الأعضاء')),
      (const CheckinScreen(), Icons.qr_code_scanner, Icons.qr_code_scanner, tr('الدخول')),
      if (canFinance) (const FinanceScreen(), Icons.account_balance_wallet_outlined, Icons.account_balance_wallet, tr('المالية')),
      (const MoreScreen(), Icons.grid_view_outlined, Icons.grid_view, tr('المزيد')),
    ];
    final i = _index.clamp(0, pages.length - 1);
    final body = IndexedStack(index: i, children: [for (final p in pages) p.$1]);
    final pending = context.services.pendingManual;

    Widget iconFor(int k, bool selected) {
      final icon = Icon(selected ? pages[k].$3 : pages[k].$2);
      if (pages[k].$1 is MoreScreen && pending > 0) {
        return Badge(label: Text('$pending'), child: icon);
      }
      return icon;
    }

    if (context.wide) {
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            selectedIndex: i,
            onDestinationSelected: go,
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: CircleAvatar(backgroundColor: context.colors.primary, child: const Icon(Icons.fitness_center, color: Colors.white)),
            ),
            destinations: [
              for (var k = 0; k < pages.length; k++)
                NavigationRailDestination(icon: iconFor(k, false), selectedIcon: iconFor(k, true), label: Text(pages[k].$4)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ]),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: i,
        onDestinationSelected: go,
        destinations: [
          for (var k = 0; k < pages.length; k++)
            NavigationDestination(icon: iconFor(k, false), selectedIcon: iconFor(k, true), label: pages[k].$4),
        ],
      ),
    );
  }
}
