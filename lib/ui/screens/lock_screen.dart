import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../models/business.dart';
import '../../services/data_tools.dart';
import '../widgets/common.dart';

String roleName(Role r) => switch (r) {
      Role.owner => tr('المالك'),
      Role.manager => tr('مدير'),
      Role.reception => tr('استقبال'),
      Role.trainer => tr('مدرب'),
    };

/// اختيار الموظف وإدخال رقمه السري
class LockScreen extends StatelessWidget {
  const LockScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    final staff = g.staff.all.where((s) => s.active && s.pinHash != null).toList();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(padding: const EdgeInsets.all(24), children: [
              const SizedBox(height: 24),
              Icon(Icons.lock_outline, size: 56, color: context.colors.primary),
              const SizedBox(height: 12),
              Text(g.settings.gymName, textAlign: TextAlign.center, style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              Text(tr('من يستخدم التطبيق؟'), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              for (final s in staff)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: ListTile(
                      leading: CircleAvatar(backgroundColor: Color(s.colorValue), child: Text(s.name.characters.first, style: const TextStyle(color: Colors.white))),
                      title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(roleName(s.role)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _login(context, s),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _login(BuildContext context, Staff s) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => PinDialog(staff: s));
    if (ok == true && context.mounted) {
      context.gym.user = s;
      context.gym.touch();
    }
  }
}

class PinDialog extends StatefulWidget {
  final Staff staff;
  const PinDialog({super.key, required this.staff});
  @override
  State<PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<PinDialog> {
  String _pin = '';
  bool _wrong = false;

  void _tap(String k) {
    setState(() {
      _wrong = false;
      if (k == '⌫') {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
      } else if (_pin.length < 8) {
        _pin += k;
      }
    });
    if (_pin.length >= 4 && checkPin(widget.staff, _pin)) Navigator.pop(context, true);
    if (_pin.length >= 6 && !checkPin(widget.staff, _pin)) {
      setState(() {
        _wrong = true;
        _pin = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.staff.name, textAlign: TextAlign.center),
      content: SizedBox(
        width: 280,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_wrong ? tr('رقم سري خاطئ') : tr('أدخل الرقم السري'),
              style: TextStyle(color: _wrong ? context.colors.error : null)),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < 4; i++)
              Container(
                margin: const EdgeInsets.all(6),
                width: 14,
                height: 14,
                decoration: BoxDecoration(shape: BoxShape.circle, color: i < _pin.length ? context.colors.primary : context.colors.outlineVariant),
              ),
          ]),
          const SizedBox(height: 12),
          Directionality(
            textDirection: TextDirection.ltr,
            child: GridView.count(
              shrinkWrap: true,
              crossAxisCount: 3,
              childAspectRatio: 1.6,
              children: [
                for (final k in ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', '⌫'])
                  k.isEmpty
                      ? const SizedBox()
                      : TextButton(onPressed: () => _tap(k), child: Text(k, style: const TextStyle(fontSize: 22))),
              ],
            ),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('إلغاء')))],
    );
  }
}
