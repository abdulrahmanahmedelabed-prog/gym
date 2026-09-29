import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// يحفظ صور الشاشات التي يلتقطها الاختبار على المحاكي في مجلد screenshots
Future<void> main() => integrationDriver(
      onScreenshot: (name, bytes, [args]) async {
        final f = File('screenshots/$name.png');
        await f.create(recursive: true);
        await f.writeAsBytes(bytes);
        return true;
      },
    );
