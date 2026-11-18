# CellMeter

**Monitor. Analyze. Optimize.**

A battery monitoring and analytics app for Android, built with Flutter. CellMeter
measures what a phone's battery actually holds today — rather than repeating what
the manufacturer claimed when it was new — and explains where the charge goes.

Everything stays on the device. The release build has no `INTERNET` permission.

---

## What it does

| Area | What you get |
|---|---|
| **Health** | Measured capacity in mAh, health as a share of design capacity, wear, cycles used, and the evidence behind the figure |
| **Live readings** | Level, current (mA), power (W), voltage, temperature, charging state and plug type, updated every 2 seconds |
| **Charging** | Live charging current and power, charge-speed class, time to full *and* time to your charge limit, a current curve for the session in progress, and your chargers ranked by the power each actually delivers |
| **Discharge** | Screen-on and screen-off drain rates kept separate, with runtime forecasts for each |
| **History** | 24-hour level chart, per-session records with level span, charge moved, temperature and drain rates |
| **Apps** | Battery attributed across apps by foreground time, with the unattributed remainder shown rather than hidden |
| **Alerts** | Charge limit alarm, high-drain alert, low battery, high temperature — all evaluated natively so they fire with no Dart engine running |
| **Widgets** | A resizable battery widget (2×1 to 4×2) and a 2×2 health widget, in fixed brand colours, driven by the sampler rather than Android's 30-minute refresh floor |

---

## How capacity is measured

A battery's full capacity is the charge that went in divided by the fraction of the
battery it filled. If the coulomb counter says 1 480 mAh went in while the level
moved from 24% to 78%, the battery holds about `1480 / 0.54 ≈ 2741` mAh.

Three things make that harder than it sounds, and most of the code in
[`lib/domain/analytics/`](lib/domain/analytics/) exists to handle them.

**1. Not every charge is measurable.** The level is quantised to whole percent, so a
narrow charge carries a large relative error. CellMeter requires a session to cover
**20% or more** — not a full charge, which is what competing tools demand and why
they can go weeks without producing a number. Sessions are also rejected if the
sampler was suspended mid-way, if the battery ran hot, or if too few readings were
taken. **Every rejection is shown to the user with its reason**, on the Health
screen.

**2. Some devices lie about the charge counter.** A number of OEMs implement
`BATTERY_PROPERTY_CHARGE_COUNTER` as `level% × design_capacity` instead of reading
the fuel gauge. Such a counter is worse than none: dividing it by the level change
returns the design capacity exactly, every time, so a worn battery reports 100%
health forever. CellMeter detects this by checking whether `counter / level` is
*constant* — a real gauge keeps moving between level steps, a derived one does not
— and rejects those sessions outright. See `_counterLooksSynthetic` in
[`session_segmenter.dart`](lib/domain/analytics/session_segmenter.dart).

**3. Single sessions are noisy in ways that do not average out.** Fuel gauges
re-calibrate, usually at the extremes, producing wild one-off outliers.
Temperature shifts real capacity by several percent. So the estimator uses a
**weighted median**, not a mean: a median ignores a re-calibration outlier entirely,
where a mean would carry it for weeks. Sessions are weighted by level span (wider
charges carry more information), decayed by a 45-day half-life (so genuine
degradation is tracked), and discounted when measured by integrating current rather
than from the coulomb counter. Outliers beyond 3 median-absolute-deviations are
dropped first.

Confidence is reported alongside, and depends on three things rather than a session
count alone: how many sessions, how much of the battery they covered in total, and
how closely they agree. Saying *"still measuring"* is treated as more useful than a
precise-looking number that moves next week.

### When there is no coulomb counter

Devices that expose only `CURRENT_NOW` fall back to trapezoidal integration of
current over time. Intervals longer than 10 minutes are skipped rather than
interpolated across — assuming the current held steady through a gap nobody observed
is exactly the invented data this app exists to avoid — and the result is discarded
unless it covers 80% of the session.

---

## Per-app battery attribution

Android provides no API that reports an app's energy use. What the system's own
battery screen shows is *modelled*: estimated component usage multiplied by a table
of nominal costs the manufacturer supplies in `power_profile.xml`, which on real
hardware is frequently inaccurate.

CellMeter does not reproduce that model. It measures the one thing it can measure
exactly — the charge the battery actually lost — and divides it across apps by
foreground time over the same window. The claim is therefore *"the stretch of your
day when this app was on screen cost you 340 mAh"*, which the data supports, rather
than a fabricated per-app wattage.

Background work is deliberately **not** attributed: nothing available to a normal
app can tell whose wakelock drained the battery. It stays in the visible
"standby and background" remainder. The Apps screen says all of this on screen.

---

## Why a native foreground service

A capacity measurement is a difference between two coulomb-counter readings taken
tens of minutes apart. A gap in the middle invalidates the whole session.

Background execution limits would otherwise drop samples exactly when they matter —
during a long screen-off charge — which is the single most common complaint about
apps in this category. So sampling runs in a native Kotlin foreground service
([`MonitorService.kt`](android/app/src/main/kotlin/com/cellmeter/app/monitor/MonitorService.kt)),
restarted on boot, with `START_STICKY`, and the app surfaces the battery-optimisation
exemption prompt on the dashboard rather than burying it in settings.

Sampling cadence adapts: 10s while charging, 30s with the screen on, 120s in
standby, plus an immediate sample on every `ACTION_BATTERY_CHANGED` and screen
transition. Redundant samples are skipped, with a 10-minute heartbeat so a gap in
the record unambiguously means *"the sampler was dead"* rather than *"nothing
happened"*.

### Sample hand-off

The service never touches the Flutter database. It appends newline-delimited JSON to
a spool file; Dart reads whole lines, commits them to drift, and only then tells the
native side to drop them. An append-only file makes the hot path trivially correct —
no cross-process locking, no schema duplicated across two languages — and a process
kill mid-write costs at most the final partial line, which the reader skips.

---

## Home screen widgets

Two entries in the widget picker: a resizable **battery** widget (2×1 compact,
4×1 row, 4×2 full panel — one provider picking its layout from the cell size the
launcher gave it) and a fixed 2×2 **health** widget.

**Nothing is ever placed automatically.** Android does not permit an app to put a
widget on the home screen by itself, which is a platform guarantee rather than a
limitation here. The user adds one from the launcher's widget picker, or through
the "Add to home screen" buttons in Settings, which call
`requestPinAppWidget()` — that opens the *system's* own confirmation dialog with
a preview. On launchers that do not implement pinning, the app falls back to
showing how to add it from the picker.

**Colours are fixed.** The widgets deliberately do not follow the app's
light/dark/AMOLED setting and do not opt into Material You wallpaper tinting.
Colour is load bearing — green is healthy or charging, yellow is the user's
charge limit, the severity ramp drives temperature — and a widget recoloured to
someone's wallpaper would stay legible while ceasing to mean anything.

**The 4×2 panel carries a sparkline** of the last six hours, with charging
stretches drawn green and discharging blue, so the rhythm of a day — a long
slow fall, a sharp climb — is readable without a legend or an axis. This is the
one thing a CellMeter widget can show that a stock battery widget cannot, and
it only exists because the sampler is already running. The scale is fixed at
0–100% rather than fitted to the data: a sparkline that rescaled would make a
2% dip look identical to a 60% drain. The points come from a small native ring
buffer (`WidgetHistory`), fed by the sampler whether or not a widget is placed,
so the trace is already there the moment one is added.

Every size also carries a battery silhouette that fills, which is what makes
the widget legible as a battery at a glance on a home screen full of other
cards, with a notch marking the charge limit.

**They stay live.** Android's `updatePeriodMillis` has a 30-minute floor, which
is useless for a battery readout. Because CellMeter already runs a sampler,
widgets are pushed from it whenever a reading changes meaningfully — roughly
10–60 seconds depending on charging state, at no extra battery cost. An app
without a running service cannot do this. The declared 30-minute period remains
only as a safety net for when the service has been killed and not yet restarted.

The widget's fourth column counts down to the user's **charge limit**, not to
100%, whenever one is set — a widget sitting next to a setting that says "stop at
80%" should not answer a question they deliberately stopped asking.

Health and the runtime forecast are the output of the Dart analytics, which the
widget cannot run. Flutter mirrors those few figures into
`WidgetDataStore` whenever it recomputes them, so the widget can render with no
Dart engine alive.

---

## Architecture

```
lib/
├── core/
│   ├── format/units.dart          Every physical quantity, formatted in one place
│   ├── state/providers.dart       Riverpod graph
│   └── theme/                     Brand palette and ThemeData
├── data/
│   ├── db/                        drift schema + retention policy
│   ├── native/                    MethodChannel bridge and its models
│   └── repository/                Ingest → segment → estimate pipeline
├── domain/
│   ├── analytics/
│   │   ├── session_segmenter.dart  Samples → sessions, with quality gating
│   │   ├── capacity_estimator.dart Sessions → capacity, weighted median
│   │   ├── drain_analyzer.dart     Drain rates, runtime, time-to-full
│   │   └── app_attributor.dart     Charge → apps by foreground share
│   └── models/
├── features/                      One folder per screen
└── shared/widgets/                Gauge, charts, metric cards

android/app/src/main/kotlin/com/cellmeter/app/
├── battery/
│   ├── BatteryReader.kt           Every metric, defensively read
│   ├── DesignCapacity.kt          sysfs → PowerProfile reflection → user override
│   ├── SysfsBattery.kt            Best-effort kernel node reads
│   └── AppUsageReader.kt          Foreground time from UsageStatsManager
├── monitor/
│   ├── MonitorService.kt          The sampler
│   ├── SampleSink.kt              Append-only spool
│   ├── AlertEvaluator.kt          Alert rules, debounced by state
│   ├── MonitorSettings.kt         Native mirror of user settings
│   └── Notifications.kt
├── widget/
│   ├── BatteryWidgetProvider.kt   Resizable 2×1–4×2, layout by cell size
│   ├── HealthWidgetProvider.kt    Fixed 2×2
│   ├── WidgetRenderer.kt          RemoteViews for every size
│   ├── GaugeRenderer.kt           Arcs, battery silhouette, sparkline
│   ├── WidgetHistory.kt           Ring buffer behind the sparkline
│   ├── WidgetUpdater.kt           Pushed from the sampler, rate limited
│   ├── WidgetDataStore.kt         Analytics figures mirrored from Dart
│   ├── WidgetPalette.kt           Fixed brand colours
│   └── WidgetPinner.kt            The system add-widget dialog
└── MainActivity.kt                The only bridge
```

The design keeps one immutable fact table (`samples`) and treats everything else as
a cache of analysis over it. That costs disk, and buys the ability to **fix the
analytics in an update and recompute a user's entire history** instead of discarding
it — exposed as "Rebuild analysis from raw readings" in Settings.

---

## Device compatibility

Android guarantees almost none of the battery properties this app uses. Every read
is screened against a plausible range, and `null` means "this device does not report
that" — never zero.

| Metric | Availability |
|---|---|
| Level, voltage, temperature, plug type, health flag | Universal |
| `CURRENT_NOW` | Very common |
| `CHARGE_COUNTER` | Common; sometimes derived from level (detected and rejected) |
| Design capacity | `PowerProfile` reflection works on most devices; sysfs rarely |
| `STATE_OF_HEALTH` | Android 14+, and only some devices |
| Manufacturing / first-use date | Android 15+, rare |
| Cycle count | Android 14+ broadcast extra, or sysfs (usually blocked) |

**Current sign convention** is calibrated at runtime: a significant minority of OEMs
invert it, so `BatteryReader` learns the device's convention from a clear sample and
caches it.

**iOS** is not a target. It exposes a rounded level and a charging flag and nothing
else — no current, no coulomb counter, no per-app data — so an app of this kind
cannot exist there. The project still builds for iOS; `BatteryChannel` degrades to a
basic readout rather than inventing numbers.

---

## Running it

```bash
flutter pub get
```

```bash
dart run build_runner build
```

```bash
flutter run
```

Tests cover the analytics, which is where the correctness risk is:

```bash
flutter test
```

The fixtures in `test/support/fixtures.dart` model the physics rather than drawing
straight lines — charge accumulates from current, and the level is the quantised
consequence. That matters: a fixture that interpolated both linearly would be
indistinguishable from the derived-counter fake the segmenter is meant to catch.

---

## Build configuration

- `minSdk` 24, `targetSdk` 36, `compileSdk` 37
- Application ID `com.cellmeter.app`
- AGP 9.1.0, Gradle 9.3.1, Kotlin 2.3.20, Flutter 3.44 / Dart 3.12

Release builds are currently signed with the debug key. Add a real signing config
before publishing.
