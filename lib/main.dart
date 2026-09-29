import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'data/db_factory.dart';
import 'data/gym_data.dart';
import 'services/demo_data.dart';
import 'services/sync.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await openGymDatabase('nadi_gym.db');
  final gym = await GymData.open(db);
  // نسخة الويب التجريبية تفتح مباشرة على نادٍ تجريبي كامل (مع شاشة انتظار أثناء تجهيزه أول مرة)
  if (kIsWeb && gym.isEmpty) {
    runApp(const _PreparingDemo());
    await DemoData(gym).generate();
  }
  // المزامنة تُحمَّل قبل أي تعديل حتى لا يفوتها شيء
  final sync = SyncService(gym);
  await sync.load();
  runApp(GymApp(gym: gym, sync: sync));
}

class _PreparingDemo extends StatelessWidget {
  const _PreparingDemo();

  @override
  Widget build(BuildContext context) => const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Color(0xFF0F766E),
          body: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text('جاري تجهيز نادٍ تجريبي…', textDirection: TextDirection.rtl, style: TextStyle(color: Colors.white, fontSize: 18)),
            ]),
          ),
        ),
      );
}
