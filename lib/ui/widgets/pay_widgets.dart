import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/i18n.dart';
import '../../core/money.dart';
import '../../models/billing.dart';
import '../../models/settings.dart';
import '../../services/license.dart';
import '../../services/reports.dart';
import 'common.dart';

IconData payMethodIconOf(PayMethod m) => switch (m) {
      PayMethod.cash => Icons.payments_outlined,
      PayMethod.card => Icons.credit_card,
      PayMethod.transfer => Icons.account_balance_outlined,
      PayMethod.wallet => Icons.phone_iphone,
      PayMethod.online => Icons.language,
    };

/// اختيار طريقة الدفع والحساب المستلم ورقم العملية
class PayChoice {
  PayMethod method = PayMethod.cash;
  PayAccount? account;
  final reference = TextEditingController();
  bool verified = false;

  bool get needsAccount => method == PayMethod.wallet || method == PayMethod.transfer;
  String? get ref => reference.text.trim().isEmpty ? null : reference.text.trim();
  String? get accountName => needsAccount ? account?.name : null;
  bool get isVerified => !needsAccount || verified;
}

class PayPicker extends StatefulWidget {
  final PayChoice choice;
  final double amount;
  final VoidCallback? onChanged;
  const PayPicker({super.key, required this.choice, required this.amount, this.onChanged});

  @override
  State<PayPicker> createState() => _PayPickerState();
}

class _PayPickerState extends State<PayPicker> {
  PayChoice get c => widget.choice;

  void _set(VoidCallback f) {
    setState(f);
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    final accounts = g.has(Feature.walletQr) ? g.settings.activeAccounts : <PayAccount>[];
    final forMethod = accounts.where((a) => c.method == PayMethod.wallet ? a.type == 'wallet' : a.type == 'bank').toList();
    if (c.needsAccount && (c.account == null || !forMethod.contains(c.account)) && forMethod.isNotEmpty) c.account = forMethod.first;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final m in PayMethod.values.where((x) => x != PayMethod.online))
          ChoiceChip(
            avatar: Icon(payMethodIconOf(m), size: 18),
            label: Text(payMethodName(m)),
            selected: c.method == m,
            onSelected: (_) => _set(() => c.method = m),
          ),
      ]),
      if (c.needsAccount) ...[
        const SizedBox(height: 10),
        if (forMethod.isNotEmpty)
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final a in forMethod)
              ChoiceChip(
                label: Text(a.name),
                selected: identical(c.account, a) || c.account?.id == a.id,
                onSelected: (_) => _set(() => c.account = a),
              ),
          ]),
        if (c.account != null && c.account!.qr.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              onPressed: () => showPayQrDialog(context, c.account!, widget.amount),
              icon: const Icon(Icons.qr_code_2),
              label: Text(tr('اعرض رمز QR ليدفع العضو')),
            ),
          ),
        const SizedBox(height: 10),
        TextField(controller: c.reference, decoration: InputDecoration(labelText: tr('رقم العملية / الحوالة'), prefixIcon: const Icon(Icons.tag))),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(tr('تأكدت من وصول المبلغ إلى الحساب')),
          subtitle: Text(tr('وإلا تبقى الدفعة في «المطابقة» حتى تتأكد')),
          value: c.verified,
          onChanged: (v) => _set(() => c.verified = v ?? false),
        ),
      ] else if (c.method == PayMethod.card)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: TextField(controller: c.reference, decoration: InputDecoration(labelText: tr('رقم العملية (اختياري)'), prefixIcon: const Icon(Icons.tag))),
        ),
    ]);
  }
}

/// رمز QR كبير يمسحه العضو من تطبيق البنك أو المحفظة
Future<void> showPayQrDialog(BuildContext context, PayAccount a, double amount, {String? note}) => showDialog(
      context: context,
      builder: (c) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(a.name, style: Theme.of(c).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            if (amount > 0) Text(fmtMoney(amount), style: Theme.of(c).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            Container(color: Colors.white, padding: const EdgeInsets.all(10), child: QrImageView(data: a.qr, size: 260)),
            const SizedBox(height: 10),
            Text(a.number, textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w700)),
            if (a.holder.isNotEmpty) Text(a.holder),
            const SizedBox(height: 8),
            Text(note ?? tr('امسح الرمز من تطبيق البنك أو المحفظة (iBuraq) وادفع المبلغ'), textAlign: TextAlign.center, style: Theme.of(c).textTheme.bodySmall),
            const SizedBox(height: 8),
            TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('إغلاق'))),
          ]),
        ),
      ),
    );

/// صورة PNG لرمز QR مع اسم الحساب والمبلغ (لإرسالها بواتساب)
Future<Uint8List> payQrPng(PayAccount a, {double amount = 0, String title = ''}) async {
  const size = 720.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, size, size + 220), Paint()..color = Colors.white);
  void text(String s, double y, double fontSize, {FontWeight w = FontWeight.w700}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(color: Colors.black, fontSize: fontSize, fontWeight: w, fontFamily: 'Tajawal')),
      textDirection: TextDirection.rtl,
      textAlign: TextAlign.center,
    )..layout(maxWidth: size - 40);
    tp.paint(canvas, Offset((size - tp.width) / 2, y));
  }

  text(title.isEmpty ? a.name : title, 20, 40);
  if (amount > 0) text(fmtMoney(amount), 80, 44, w: FontWeight.w900);
  final painter = QrPainter(data: a.qr, version: QrVersions.auto, gapless: true);
  canvas.save();
  canvas.translate(110, 150);
  painter.paint(canvas, const Size(500, 500));
  canvas.restore();
  text('${a.name}: ${a.number}', 670, 28);
  text(tr('امسح الرمز من أي تطبيق بنكي أو محفظة'), 720, 24, w: FontWeight.w400);
  final img = await recorder.endRecording().toImage(size.toInt(), (size + 220).toInt());
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

bool get canScanWithCamera => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
