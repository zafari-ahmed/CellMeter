import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

/// The dashboard's hero readout: an arc showing charge level, with the live
/// figures inside it.
///
/// An arc rather than a filled battery outline because the same control has to
/// carry a second quantity — the user's charge limit — and a tick on an arc
/// reads as a target in a way that a mark on a battery icon does not.
class BatteryGauge extends StatelessWidget {
  const BatteryGauge({
    super.key,
    required this.levelPct,
    required this.isCharging,
    this.chargeLimitPct,
    this.primaryLabel,
    this.secondaryLabel,
    this.size = 220,
  });

  final double? levelPct;
  final bool isCharging;

  /// Drawn as a tick on the arc. Showing the limit where the level is read
  /// turns an abstract setting into something the user can see approaching.
  final int? chargeLimitPct;

  final String? primaryLabel;
  final String? secondaryLabel;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final level = levelPct;
    final color = isCharging
        ? AppColors.primary
        : (level == null ? theme.colorScheme.onSurfaceVariant
            : AppColors.forLevel(level));

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Animated so a level change reads as movement rather than a jump,
          // which matters when the number updates every couple of seconds.
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: (level ?? 0) / 100),
            duration: const Duration(milliseconds: 650),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => CustomPaint(
              size: Size.square(size),
              painter: _GaugePainter(
                progress: value,
                color: color,
                trackColor: theme.colorScheme.outlineVariant,
                limit: chargeLimitPct == null ? null : chargeLimitPct! / 100,
                limitColor: AppColors.accent,
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isCharging)
                const Padding(
                  padding: EdgeInsets.only(bottom: 2),
                  child: Icon(
                    Icons.bolt_rounded,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    level == null ? '--' : level.round().toString(),
                    style: AppTheme.numeric(
                      context,
                      size: size * 0.26,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    '%',
                    style: AppTheme.numeric(
                      context,
                      size: size * 0.11,
                      weight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              if (primaryLabel != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    primaryLabel!,
                    style: theme.textTheme.titleSmall?.copyWith(color: color),
                  ),
                ),
              if (secondaryLabel != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    secondaryLabel!,
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    required this.limit,
    required this.limitColor,
  });

  final double progress;
  final Color color;
  final Color trackColor;
  final double? limit;
  final Color limitColor;

  /// The arc leaves a gap at the bottom so the two ends are distinguishable
  /// and the shape does not read as a plain ring.
  static const double _startAngle = math.pi * 0.75;
  static const double _sweepAngle = math.pi * 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.075;
    final rect = Rect.fromLTWH(0, 0, size.width, size.height)
        .deflate(stroke / 2 + 2);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = trackColor;

    canvas.drawArc(rect, _startAngle, _sweepAngle, false, track);

    if (progress > 0) {
      final fill = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: _startAngle,
          endAngle: _startAngle + _sweepAngle,
          colors: [color.withValues(alpha: 0.55), color],
          transform: const GradientRotation(_startAngle),
        ).createShader(rect);

      canvas.drawArc(
        rect,
        _startAngle,
        _sweepAngle * progress.clamp(0.0, 1.0),
        false,
        fill,
      );
    }

    final limitValue = limit;
    if (limitValue != null && limitValue > 0 && limitValue < 1) {
      final angle = _startAngle + _sweepAngle * limitValue;
      final centre = rect.center;
      final radius = rect.width / 2;
      final inner = Offset(
        centre.dx + math.cos(angle) * (radius - stroke * 0.62),
        centre.dy + math.sin(angle) * (radius - stroke * 0.62),
      );
      final outer = Offset(
        centre.dx + math.cos(angle) * (radius + stroke * 0.62),
        centre.dy + math.sin(angle) * (radius + stroke * 0.62),
      );

      canvas.drawLine(
        inner,
        outer,
        Paint()
          ..color = limitColor
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.trackColor != trackColor ||
      old.limit != limit;
}

/// A horizontal bar showing health as a share of design capacity.
class HealthBar extends StatelessWidget {
  const HealthBar({
    super.key,
    required this.healthPct,
    this.height = 12,
  });

  final double? healthPct;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final health = healthPct;
    final color = health == null
        ? theme.colorScheme.onSurfaceVariant
        : AppColors.forScore(health);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(height),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: (health ?? 0) / 100),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => LinearProgressIndicator(
              value: value.clamp(0.0, 1.0),
              minHeight: height,
              backgroundColor: theme.colorScheme.outlineVariant,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Worn', style: theme.textTheme.labelSmall),
            Text('As new', style: theme.textTheme.labelSmall),
          ],
        ),
      ],
    );
  }
}
