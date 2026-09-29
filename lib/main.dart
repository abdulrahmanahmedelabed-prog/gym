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
  // نسخة الويب التجريبية تفتح مباشرة على نادٍ تجريبي كامل
  if (kIsWeb && gym.isEmpty) {
    await DemoData(gym).generate();
  }
  // المزامنة تُحمَّل قبل أي تعديل حتى لا يفوتها شيء
  final sync = SyncService(gym);
  await sync.load();
  runApp(GymApp(gym: gym, sync: sync));
}
