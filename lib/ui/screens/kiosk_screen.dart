import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/i18n.dart';
import '../../services/checkin.dart';
import '../widgets/common.dart';
import 'checkin_screen.dart';

/// شاشة الدخول الذاتي: جهاز لوحي عند الباب، العضو يمسح بطاقته بنفسه.
/// للخروج: اضغط مطولاً على اسم النادي.
class KioskScreen extends StatefulWidget {
  const KioskScreen({super.key});
  @override
  State<KioskScreen> createState() => _KioskScreenState();
}

class _KioskScreenState extends State<KioskScreen> {
  final _scanner = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates, facing: CameraFacing.front);
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _reset = ResetTimer();
  CheckinDecision? _dec;
  String? _lastCode;
  DateTime _lastAt = DateTime(2000);

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _scanner.dispose();
    _reset.cancel();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _scan(String raw) async {
    final now = DateTime.now();
    if (raw == _lastCode && now.difference(_lastAt).inSeconds < 6) return;
    _lastCode = raw;
    _lastAt = now;
    final sv = context.services;
    final dec = sv.checkin.evaluate(sv.members.resolveScan(raw));
    setState(() => _dec = dec);
    if (dec.member != null) await sv.checkin.commit(dec, method: 'kiosk');
    dec.allowed ? HapticFeedback.mediumImpact() : HapticFeedback.heavyImpact();
    _reset.start(const Duration(seconds: 5), () {
      if (mounted) setState(() => _dec = null);
    });
    _input.clear();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final g = context.gymWatch;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          GestureDetector(
            onLongPress: () => Navigator.pop(context),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(g.settings.gymName, style: context.text.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
            ),
          ),
          // قارئ الباركود الخارجي يكتب هنا
          SizedBox(
            width: 1,
            height: 1,
            child: TextField(controller: _input, focusNode: _focus, autofocus: true, onSubmitted: _scan),
          ),
          Expanded(
            child: _dec != null
                ? Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Padding(padding: const EdgeInsets.all(24), child: CheckinResultCard(dec: _dec!, large: true)),
                    ),
                  )
                : Column(children: [
                    Text(tr('امسح بطاقتك للدخول'), style: context.text.headlineSmall),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: MobileScanner(
                            controller: _scanner,
                            onDetect: (cap) {
                              final v = cap.barcodes.isEmpty ? null : cap.barcodes.first.rawValue;
                              if (v != null) _scan(v);
                            },
                            errorBuilder: (c, e) => Container(
                              color: Colors.black,
                              alignment: Alignment.center,
                              child: Text(tr('الكاميرا غير متاحة — استخدم قارئ الباركود'), style: const TextStyle(color: Colors.white)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ]),
          ),
        ]),
      ),
    );
  }
}
