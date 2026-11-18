import 'package:flutter/material.dart';

/// CellMeter's brand palette.
///
/// The identity is a technical instrument: a dark navy chassis, an electric
/// green readout, and yellow reserved for "look at this". Colour is load
/// bearing here — a battery app is read at a glance, so green/amber/red have to
/// mean the same thing on every screen.
abstract final class AppColors {
  // ------------------------------------------------------------ brand core

  /// Electric Green. Primary brand colour, healthy readings, charging.
  static const Color primary = Color(0xFF39E75F);
  static const Color primaryDim = Color(0xFF26A944);
  static const Color primaryBright = Color(0xFF6BFF8A);

  /// Deep Navy. The surface everything else sits on.
  static const Color navy = Color(0xFF101B2D);
  static const Color navyLight = Color(0xFF18263E);
  static const Color navyLighter = Color(0xFF223250);
  static const Color navyDeep = Color(0xFF0A1220);

  /// Yellow. Warnings, "needs attention", the second series in a chart.
  static const Color accent = Color(0xFFFFC928);
  static const Color accentDim = Color(0xFFD4A313);

  // -------------------------------------------------------- semantic scale

  /// The health/severity ramp. Used for health rings, drain badges and
  /// temperature readouts so one colour always means one thing.
  static const Color excellent = Color(0xFF39E75F);
  static const Color good = Color(0xFF9CE640);
  static const Color fair = Color(0xFFFFC928);
  static const Color poor = Color(0xFFFF8A3D);
  static const Color critical = Color(0xFFFF4D4D);

  static const Color info = Color(0xFF3DAEFF);
  static const Color cool = Color(0xFF3DD6D0);

  // ----------------------------------------------------------- chart series

  /// Categorical series for the per-app breakdown and multi-line charts.
  /// Ordered so adjacent entries stay distinguishable, including for the most
  /// common forms of colour blindness.
  static const List<Color> series = <Color>[
    Color(0xFF39E75F),
    Color(0xFF3DAEFF),
    Color(0xFFFFC928),
    Color(0xFFB07BFF),
    Color(0xFF3DD6D0),
    Color(0xFFFF8A3D),
    Color(0xFFFF6FB5),
    Color(0xFF9CE640),
  ];

  // ------------------------------------------------------------ light theme

  static const Color lightSurface = Color(0xFFF6F8FB);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0xFFE2E8F0);
  static const Color lightText = Color(0xFF0E1726);
  static const Color lightTextMuted = Color(0xFF64748B);

  // ------------------------------------------------------------- dark theme

  static const Color darkSurface = navy;
  static const Color darkCard = navyLight;
  static const Color darkBorder = Color(0xFF2A3B5C);
  static const Color darkText = Color(0xFFEDF2F9);
  static const Color darkTextMuted = Color(0xFF94A7C4);

  /// True black for AMOLED panels, where an unlit pixel costs nothing.
  static const Color amoledSurface = Color(0xFF000000);
  static const Color amoledCard = Color(0xFF0C1420);

  /// Maps a 0..100 score onto the severity ramp. Higher is better.
  static Color forScore(double score) {
    if (score >= 85) return excellent;
    if (score >= 70) return good;
    if (score >= 55) return fair;
    if (score >= 40) return poor;
    return critical;
  }

  /// Maps a battery level onto the ramp, which inverts near empty.
  static Color forLevel(double levelPct) {
    if (levelPct >= 60) return excellent;
    if (levelPct >= 35) return good;
    if (levelPct >= 20) return fair;
    if (levelPct >= 10) return poor;
    return critical;
  }

  /// Lithium cells are happy from roughly 15 °C to 35 °C and degrade quickly
  /// above 40 °C, so the ramp is tuned to those boundaries rather than to a
  /// linear scale.
  static Color forTemperature(double celsius) {
    if (celsius < 0) return info;
    if (celsius <= 35) return excellent;
    if (celsius <= 40) return fair;
    if (celsius <= 45) return poor;
    return critical;
  }
}
