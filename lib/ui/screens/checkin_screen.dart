import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/money.dart';
import '../../models/business.dart';
import '../../models/member.dart';
import '../../services/checkin.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import 'dashboard_screen.dart';
import 'kiosk_screen.dart';
import 'member_detail_screen.dart';
import 'sale_screen.dart';

class CheckinScreen extends StatefulWidget {
  const CheckinScreen({super.key});
  @override
  State<CheckinScreen> createState() => _CheckinScreenState();
}

class _CheckinScreenState extends State<CheckinScreen> {
  final _q = TextEditingController();
  final _focus = FocusNode();
  bool _camera = false;
  MobileScannerController? _scanner;
  CheckinDecision? _last;
  bool _lastCommitted = false;
  String? _lastCode;
  DateTime _lastScanAt = DateTime(2000);

  @override
  void dispose() {
    _scanner?.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _toggleCamera() {
    setState(() {
      _camera = !_camera;
      if (_camera) {
        _scanner = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates, formats: const [BarcodeFormat.qrCode, BarcodeFormat.code128, BarcodeFormat.ean13]);
      } else {
        _scanner?.dispose();
        _scanner = null;
      }
    });
  }

  /// مسح بطاقة (كاميرا أو قارئ باركود USB/بلوتوث يكتب الرمز ثم Enter)
  Future<void> _scan(String raw, {String method = 'scan'}) async {
    final now = DateTime.now();
    if (raw == _lastCode && now.difference(_lastScanAt).inSeconds < 4) return;
    _lastCode = raw;
    _lastScanAt = now;
    final m = context.services.members.resolveScan(raw);
    await _process(m, method: method);
  }

  Future<void> _process(Member? m, {String method = 'manual'}) async {
    final sv = context.services;
    final dec = sv.checkin.evaluate(m);
    setState(() {
      _last = dec;
      _lastCommitted = false;
      _q.clear();
    });
    if (dec.member == null) {
      HapticFeedback.heavyImpact();
      return;
    }
    if (dec.allowed) {
      HapticFeedback.mediumImpact();
      SystemSound.play(SystemSoundType.click);
      await sv.checkin.commit(dec, method: method);
      if (mounted) setState(() => _lastCommitted = true);
    } else {
      HapticFeedback.heavyImpact();
      await sv.checkin.commit(dec, method: method); // تسجيل المحاولة المرفوضة للتقارير
    }
  }

  Future<void> _override() async {
    final dec = _last;
    if (dec == null) return;
    final ok = await confirm(context, tr('سماح استثنائي بالدخول؟'), message: dec.message, ok: tr('سماح'));
    if (!ok || !mounted) return;
    await runAction(context, () => context.services.checkin.commit(dec, override: true), success: tr('سُجل الدخول استثنائياً'));
    if (mounted) setState(() => _lastCommitted = true);
  }

  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    final sv = context.services;
    final inGym = sv.checkin.inGymNow();
    final today = sv.checkin.today();
    final results = _q.text.trim().isEmpty ? <Member>[] : sv.members.search(_q.text).take(8).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('تسجيل الدخول')),
        actions: [
          Center(child: Pill(tr('في النادي: {n}', {'n': inGym.length}), brandSeed, icon: Icons.directions_run)),
          IconButton(
            tooltip: tr('شاشة الدخول الذاتي'),
            icon: const Icon(Icons.tablet_android),
            onPressed: () => context.push(const KioskScreen()),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _q,
                focusNode: _focus,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: tr('امسح البطاقة أو اكتب الاسم / الجوال / الرقم'),
                  prefixIcon: const Icon(Icons.search),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (v) {
                  if (v.trim().isEmpty) return;
                  final exact = sv.members.resolveScan(v);
                  if (exact != null) {
                    _scan(v);
                  } else if (results.length == 1) {
                    _process(results.first);
                  }
                  _focus.requestFocus();
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              iconSize: 28,
              style: IconButton.styleFrom(minimumSize: const Size(52, 52)),
              tooltip: tr('الكاميرا'),
              onPressed: _toggleCamera,
              icon: Icon(_camera ? Icons.videocam_off : Icons.qr_code_scanner),
            ),
          ]),
        ),
        if (_camera && _scanner != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 240,
                child: Stack(fit: StackFit.expand, children: [
                  MobileScanner(
                    controller: _scanner!,
                    onDetect: (cap) {
                      final v = cap.barcodes.isEmpty ? null : cap.barcodes.first.rawValue;
                      if (v != null) _scan(v);
                    },
                    errorBuilder: (c, e) => Center(child: Text(tr('تعذر تشغيل الكاميرا'), style: const TextStyle(color: Colors.white))),
                  ),
                  Center(
                    child: Container(
                      width: 170,
                      height: 170,
                      decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 3), borderRadius: BorderRadius.circular(18)),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        for (final m in results)
          ListTile(
            leading: MemberAvatar(m),
            title: Text(m.name),
            subtitle: Text('#${m.code} • ${m.phone}'),
            trailing: StatePill(sv.members.stateOf(m.id)),
            onTap: () => _process(m),
          ),
        if (_last != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: CheckinResultCard(
              dec: _last!,
              committed: _lastCommitted,
              onOverride: _last!.overridable && g.can(Perm.override) && !_lastCommitted ? _override : null,
              onRenew: _last!.member == null || !g.can(Perm.sell) ? null : () => context.push(SaleScreen(memberId: _last!.member!.id)),
              onOpen: _last!.member == null ? null : () => context.push(MemberDetailScreen(memberId: _last!.member!.id)),
              onCollect: _last!.member == null || _last!.balance <= 0 || !g.can(Perm.sell) ? null : () => showCollectDialog(context, memberId: _last!.member!.id),
            ),
          ),
        if (_last == null && results.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              Icon(Icons.qr_code_2, size: 72, color: context.colors.outline),
              const SizedBox(height: 8),
              Text(tr('اطلب من العضو عرض بطاقته (QR) أو اكتب اسمه'), textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text(tr('يعمل أيضاً مع قارئ الباركود الموصول بالجهاز'), textAlign: TextAlign.center, style: context.text.bodySmall),
            ]),
          ),
        Section(
          title: tr('زيارات اليوم ({n})', {'n': today.where((c) => c.allowed).length}),
          child: today.isEmpty
              ? Text(tr('لا زيارات بعد'), style: TextStyle(color: context.colors.onSurfaceVariant))
              : Card(
                  child: Column(children: [
                    for (final c in today.take(50))
                      if (g.members[c.memberId] case final m?)
                        ListTile(
                          dense: true,
                          leading: MemberAvatar(m, radius: 16),
                          title: Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: c.allowed ? null : Text(checkinResultText(c.result), style: TextStyle(color: context.colors.error)),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            if (inGym.any((x) => x.id == c.id)) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.circle, size: 8, color: StatusColors.active)),
                            Text(hhmm(minutesOfDay(c.time)), style: const TextStyle(fontWeight: FontWeight.w700)),
                          ]),
                          onTap: () => context.push(MemberDetailScreen(memberId: m.id)),
                        ),
                  ]),
                ),
        ),
      ]),
    );
  }
}

/// بطاقة نتيجة الدخول: خضراء عند السماح وحمراء عند الرفض
class CheckinResultCard extends StatelessWidget {
  final CheckinDecision dec;
  final bool committed;
  final bool large;
  final VoidCallback? onOverride, onRenew, onOpen, onCollect;
  const CheckinResultCard({super.key, required this.dec, this.committed = false, this.large = false, this.onOverride, this.onRenew, this.onOpen, this.onCollect});

  @override
  Widget build(BuildContext context) {
    final ok = dec.allowed;
    final color = ok ? StatusColors.active : StatusColors.expired;
    final m = dec.member;
    final s = dec.sub;
    return Card(
      color: color.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: color, width: 2)),
      child: Padding(
        padding: EdgeInsets.all(large ? 28 : 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            if (m != null) MemberAvatar(m, radius: large ? 56 : 32, ring: color) else Icon(Icons.help_outline, size: large ? 100 : 56, color: color),
            SizedBox(width: large ? 24 : 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(ok ? Icons.check_circle : Icons.cancel, color: color, size: large ? 40 : 26),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(ok ? tr('مسموح') : tr('مرفوض'),
                        style: (large ? context.text.displaySmall : context.text.titleLarge)?.copyWith(color: color, fontWeight: FontWeight.w900)),
                  ),
                ]),
                if (m != null) Text(m.name, style: (large ? context.text.headlineMedium : context.text.titleMedium)?.copyWith(fontWeight: FontWeight.w800)),
                Text(dec.message, style: (large ? context.text.titleLarge : context.text.bodyLarge)?.copyWith(color: ok ? null : color, fontWeight: FontWeight.w600)),
              ]),
            ),
          ]),
          if (s != null && m != null) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 6, children: [
              Pill(s.planName, brandSeed, icon: Icons.card_membership),
              if (dec.visitsLeft != null) Pill(tr('{n} حصة متبقية', {'n': dec.visitsLeft}), const Color(0xFF6366F1))
              else if (dec.daysLeft != null && dec.daysLeft! >= 0) Pill(tr('ينتهي {d}', {'d': fmtDay(s.end)}), const Color(0xFF6366F1)),
              if (dec.balance > 0) Pill(tr('عليه {a}', {'a': fmtMoney(dec.balance)}), StatusColors.expired, icon: Icons.account_balance_wallet_outlined),
            ]),
          ],
          for (final w in dec.warnings)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                const Icon(Icons.info_outline, size: 18, color: StatusColors.expiring),
                const SizedBox(width: 6),
                Expanded(child: Text(w, style: TextStyle(fontSize: large ? 18 : 14))),
              ]),
            ),
          if (!large && (onOverride != null || onRenew != null || onOpen != null || onCollect != null)) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (!ok && onRenew != null) FilledButton.icon(onPressed: onRenew, icon: const Icon(Icons.autorenew), label: Text(tr('تجديد'))),
              if (onCollect != null) OutlinedButton.icon(onPressed: onCollect, icon: const Icon(Icons.payments_outlined), label: Text(tr('تحصيل'))),
              if (onOverride != null) OutlinedButton.icon(onPressed: onOverride, icon: const Icon(Icons.admin_panel_settings_outlined), label: Text(tr('سماح استثنائي'))),
              if (onOpen != null) TextButton(onPressed: onOpen, child: Text(tr('الملف'))),
            ]),
          ],
          if (committed && !large)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(tr('سُجّل الدخول {t}', {'t': hhmm(minutesOfDay(DateTime.now()))}), style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 12)),
            ),
        ]),
      ),
    );
  }
}

/// مؤقت بسيط لإخفاء النتيجة (يُستخدم في شاشة الدخول الذاتي)
class ResetTimer {
  Timer? _t;
  void start(Duration d, VoidCallback f) {
    _t?.cancel();
    _t = Timer(d, f);
  }

  void cancel() => _t?.cancel();
}
