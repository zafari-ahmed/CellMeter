# CellMeter — what is built, and what is next

## Built

**Measurement core**
- Native sampler as a foreground service, restarted on boot, adaptive cadence
- Append-only spool hand-off between Kotlin and Dart
- Session segmentation with quality gating and user-visible rejection reasons
- Capacity estimation by weighted median, with outlier rejection and confidence
- Derived-charge-counter detection
- Current-integration fallback for devices with no coulomb counter
- Drain analysis split by screen state; runtime forecasts; time-to-full with the
  constant-voltage taper allowed for
- Per-app attribution by foreground share, with the remainder shown

**App**
- Dashboard, Health, Charging, History, Apps, Settings, onboarding
- Charge alarm, high-drain, low-battery and temperature alerts, all native
- Light / dark / AMOLED themes
- "I replaced the battery" reset
- Rebuild-analysis-from-raw-readings

**Tests** — 39 covering the analytics, on physically faithful fixtures.

---

## Next, roughly in order of value

### 1. Home screen widgets
The most-requested feature in this category and currently absent. A level-and-rate
widget plus a health widget. `home_widget` plus a native `GlanceAppWidget`.

### 2. Charging alarm sound and escalation
Right now the charge alarm is a high-priority notification. Users who charge
overnight want an actual sound, a repeat, and optionally a full-screen alert.
Needs `USE_FULL_SCREEN_INTENT` and careful Play justification.

### 3. Deep sleep and wakelock diagnostics
`uptimeMillis` vs `elapsedRealtime` is already sampled but not yet surfaced. A phone
that never sleeps is the single most common cause of bad standby drain, and the data
to show it is already being collected.

### 4. Data export
CSV and JSON export of sessions and samples. Cheap to build, and it makes the app
credible to the technical users who form its early audience. Pairs well with import
for device migration.

### 5. Pro tier
Following the market convention, and matching what the data already supports:
- History beyond 24 hours (the retention policy is already written for this)
- AMOLED theme
- Detailed notification figures
- Widgets
- Export
- No ads

`RetentionPolicy.free` / `.pro` already exist; the gate itself is not wired up.

### 6. Battery health over time
The capacity-estimate history is recorded but only charted crudely. A proper
degradation trend, with a projection of when health will cross 80%, is a compelling
reason to keep the app installed for years.

### 7. Charge-speed comparison by charger identity
Currently chargers are grouped by plug type, which cannot tell two AC chargers
apart. Letting the user name a charging session ("desk charger", "car") would make
the comparison genuinely actionable.

### 8. Per-device calibration profiles
Battery property support varies enormously by OEM. Shipping a small table of known
device quirks — which models report a derived counter, which need a sysfs path —
would improve first-run accuracy. Must be bundled, not fetched, to keep the no-network guarantee.

---

## Known limitations

- **iOS** cannot support this app's core features. The project builds, but
  `BatteryChannel` returns nothing there and the UI degrades to a basic readout.
- **Background attribution** is impossible for a normal app. The unattributed
  remainder is shown rather than spread across apps.
- **Design capacity** comes from a hidden API via reflection on most devices. It
  works widely today but is not guaranteed; the user-entered override is the
  fallback.
- **Release signing** still uses the debug key.
