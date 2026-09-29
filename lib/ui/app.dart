import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import '../data/gym_data.dart';
import 'app_services.dart';
import 'screens/lock_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/shell.dart';
import 'theme.dart';

class GymApp extends StatefulWidget {
  final GymData gym;
  final bool startBackground;
  const GymApp({super.key, required this.gym, this.startBackground = true});

  @override
  State<GymApp> createState() => _GymAppState();
}

class _GymAppState extends State<GymApp> with WidgetsBindingObserver {
  late final AppServices services = AppServices(widget.gym);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.startBackground) services.start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    services.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) services.onResume();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<GymData>.value(value: widget.gym),
        Provider<AppServices>.value(value: services),
      ],
      child: Selector<GymData, (String, String)>(
        selector: (_, g) => (g.settings.language, g.settings.themeMode),
        builder: (context, v, _) => MaterialApp(
          title: v.$1 == 'ar' ? 'نادي جيم' : 'Nadi Gym',
          debugShowCheckedModeBanner: false,
          locale: Locale(v.$1),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: switch (v.$2) { 'light' => ThemeMode.light, 'dark' => ThemeMode.dark, _ => ThemeMode.system },
          home: const RootGate(),
        ),
      ),
    );
  }
}

/// أول تشغيل ← الإعداد، وإن كان القفل مفعلاً ← اختيار الموظف والرقم السري
class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    final g = context.watch<GymData>();
    if (!g.settings.onboarded) return const OnboardingScreen();
    final needsPin = g.settings.requirePin && g.staff.all.any((s) => s.active && s.pinHash != null);
    if (needsPin && g.user == null) return const LockScreen();
    return const Shell();
  }
}
