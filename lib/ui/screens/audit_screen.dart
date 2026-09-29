import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../widgets/common.dart';

String auditActionName(String a) => switch (a) {
      'discount' => tr('خصم'),
      'refund' => tr('استرداد'),
      'void' => tr('إلغاء فاتورة'),
      'cancel' => tr('إلغاء اشتراك'),
      'freeze' => tr('تجميد'),
      'unfreeze' => tr('فك تجميد'),
      'override' => tr('سماح استثنائي'),
      'adjust' => tr('تعديل يدوي'),
      'price' => tr('تغيير سعر'),
      'delete' => tr('حذف عضو'),
      'referral' => tr('مكافأة ترشيح'),
      'campaign' => tr('رسالة جماعية'),
      'staff' => tr('موظفون'),
      'stock' => tr('مخزون'),
      'expense_delete' => tr('حذف مصروف'),
      _ => a,
    };

/// سجل العمليات الحساسة: من فعل ماذا ومتى
class AuditScreen extends StatelessWidget {
  const AuditScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    final list = g.audit.all.toList()..sort((a, b) => b.time.compareTo(a.time));
    return Scaffold(
      appBar: AppBar(title: Text(tr('سجل العمليات'))),
      body: list.isEmpty
          ? EmptyState(icon: Icons.history, title: tr('لا توجد عمليات مسجلة'))
          : ListView.separated(
              itemCount: list.length > 500 ? 500 : list.length,
              separatorBuilder: (_, _) => const Divider(indent: 16),
              itemBuilder: (c, i) {
                final a = list[i];
                return ListTile(
                  dense: true,
                  title: Text('${auditActionName(a.action)} — ${a.details}'),
                  subtitle: Text('${dayKey(a.time)} ${hhmm(minutesOfDay(a.time))}${a.user == null ? '' : ' • ${a.user}'}'),
                );
              },
            ),
    );
  }
}
