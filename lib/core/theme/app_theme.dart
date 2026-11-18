import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';

/// Which surface palette the app is painted on.
enum AppThemeMode {
  /// Follow the system setting, using [AppThemeMode.dark] when it is dark.
  system,
  light,
  dark,

  /// True-black variant for AMOLED panels. Unlit pixels draw no power, which
  /// is a measurable saving on exactly the device this app is installed to
  /// study.
  amoled;

  String get label => switch (this) {
        AppThemeMode.system => 'Follow system',
        AppThemeMode.light => 'Light',
        AppThemeMode.dark => 'Dark',
        AppThemeMode.amoled => 'AMOLED black',
      };
}

/// Theme construction for CellMeter.
///
/// The type ramp leans on tabular figures: almost every number on screen
/// updates once a second, and proportional digits make a readout jitter as the
/// glyph widths change. [numeric] is used wherever a value ticks.
abstract final class AppTheme {
  static ThemeData light() => _build(
        brightness: Brightness.light,
        surface: AppColors.lightSurface,
        card: AppColors.lightCard,
        border: AppColors.lightBorder,
        text: AppColors.lightText,
        textMuted: AppColors.lightTextMuted,
      );

  static ThemeData dark() => _build(
        brightness: Brightness.dark,
        surface: AppColors.darkSurface,
        card: AppColors.darkCard,
        border: AppColors.darkBorder,
        text: AppColors.darkText,
        textMuted: AppColors.darkTextMuted,
      );

  static ThemeData amoled() => _build(
        brightness: Brightness.dark,
        surface: AppColors.amoledSurface,
        card: AppColors.amoledCard,
        border: const Color(0xFF1E2838),
        text: AppColors.darkText,
        textMuted: AppColors.darkTextMuted,
      );

  static ThemeData of(AppThemeMode mode, Brightness platformBrightness) =>
      switch (mode) {
        AppThemeMode.light => light(),
        AppThemeMode.dark => dark(),
        AppThemeMode.amoled => amoled(),
        AppThemeMode.system =>
          platformBrightness == Brightness.dark ? dark() : light(),
      };

  static ThemeData _build({
    required Brightness brightness,
    required Color surface,
    required Color card,
    required Color border,
    required Color text,
    required Color textMuted,
  }) {
    final isDark = brightness == Brightness.dark;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: AppColors.primary,
      onPrimary: AppColors.navyDeep,
      primaryContainer: isDark ? AppColors.primaryDim : AppColors.primaryBright,
      onPrimaryContainer: isDark ? AppColors.darkText : AppColors.navyDeep,
      secondary: AppColors.accent,
      onSecondary: AppColors.navyDeep,
      secondaryContainer: isDark ? AppColors.accentDim : const Color(0xFFFFF0C2),
      onSecondaryContainer: isDark ? AppColors.darkText : AppColors.navyDeep,
      tertiary: AppColors.info,
      onTertiary: Colors.white,
      error: AppColors.critical,
      onError: Colors.white,
      errorContainer: isDark ? const Color(0xFF5C1F1F) : const Color(0xFFFFE0E0),
      onErrorContainer: isDark ? AppColors.darkText : const Color(0xFF7A1010),
      surface: surface,
      onSurface: text,
      surfaceContainerLowest: isDark ? AppColors.navyDeep : Colors.white,
      surfaceContainerLow: card,
      surfaceContainer: card,
      surfaceContainerHigh: isDark ? AppColors.navyLighter : const Color(0xFFEFF3F8),
      surfaceContainerHighest: isDark ? AppColors.navyLighter : const Color(0xFFE8EDF4),
      onSurfaceVariant: textMuted,
      outline: border,
      outlineVariant: border,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: isDark ? AppColors.lightSurface : AppColors.navy,
      onInverseSurface: isDark ? AppColors.lightText : AppColors.darkText,
      inversePrimary: AppColors.primaryDim,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: surface,
      splashFactory: InkSparkle.splashFactory,
    );

    return base.copyWith(
      textTheme: _textTheme(base.textTheme, text, textMuted),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: surface,
              )
            : SystemUiOverlayStyle.dark.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: surface,
              ),
        titleTextStyle: TextStyle(
          color: text,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
      ),
      cardTheme: CardThemeData(
        color: card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: border),
        ),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? AppColors.navyDeep : Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.primary.withValues(alpha: 0.18),
        elevation: 0,
        height: 66,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: selected ? AppColors.primary : textMuted,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppColors.primary : textMuted,
          );
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.navyDeep,
          minimumSize: const Size(0, 50),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          minimumSize: const Size(0, 50),
          side: BorderSide(color: border),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? AppColors.navyDeep
                : (isDark ? AppColors.darkTextMuted : Colors.white)),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? AppColors.primary
                : (isDark ? AppColors.navyLighter : const Color(0xFFCBD5E1))),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.primary,
        inactiveTrackColor: border,
        thumbColor: AppColors.primary,
        overlayColor: AppColors.primary.withValues(alpha: 0.15),
        trackHeight: 5,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: textMuted,
        textColor: text,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? AppColors.navyLighter : const Color(0xFFEFF3F8),
        side: BorderSide(color: border),
        labelStyle: TextStyle(
          color: text,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? AppColors.navyLighter : AppColors.navy,
        contentTextStyle: const TextStyle(color: AppColors.darkText),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? AppColors.navyLighter : AppColors.navy,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(color: AppColors.darkText, fontSize: 12),
      ),
    );
  }

  static TextTheme _textTheme(TextTheme base, Color text, Color muted) {
    return base.copyWith(
      displayLarge: base.displayLarge?.copyWith(
        color: text,
        fontWeight: FontWeight.w800,
        letterSpacing: -2,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      displayMedium: base.displayMedium?.copyWith(
        color: text,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.5,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        color: text,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
      ),
      headlineSmall: base.headlineSmall?.copyWith(
        color: text,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      titleLarge: base.titleLarge?.copyWith(
        color: text,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      titleMedium: base.titleMedium?.copyWith(
        color: text,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      titleSmall: base.titleSmall?.copyWith(
        color: text,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: base.bodyLarge?.copyWith(color: text, height: 1.45),
      bodyMedium: base.bodyMedium?.copyWith(color: text, height: 1.45),
      bodySmall: base.bodySmall?.copyWith(color: muted, height: 1.4),
      labelLarge: base.labelLarge?.copyWith(
        color: text,
        fontWeight: FontWeight.w600,
      ),
      labelMedium: base.labelMedium?.copyWith(
        color: muted,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
      labelSmall: base.labelSmall?.copyWith(
        color: muted,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
      ),
    );
  }

  /// Style for any figure that updates while the user is looking at it.
  /// Tabular figures keep the digits from shifting as the value changes.
  static TextStyle numeric(
    BuildContext context, {
    double size = 32,
    FontWeight weight = FontWeight.w800,
    Color? color,
  }) =>
      TextStyle(
        fontSize: size,
        fontWeight: weight,
        letterSpacing: -1,
        height: 1.05,
        color: color ?? Theme.of(context).colorScheme.onSurface,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}
