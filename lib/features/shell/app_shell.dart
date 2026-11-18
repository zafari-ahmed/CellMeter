import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/providers.dart';
import '../apps/apps_screen.dart';
import '../charging/charging_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../health/health_screen.dart';
import '../history/history_screen.dart';
import '../settings/settings_screen.dart';

/// The five top-level destinations.
///
/// Flat navigation rather than a drawer or nested tabs: every one of these
/// answers a different question about the same battery, and people move
/// between them constantly ("it says 14%/h — which app?"). Burying any of them
/// a level down would make that comparison a chore.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  int _index = 0;

  static const _destinations = <NavigationDestination>[
    NavigationDestination(
      icon: Icon(Icons.speed_outlined),
      selectedIcon: Icon(Icons.speed_rounded),
      label: 'Now',
    ),
    NavigationDestination(
      icon: Icon(Icons.favorite_outline_rounded),
      selectedIcon: Icon(Icons.favorite_rounded),
      label: 'Health',
    ),
    NavigationDestination(
      icon: Icon(Icons.bolt_outlined),
      selectedIcon: Icon(Icons.bolt_rounded),
      label: 'Charging',
    ),
    NavigationDestination(
      icon: Icon(Icons.history_outlined),
      selectedIcon: Icon(Icons.history_rounded),
      label: 'History',
    ),
    NavigationDestination(
      icon: Icon(Icons.apps_outlined),
      selectedIcon: Icon(Icons.apps_rounded),
      label: 'Apps',
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Make sure the sampler is running every time the app is opened, in case
    // the system stopped the service while the app was away.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(batteryChannelProvider).startMonitoring();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back to the foreground is the moment the on-screen figures are
    // most likely to be stale: the sampler has been spooling the whole time
    // the app was away.
    if (state == AppLifecycleState.resumed) {
      ref.read(syncControllerProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keeps the home screen widgets fed while the app is open. The sampler
    // keeps them live when it is not.
    ref.watch(widgetFeedProvider);

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          DashboardScreen(),
          HealthScreen(),
          ChargingScreen(),
          HistoryScreen(),
          AppsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: _destinations,
      ),
      floatingActionButton: _index == 0
          ? FloatingActionButton.small(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SettingsScreen(),
                ),
              ),
              tooltip: 'Settings',
              child: const Icon(Icons.settings_rounded),
            )
          : null,
    );
  }
}
