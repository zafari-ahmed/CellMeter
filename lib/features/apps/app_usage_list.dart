import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../domain/analytics/app_attributor.dart';
import 'app_detail_sheet.dart';

/// The ranked list of apps, with icons and a tap target.
///
/// Replaces the generic bar list on this screen specifically, because an app
/// row needs to be openable — a user who sees something near the top wants to
/// act on it, and a bare bar gives them nowhere to go.
class AppUsageList extends StatelessWidget {
  const AppUsageList({
    super.key,
    required this.apps,
    required this.icons,
    required this.isAttributed,
    required this.valueLabel,
    required this.valueOf,
    required this.captionOf,
    this.maxEntries = 12,
  });

  final List<AppConsumption> apps;
  final Map<String, Uint8List> icons;
  final bool isAttributed;

  /// The figure shown on the right of each row.
  final String Function(AppConsumption) valueLabel;

  /// The quantity the bar length is proportional to.
  final double Function(AppConsumption) valueOf;

  final String Function(AppConsumption) captionOf;

  final int maxEntries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (apps.isEmpty) return const SizedBox.shrink();

    final shown = apps.take(maxEntries).toList();
    final peak = shown
        .map(valueOf)
        .fold<double>(0, (a, b) => a > b ? a : b)
        .clamp(0.0001, double.infinity);

    return Column(
      children: [
        for (var i = 0; i < shown.length; i++)
          InkWell(
            onTap: () => AppDetailSheet.show(
              context,
              app: shown[i],
              icon: icons[shown[i].packageName],
              isAttributed: isAttributed,
            ),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: icons[shown[i].packageName] != null
                        ? Image.memory(
                            icons[shown[i].packageName]!,
                            fit: BoxFit.contain,
                          )
                        : Icon(
                            Icons.android_rounded,
                            size: 18,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                shown[i].label,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              valueLabel(shown[i]),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(
                              begin: 0,
                              end: valueOf(shown[i]) / peak,
                            ),
                            duration: Duration(milliseconds: 380 + i * 35),
                            curve: Curves.easeOutCubic,
                            builder: (context, value, _) =>
                                LinearProgressIndicator(
                              value: value,
                              minHeight: 6,
                              backgroundColor:
                                  theme.colorScheme.outlineVariant,
                              valueColor: AlwaysStoppedAnimation(
                                AppColors
                                    .series[i % AppColors.series.length],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          captionOf(shown[i]),
                          style: theme.textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
