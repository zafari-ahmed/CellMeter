import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/providers.dart';
import '../../core/theme/app_colors.dart';
import '../shell/app_shell.dart';

/// First run.
///
/// Three jobs, in order of how much they affect whether the app works at all:
/// explain that measurement takes time, get the permissions that let it
/// happen, and start the sampler. The expectation-setting comes first
/// deliberately — the most common way an app like this gets uninstalled is a
/// user opening it an hour later, seeing no health figure, and concluding it
/// is broken.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await ref.read(batteryChannelProvider).startMonitoring();
    await ref.read(appPreferencesProvider.notifier).completeOnboarding();
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const AppShell()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (index) => setState(() => _page = index),
                children: const [
                  _Page(
                    icon: Icons.insights_rounded,
                    title: 'Measured, not guessed',
                    body: 'CellMeter reads your battery\'s own charge gauge to '
                        'work out what it really holds today — not what the '
                        'manufacturer claimed when it was new.',
                  ),
                  _Page(
                    icon: Icons.schedule_rounded,
                    title: 'This takes a little time',
                    body: 'Capacity is measured while charging. One session '
                        'covering 20% of the battery gives a first estimate; '
                        'a few more make it accurate.\n\n'
                        'You never need to charge to 100%.',
                  ),
                  _PermissionsPage(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < 3; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: i == _page ? 22 : 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: i == _page
                                ? AppColors.primary
                                : theme.colorScheme.outlineVariant,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        if (_page < 2) {
                          _controller.nextPage(
                            duration: const Duration(milliseconds: 280),
                            curve: Curves.easeOutCubic,
                          );
                        } else {
                          _finish();
                        }
                      },
                      child: Text(_page < 2 ? 'Next' : 'Start monitoring'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 44, color: AppColors.primary),
          ),
          const SizedBox(height: 32),
          Text(
            title,
            style: theme.textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          Text(
            body,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// The permissions that decide whether measurement is accurate or full of
/// holes, each with the consequence of skipping it stated plainly.
class _PermissionsPage extends ConsumerWidget {
  const _PermissionsPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final unrestricted = ref.watch(batteryOptimizationProvider).value;
    final usageAccess = ref.watch(usageAccessProvider).value;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Two things to allow', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Both are optional. CellMeter will tell you what it cannot do '
            'without them rather than nagging.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          _PermissionTile(
            icon: Icons.battery_saver_rounded,
            title: 'Run without restrictions',
            body: 'Android suspends background work to save power. If it '
                'suspends CellMeter mid-charge, that charge cannot be used to '
                'measure capacity.',
            granted: unrestricted == true,
            onGrant: () async {
              await ref
                  .read(batteryChannelProvider)
                  .requestIgnoreBatteryOptimizations();
              ref.invalidate(batteryOptimizationProvider);
            },
          ),
          const SizedBox(height: 14),
          _PermissionTile(
            icon: Icons.apps_rounded,
            title: 'Usage access',
            body: 'Lets CellMeter see which app was on screen, so battery use '
                'can be attributed to apps. Without it everything else still '
                'works; the Apps screen stays empty.',
            granted: usageAccess == true,
            onGrant: () async {
              await ref.read(batteryChannelProvider).openUsageAccessSettings();
              ref.invalidate(usageAccessProvider);
            },
          ),
          const SizedBox(height: 20),
          Text(
            'CellMeter has no network permission. Nothing it measures can '
            'leave this device.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  const _PermissionTile({
    required this.icon,
    required this.title,
    required this.body,
    required this.granted,
    required this.onGrant,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool granted;
  final VoidCallback onGrant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  granted ? Icons.check_circle_rounded : icon,
                  color: granted
                      ? AppColors.primary
                      : theme.colorScheme.onSurfaceVariant,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleSmall),
                ),
                if (!granted)
                  TextButton(onPressed: onGrant, child: const Text('Allow')),
              ],
            ),
            const SizedBox(height: 6),
            Text(body, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
