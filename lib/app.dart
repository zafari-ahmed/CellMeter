import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/state/providers.dart';
import 'core/theme/app_theme.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/shell/app_shell.dart';

/// Root widget.
///
/// Rebuilds on a platform brightness change so "follow system" switches themes
/// live rather than at the next cold start.
class CellMeterApp extends ConsumerStatefulWidget {
  const CellMeterApp({super.key});

  @override
  ConsumerState<CellMeterApp> createState() => _CellMeterAppState();
}

class _CellMeterAppState extends ConsumerState<CellMeterApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(appPreferencesProvider);
    final brightness = MediaQuery.platformBrightnessOf(context);
    final mode = prefs.value?.themeMode ?? AppThemeMode.system;

    return MaterialApp(
      title: 'CellMeter',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.of(mode, brightness),
      home: prefs.when(
        loading: () => const _Splash(),
        error: (_, _) => const AppShell(),
        data: (value) =>
            value.onboardingComplete ? const AppShell() : const OnboardingScreen(),
      ),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
}
