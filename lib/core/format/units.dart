import 'package:intl/intl.dart';

/// Formatting for every physical quantity CellMeter shows.
///
/// Centralised for two reasons. A battery app lives or dies on whether its
/// numbers look trustworthy, which means consistent precision and never
/// printing more digits than the sensor justifies. And almost every value is
/// optional, so each formatter has to have one agreed way of saying "this
/// device does not report that".
abstract final class Units {
  /// What any screen prints where a sensor gave nothing.
  static const String unavailable = '—';

  static final NumberFormat _int = NumberFormat.decimalPattern();
  static final NumberFormat _one = NumberFormat('#,##0.0');
  static final NumberFormat _two = NumberFormat('#,##0.00');

  // --------------------------------------------------------------- current

  /// Microamps to a milliamp reading. The fuel gauge resolves to roughly a
  /// milliamp at best, so decimals here would be invented precision.
  static String currentMa(num? microAmps, {bool signed = false}) {
    if (microAmps == null) return unavailable;
    final ma = microAmps / 1000;
    final value = signed ? ma : ma.abs();
    return '${_int.format(value.round())} mA';
  }

  /// Signed milliamps with an explicit + so charge and discharge read apart
  /// at a glance.
  static String currentMaSigned(num? microAmps) {
    if (microAmps == null) return unavailable;
    final ma = (microAmps / 1000).round();
    final sign = ma > 0 ? '+' : '';
    return '$sign${_int.format(ma)} mA';
  }

  // ----------------------------------------------------------------- power

  static String watts(num? milliWatts) {
    if (milliWatts == null) return unavailable;
    final w = milliWatts.abs() / 1000;
    return '${_two.format(w)} W';
  }

  // -------------------------------------------------------------- capacity

  /// Microamp-hours to mAh.
  static String capacityMah(num? microAmpHours) {
    if (microAmpHours == null) return unavailable;
    return '${_int.format((microAmpHours / 1000).round())} mAh';
  }

  /// A value already expressed in mAh.
  static String mah(num? milliAmpHours, {int decimals = 0}) {
    if (milliAmpHours == null) return unavailable;
    final text = decimals == 0
        ? _int.format(milliAmpHours.round())
        : _one.format(milliAmpHours);
    return '$text mAh';
  }

  // --------------------------------------------------------------- voltage

  static String volts(num? milliVolts) {
    if (milliVolts == null) return unavailable;
    return '${_two.format(milliVolts / 1000)} V';
  }

  static String millivolts(num? milliVolts) {
    if (milliVolts == null) return unavailable;
    return '${_int.format(milliVolts.round())} mV';
  }

  // ----------------------------------------------------------- temperature

  static String celsius(num? value) {
    if (value == null) return unavailable;
    return '${_one.format(value)} °C';
  }

  static String fahrenheit(num? celsiusValue) {
    if (celsiusValue == null) return unavailable;
    return '${_one.format(celsiusValue * 9 / 5 + 32)} °F';
  }

  static String temperature(num? celsiusValue, {bool useFahrenheit = false}) =>
      useFahrenheit ? fahrenheit(celsiusValue) : celsius(celsiusValue);

  // ------------------------------------------------------------ percentage

  static String percent(num? value, {int decimals = 0}) {
    if (value == null) return unavailable;
    final text =
        decimals == 0 ? value.round().toString() : _one.format(value);
    return '$text%';
  }

  /// A rate of change, as shown on the drain cards.
  static String percentPerHour(num? value) {
    if (value == null) return unavailable;
    return '${_one.format(value.abs())}%/h';
  }

  // -------------------------------------------------------------- duration

  /// Compact duration for dense rows: `4h 12m`, `12m`, `45s`.
  static String duration(Duration? d) {
    if (d == null) return unavailable;
    final total = d.abs();
    final hours = total.inHours;
    final minutes = total.inMinutes.remainder(60);
    final seconds = total.inSeconds.remainder(60);

    if (hours > 0) return '${hours}h ${minutes}m';
    if (minutes > 0) return '${minutes}m';
    return '${seconds}s';
  }

  /// Long form for the one or two places that have room: `4 hours 12 min`.
  static String durationLong(Duration? d) {
    if (d == null) return unavailable;
    final total = d.abs();
    final hours = total.inHours;
    final minutes = total.inMinutes.remainder(60);

    if (hours > 0 && minutes > 0) {
      return '$hours ${_plural(hours, 'hour')} $minutes min';
    }
    if (hours > 0) return '$hours ${_plural(hours, 'hour')}';
    if (minutes > 0) return '$minutes min';
    return '${total.inSeconds} sec';
  }

  /// Time remaining, where we would rather be vague than precise and wrong.
  static String remaining(Duration? d) {
    if (d == null) return unavailable;
    if (d.inMinutes < 1) return 'under a minute';
    if (d.inDays >= 2) return '${d.inDays} days';
    return duration(d);
  }

  // ------------------------------------------------------------------ time

  static final DateFormat _clock = DateFormat('HH:mm');
  static final DateFormat _clockSec = DateFormat('HH:mm:ss');
  static final DateFormat _dayMonth = DateFormat('d MMM');
  static final DateFormat _dayMonthTime = DateFormat('d MMM, HH:mm');
  static final DateFormat _weekday = DateFormat('EEE');

  static String clock(DateTime? t) => t == null ? unavailable : _clock.format(t);

  static String clockWithSeconds(DateTime? t) =>
      t == null ? unavailable : _clockSec.format(t);

  static String dayMonth(DateTime? t) =>
      t == null ? unavailable : _dayMonth.format(t);

  static String weekday(DateTime? t) =>
      t == null ? unavailable : _weekday.format(t);

  /// Dates in lists, where "today" and "yesterday" carry more than a date does.
  static String friendlyDateTime(DateTime? t) {
    if (t == null) return unavailable;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(t.year, t.month, t.day);
    final diff = today.difference(that).inDays;

    if (diff == 0) return 'Today, ${_clock.format(t)}';
    if (diff == 1) return 'Yesterday, ${_clock.format(t)}';
    if (diff < 7) return '${_weekday.format(t)}, ${_clock.format(t)}';
    return _dayMonthTime.format(t);
  }

  static String relative(DateTime? t) {
    if (t == null) return unavailable;
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 45) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'yesterday';
    if (diff.inDays < 30) return '${diff.inDays} days ago';
    return _dayMonth.format(t);
  }

  // ------------------------------------------------------------------ misc

  static String bytes(int? count) {
    if (count == null) return unavailable;
    if (count < 1024) return '$count B';
    if (count < 1024 * 1024) return '${_one.format(count / 1024)} KB';
    return '${_one.format(count / (1024 * 1024))} MB';
  }

  static String count(num? value) =>
      value == null ? unavailable : _int.format(value);

  static String cycles(num? value) {
    if (value == null) return unavailable;
    return '${_one.format(value)} ${_plural(value, 'cycle')}';
  }

  static String _plural(num value, String word) =>
      value == 1 ? word : '${word}s';
}
