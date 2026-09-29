import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/i18n.dart';
import '../../core/ids.dart';
import '../../models/settings.dart';
import '../widgets/common.dart';
import '../widgets/pay_widgets.dart';

/// حسابات استلام الدفع: محافظ (جوال باي، بال باي...) وحسابات بنكية ورمز iBuraq الموحد
class PayAccountsScreen extends StatelessWidget {
  const PayAccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    final list = g.settings.payAccounts;
    return Scaffold(
      appBar: AppBar(title: Text(tr('حسابات استلام الدفع'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => editPayAccount(context, null),
        icon: const Icon(Icons.add),
        label: Text(tr('حساب')),
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 88), children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            tr('أضف المحافظ والحسابات التي يحوّل لها الأعضاء. ولكل حساب ضع رمز QR الموحد (iBuraq QR Quick) من تطبيق بنكك أو محفظتك: '
                'يظهر للعضو عند الدفع ليمسحه من أي تطبيق بنكي أو محفظة، ويُرسل له مع طلبات الدفع والتجديد، ويُطبع على الفاتورة.'),
            style: TextStyle(color: context.colors.onSurfaceVariant),
          ),
        ),
        if (list.isEmpty) EmptyState(icon: Icons.account_balance_wallet_outlined, title: tr('لا توجد حسابات')),
        for (final a in list)
          ListTile(
            leading: CircleAvatar(child: Icon(a.type == 'wallet' ? Icons.phone_iphone : Icons.account_balance)),
            title: Text(a.name, style: TextStyle(fontWeight: FontWeight.w700, decoration: a.active ? null : TextDecoration.lineThrough)),
            subtitle: Text([a.number, if (a.holder.isNotEmpty) a.holder, if (a.qr.isNotEmpty) tr('✓ رمز QR')].join(' • ')),
            trailing: a.qr.isEmpty
                ? null
                : IconButton(icon: const Icon(Icons.qr_code_2), onPressed: () => showPayQrDialog(context, a, 0)),
            onTap: () => editPayAccount(context, a),
          ),
      ]),
    );
  }
}

Future<void> editPayAccount(BuildContext context, PayAccount? a0) async {
  final g = context.gym;
  final a = a0 ?? PayAccount(id: newId(), name: walletPresets.first);
  final name = TextEditingController(text: a.name);
  final number = TextEditingController(text: a.number);
  final holder = TextEditingController(text: a.holder);
  final qr = TextEditingController(text: a.qr);
  final r = await showDialog<String>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: Text(a0 == null ? tr('حساب استلام جديد') : a.name),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'wallet', label: Text(tr('محفظة')), icon: const Icon(Icons.phone_iphone)),
                  ButtonSegment(value: 'bank', label: Text(tr('بنك / iBuraq')), icon: const Icon(Icons.account_balance)),
                ],
                selected: {a.type},
                onSelectionChanged: (v) => set(() => a.type = v.first),
              ),
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final p in a.type == 'wallet' ? walletPresets : bankPresets)
                  ActionChip(label: Text(p), onPressed: () => set(() => name.text = p)),
              ]),
              const SizedBox(height: 10),
              TextField(controller: name, decoration: InputDecoration(labelText: tr('الاسم'))),
              const SizedBox(height: 10),
              TextField(
                controller: number,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: a.type == 'wallet' ? tr('رقم المحفظة') : tr('رقم الحساب / IBAN / المعرّف')),
              ),
              const SizedBox(height: 10),
              TextField(controller: holder, decoration: InputDecoration(labelText: tr('اسم صاحب الحساب'))),
              const SizedBox(height: 14),
              Text(tr('رمز QR الموحد لهذا الحساب'), style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (canScanWithCamera)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.qr_code_scanner),
                    label: Text(tr('مسح بالكاميرا')),
                    onPressed: () async {
                      final v = await Navigator.of(c).push<String>(MaterialPageRoute(builder: (_) => const ScanQrScreen()));
                      if (v != null) set(() => qr.text = v);
                    },
                  ),
                if (canScanWithCamera)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.image_outlined),
                    label: Text(tr('من صورة')),
                    onPressed: () async {
                      final x = await ImagePicker().pickImage(source: ImageSource.gallery);
                      if (x == null) return;
                      try {
                        final cap = await MobileScannerController().analyzeImage(x.path);
                        final v = cap?.barcodes.firstOrNull?.rawValue;
                        if (v == null) throw Exception();
                        set(() => qr.text = v);
                      } catch (_) {
                        if (c.mounted) ScaffoldMessenger.maybeOf(c)?.showSnackBar(SnackBar(content: Text(tr('لم يُعثر على رمز QR في الصورة'))));
                      }
                    },
                  ),
              ]),
              const SizedBox(height: 8),
              TextField(
                controller: qr,
                minLines: 1,
                maxLines: 3,
                textDirection: TextDirection.ltr,
                onChanged: (_) => set(() {}),
                decoration: InputDecoration(labelText: tr('محتوى الرمز (أو الصقه هنا)')),
              ),
              if (qr.text.trim().isNotEmpty)
                Center(child: Padding(padding: const EdgeInsets.only(top: 10), child: Container(color: Colors.white, padding: const EdgeInsets.all(6), child: QrImageView(data: qr.text.trim(), size: 140)))),
              const SizedBox(height: 6),
              Text(
                tr('من تطبيق البنك أو المحفظة: افتح «استلام» أو «QR Quick» واعرض رمز حسابك بدون مبلغ، ثم امسحه بالكاميرا أو احفظه صورة واختره من «من صورة».'),
                style: Theme.of(c).textTheme.bodySmall,
              ),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(tr('فعّال')), value: a.active, onChanged: (v) => set(() => a.active = v)),
            ]),
          ),
        ),
        actions: [
          if (a0 != null) TextButton(onPressed: () => Navigator.pop(c, 'delete'), child: Text(tr('حذف'))),
          TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('إلغاء'))),
          FilledButton(onPressed: () => Navigator.pop(c, 'save'), child: Text(tr('حفظ'))),
        ],
      ),
    ),
  );
  if (r == null) return;
  final list = g.settings.payAccounts;
  list.removeWhere((x) => x.id == a.id);
  if (r == 'save' && name.text.trim().isNotEmpty) {
    a
      ..name = name.text.trim()
      ..number = number.text.trim()
      ..holder = holder.text.trim()
      ..qr = qr.text.trim();
    final i = (g.settings.payAccounts.indexWhere((x) => x.id == a.id));
    if (i >= 0) {
      list.insert(i, a);
    } else {
      list.add(a);
    }
  }
  g.settings.payAccounts = list;
  await g.saveSettings();
}

/// شاشة مسح رمز QR وإرجاع محتواه
class ScanQrScreen extends StatelessWidget {
  const ScanQrScreen({super.key});
  @override
  Widget build(BuildContext context) {
    var done = false;
    return Scaffold(
      appBar: AppBar(title: Text(tr('امسح رمز QR'))),
      body: MobileScanner(
        onDetect: (cap) {
          final v = cap.barcodes.firstOrNull?.rawValue;
          if (v == null || done) return;
          done = true;
          Navigator.pop(context, v);
        },
      ),
    );
  }
}
