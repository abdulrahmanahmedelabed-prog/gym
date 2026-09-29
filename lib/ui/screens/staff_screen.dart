import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/phone.dart';
import '../../core/ids.dart';
import '../../core/money.dart';
import '../../models/business.dart';
import '../../services/data_tools.dart';
import '../../services/reports.dart';
import '../../services/license.dart';
import '../widgets/upgrade.dart';
import '../widgets/common.dart';
import 'lock_screen.dart';

class StaffScreen extends StatelessWidget {
  const StaffScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    final list = g.staff.all.toList()..sort((a, b) => a.role.index.compareTo(b.role.index));
    final month = Range.thisMonth(g.now());
    final perf = {for (final t in context.services.reports.trainers(month)) t.trainerId: t};
    return Scaffold(
      appBar: AppBar(title: Text(tr('الموظفون والمدربون'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final active = g.staff.all.where((s) => s.active).length;
          if (active >= g.license.staffLimit) {
            await showUpgradeDialog(context,
                feature: g.license.tier == Tier.free ? Feature.staff : Feature.auditLog,
                message: tr('نسختك تسمح بـ {n} موظف. رقِّ النسخة لإضافة المزيد', {'n': g.license.staffLimit}));
            return;
          }
          if (context.mounted) await _edit(context, null);
        },
        icon: const Icon(Icons.person_add),
        label: Text(tr('موظف')),
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 88), children: [
        for (final s in list)
          ListTile(
            leading: CircleAvatar(backgroundColor: Color(s.colorValue), child: Text(s.name.characters.first, style: const TextStyle(color: Colors.white))),
            title: Text(s.name, style: TextStyle(fontWeight: FontWeight.w700, decoration: s.active ? null : TextDecoration.lineThrough)),
            subtitle: Text([
              roleName(s.role),
              if (s.isTrainer) tr('مدرب'),
              if (s.pinHash != null) tr('له رقم سري'),
              if (perf[s.id] case final p?) tr('هذا الشهر: {n} جلسة، مستحق {a}', {'n': p.sessions, 'a': fmtMoney(p.commission + p.sessionPay)}),
            ].join(' • ')),
            onTap: () => _edit(context, s),
          ),
      ]),
    );
  }

  Future<void> _edit(BuildContext context, Staff? s0) async {
    final g = context.gym;
    final s = s0 != null ? Staff.fromMap(s0.toMap()) : Staff(id: newId(), name: '');
    final name = TextEditingController(text: s.name);
    final phone = TextEditingController(text: s.phone ?? '');
    final pin = TextEditingController();
    final pct = TextEditingController(text: s.commissionPct == 0 ? '' : fmtNum(s.commissionPct));
    final rate = TextEditingController(text: s.sessionRate == 0 ? '' : fmtNum(s.sessionRate));
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(s0 == null ? tr('موظف جديد') : s.name),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: name, decoration: InputDecoration(labelText: tr('الاسم'))),
                const SizedBox(height: 10),
                TextField(controller: phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: tr('الجوال'))),
                const SizedBox(height: 10),
                DropdownButtonFormField<Role>(
                  initialValue: s.role,
                  decoration: InputDecoration(labelText: tr('الدور')),
                  items: [for (final r in Role.values) DropdownMenuItem(value: r, child: Text(roleName(r)))],
                  onChanged: (v) => set(() => s.role = v!),
                ),
                const SizedBox(height: 4),
                Text(_roleHint(s.role), style: Theme.of(c).textTheme.bodySmall),
                const SizedBox(height: 10),
                TextField(
                  controller: pin,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 6,
                  decoration: InputDecoration(labelText: s.pinHash == null ? tr('رقم سري (4-6 أرقام)') : tr('رقم سري جديد (اتركه فارغاً للإبقاء)')),
                ),
                SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(tr('مدرب (تدريب شخصي وحصص)')), value: s.isTrainer, onChanged: (v) => set(() => s.isTrainer = v)),
                if (s.isTrainer)
                  Row(children: [
                    Expanded(child: TextField(controller: pct, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: tr('عمولة التدريب %')))),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: rate, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: tr('أجر الجلسة')))),
                  ]),
                SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(tr('نشط')), value: s.active, onChanged: (v) => set(() => s.active = v)),
                Wrap(spacing: 6, children: [
                  for (final col in [0xFF7E57C2, 0xFF0F766E, 0xFFD81B60, 0xFF1E88E5, 0xFFEF6C00, 0xFF43A047])
                    GestureDetector(
                      onTap: () => set(() => s.colorValue = col),
                      child: CircleAvatar(radius: 14, backgroundColor: Color(col), child: s.colorValue == col ? const Icon(Icons.check, size: 14, color: Colors.white) : null),
                    ),
                ]),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('إلغاء'))),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('حفظ'))),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty || !context.mounted) return;
    final p = pin.text.trim();
    if (p.isNotEmpty && (p.length < 4 || parseIntInput(p) == null)) {
      context.toast(tr('الرقم السري 4 أرقام على الأقل'), error: true);
      return;
    }
    s
      ..name = name.text.trim()
      ..phone = phone.text.trim().isEmpty ? null : phone.text.trim()
      ..commissionPct = parseAmount(pct.text) ?? 0
      ..sessionRate = parseAmount(rate.text) ?? 0;
    if (p.isNotEmpty) s.pinHash = hashPin(p, s.id);
    // لا يمكن إزالة آخر مالك نشط
    final owners = g.staff.all.where((x) => x.role == Role.owner && x.active && x.id != s.id).length;
    if ((s.role != Role.owner || !s.active) && owners == 0 && (s0?.role == Role.owner)) {
      context.toast(tr('يجب أن يبقى مالك واحد نشط على الأقل'), error: true);
      return;
    }
    await g.putAll([s, g.auditEntry('staff', '${s.name} (${roleName(s.role)})')]);
    // المستخدم الحالي عدّل بياناته: تُطبَّق صلاحياته الجديدة فوراً
    if (g.user?.id == s.id) {
      g.user = s;
      g.touch();
    }
  }

  String _roleHint(Role r) => switch (r) {
        Role.owner => tr('كل الصلاحيات'),
        Role.manager => tr('كل شيء عدا الإعدادات والموظفين'),
        Role.reception => tr('الأعضاء، الدخول، البيع والتحصيل، الرسائل'),
        Role.trainer => tr('الدخول والحصص فقط'),
      };
}

