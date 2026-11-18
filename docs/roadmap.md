# CellMeter — state of the app, and what to build next

Audit date: 18 November 2026. Analyzer clean, 39 tests passing, 10,359 lines of
Dart and 3,245 of Kotlin.

---

## Verified working on hardware

Tested on a Pixel 7 Pro, Android 17 (API 37).

| Area | Evidence |
|---|---|
| Sampler | Runs as a special-use foreground service (`isForeground=true`), survives app swipe-away |
| Boot restart | `CellMeter/Boot: Restarting sampler after BOOT_COMPLETED` seen in logcat |
| Battery reads | Charge counter 2,846 mAh and current sensor +803 mA, both real on this device |
| Design capacity | 5,000 mAh resolved via `PowerProfile` reflection — note `adb shell` *can* read sysfs here but the app cannot, so this fallback is load-bearing |
| Spool ingest | 334 samples ingested, sessions derived |
| Session segmentation | 4 sessions correctly split charge/discharge with rejection reasons |
| Charge alarm | Fired at the 80% limit with the right wording |
| Live notification | `162 mA · 30.4 °C · 4.27 V · 0.69 W` |
| Per-app usage | Real breakdown with mAh figures |
| Widgets | 2×1, 2×2 and the full panel all render; sparkline draws the live trace |
| Charts | Axis labels, live charging curve, 24-hour level chart |
| Settings | Accordions, all alert controls |
| Light theme | Rendered correctly (seen via an accidental tap) |

## Never verified

- **Capacity measurement has never produced a number.** It needs one charge
  covering 20%+ in a single go; the test phone sat between 65% and 88%
  throughout. This is the core of the app and the single most important thing
  left to confirm. Run the battery to ~50%, charge to 80%, and check the Health
  screen and health widget populate.
- **Overnight Doze survival.** The sampler has never run unattended for hours.
  A gap in the record after a night asleep is the failure mode that would make
  capacity measurement unreliable in the field.
- **Any device that is not a Pixel.** Battery property support varies more by
  manufacturer than by anything else.
- **The launcher icon on a home screen** (added, built, not yet installed).

---

## Known gaps in what exists

### Data collected on every sample but never shown

These are already in the database. Surfacing them is UI work only — no new
permissions, no new plumbing, no new risk.

| Field | What it would give the user |
|---|---|
| `uptimeMs` vs `elapsedRealtimeMs` | Deep sleep percentage — *the* diagnostic for "why did my battery drain overnight" |
| `cycleCount` | The OEM's own charge-cycle count. The test Pixel reports **639**. A headline number for a battery app, currently thrown away |
| `maxCurrentMa` | Peak charging current per session. Averages alone understate a charger that starts fast and tapers |
| `manufacturingDate`, `firstUsageDate` | Battery age on Android 15+ — "your cell is 2.3 years old" is the context that makes a health figure mean something |
| `energyCounterNwh`, `currentAvgUa` | Secondary, but free |
| Temperature series | Sampled continuously, never charted. Heat is the main driver of wear |

### Dead or unwired code

- **`app_usage_slices` is never written to** — only ever deleted. Per-app
  attribution is recomputed live from `UsageStatsManager` on every view, which
  means app history cannot reach further back than Android's own usage-stats
  retention. Persisting slices would unlock "this week" and "this month".
- **`watchSessions()`** is declared and never called.
- **`RetentionPolicy.pro`** exists; nothing is gated.
- **`setDesignCapacityOverride`** survives on the channel but has no UI since
  the "This battery" section was removed. A device that reports no design
  capacity can therefore never show a health percentage.
- **`AppThemeMode.light/dark/amoled`** are unreachable now that Appearance is
  gone. The app follows the system.
- **`lib/features/discharge/`** is an empty directory.

### Test coverage

39 tests, all on `domain/analytics` — which is the right place to concentrate,
since that is where the correctness risk lives. But there are **no tests at all**
for the repository, the widgets, or any Kotlin. The circular-dependency bug that
broke the Health screen would have been caught by one repository test.

### Release readiness

- Release builds are still **signed with the debug key**.
- `isMinifyEnabled = false` — no shrinking or obfuscation.
- No privacy policy URL (Play requires one even with no data collection).

---

## What to build next

Ordered by value per unit of effort.

### 1. Deep sleep and wakelock diagnostics — *highest value, data already there*

`uptimeMs` and `elapsedRealtimeMs` are sampled on every reading and their
difference is deep sleep. A phone that never sleeps is the most common cause of
bad standby drain, and almost nothing on the market shows it clearly.

Surface: deep sleep percentage per discharge session, a warning when a
screen-off stretch stays awake, and the figure on the Discharge view.

The empty `lib/features/discharge/` folder is where this belongs — the app
currently has no dedicated discharge screen, and standby drain is the question
it should answer.

### 2. Battery age and cycle count

One row each, both already collected. "639 cycles · 2.3 years old · 87% health"
is a far more complete answer than a health percentage alone, and it is the
shape of answer people come to this category for.

### 3. Charge alarm that actually wakes you

The alarm is currently a high-priority notification. People charge overnight,
and a notification does not interrupt sleep. Needs a sound, a repeat, and
optionally a full-screen intent. This is the single most-cited reason people
install apps in this category.

Requires `USE_FULL_SCREEN_INTENT` and a Play justification.

### 4. Data export — CSV and JSON

Cheap to build, and it makes the app credible to the technical users who form
its early audience. Also the only sane path before "Reset measurement data",
and a prerequisite for device migration.

### 5. Battery health trend and projection

The capacity estimate history is already logged on every recompute. A proper
degradation chart with a projection — "on this trend you reach 80% health in
about 14 months" — is the reason someone keeps the app installed for years
rather than checking once and uninstalling.

### 6. Persist per-app history

Write `app_usage_slices` instead of recomputing. Unlocks weekly and monthly
app breakdowns, which is what people actually want to compare, and removes the
dependency on Android's short usage-stats retention.

### 7. Name your chargers

Sessions are grouped by plug type, which cannot tell two AC chargers apart.
Letting the user name a charge session — "desk", "car", "bedside" — turns the
charger comparison from a curiosity into something actionable.

### 8. Screen-on time per day

Already derivable from the samples. Heavily requested in this category, and it
pairs naturally with the per-app breakdown.

### 9. Quick Settings tile

A one-tap readout of level, current and temperature without opening the app.
Small, and it puts the app somewhere people look often.

### 10. Pro tier

The retention policy is already written for it. A reasonable split, matching
the market: history beyond 24 hours, export, widgets beyond the compact size,
and no ads.

---

## Deliberately not built

- **Per-app background attribution.** Nothing available to a normal app can
  tell whose wakelock drained the battery. It stays in the visible
  "standby and background" remainder rather than being invented.
- **Per-app drain rate.** Attribution is proportional to foreground time, so
  the rate reduces to the same value for every app. It was built, shipped an
  identical figure on every row, and was removed.
- **iOS.** It exposes a rounded level and a charging flag and nothing else —
  no current, no coulomb counter, no per-app data. The project builds there and
  degrades to a basic readout.
