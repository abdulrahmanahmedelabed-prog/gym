import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../models/member.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// بطاقة العضو الرقمية: يعرضها العضو من جواله عند الدخول (أو تُطبع)
Future<void> showMemberCard(BuildContext context, Member m) =>
    showDialog(context: context, builder: (_) => _MemberCardDialog(member: m));

class _MemberCardDialog extends StatefulWidget {
  final Member member;
  const _MemberCardDialog({required this.member});
  @override
  State<_MemberCardDialog> createState() => _MemberCardDialogState();
}

class _MemberCardDialogState extends State<_MemberCardDialog> {
  final _key = GlobalKey();

  Future<void> _shareImage() async {
    final boundary = _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final img = await boundary.toImage(pixelRatio: 3);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    if (data == null || !mounted) return;
    final m = widget.member;
    await context.services.shareFile(data.buffer.asUint8List(), 'card-${m.code}.png', 'image/png',
        text: tr('بطاقة عضويتك في {g} — اعرضها عند الدخول', {'g': context.gym.settings.gymName}));
  }

  Future<void> _print() async {
    final sv = context.services;
    final m = widget.member;
    final sub = sv.members.currentSub(m.id);
    final bytes = await (await sv.pdf()).memberCard(m, subtitle: sub == null ? null : '${sub.planName} • ${dayKey(sub.end)}');
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'card-${m.code}');
  }

  @override
  Widget build(BuildContext context) {
    final g = context.gym;
    final m = widget.member;
    final sub = context.services.members.currentSub(m.id);
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          RepaintBoundary(
            key: _key,
            child: MemberCardView(member: m, gymName: g.settings.gymName, logo: g.settings.logo, subtitle: sub == null ? null : '${sub.planName} • ${tr('حتى')} ${dayKey(sub.end)}'),
          ),
          const SizedBox(height: 12),
          Text(tr('يمسح موظف الاستقبال الرمز من شاشة «الدخول»'), textAlign: TextAlign.center, style: context.text.bodySmall),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: FilledButton.icon(onPressed: () => runAction(context, _shareImage), icon: const Icon(Icons.share), label: Text(tr('مشاركة')))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(onPressed: () => runAction(context, _print), icon: const Icon(Icons.print_outlined), label: Text(tr('طباعة')))),
          ]),
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('إغلاق'))),
        ]),
      ),
    );
  }
}

class MemberCardView extends StatelessWidget {
  final Member member;
  final String gymName;
  final String? logo;
  final String? subtitle;
  const MemberCardView({super.key, required this.member, required this.gymName, this.logo, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 340,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(colors: [Color(0xFF0F766E), Color(0xFF134E4A)], begin: Alignment.topRight, end: Alignment.bottomLeft),
      ),
      child: Column(children: [
        Row(children: [
          if (logo != null)
            ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(base64Decode(logo!), width: 32, height: 32, fit: BoxFit.cover))
          else
            const Icon(Icons.fitness_center, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(child: Text(gymName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17, fontFamily: fontFamily))),
        ]),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
          child: QrImageView(data: member.qrData, size: 190, padding: EdgeInsets.zero),
        ),
        const SizedBox(height: 14),
        Row(children: [
          MemberAvatar(member, radius: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(member.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16, fontFamily: fontFamily)),
              Text('#${member.code}${subtitle == null ? '' : ' • $subtitle'}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: fontFamily)),
            ]),
          ),
        ]),
      ]),
    );
  }
}
