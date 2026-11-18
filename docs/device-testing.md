# Running CellMeter on a physical device

Nothing in this app has been run on real hardware yet. This is the order to do
it in, and the things most likely to be wrong.

---

## 1. Prepare the phone

**Enable Developer options**
Settings → About phone → tap **Build number** seven times. On Xiaomi/Redmi it is
MIUI version; on Samsung it is Build number under Software information.

**Enable USB debugging**
Settings → System → Developer options → **USB debugging** on.

**Also turn on, if present:**
- *Install via USB* (Xiaomi, Oppo, Vivo, Realme — without this `flutter run` fails)
- *USB debugging (Security settings)* (Xiaomi)
- *Disable permission monitoring* (Xiaomi, stops MIUI killing the sampler)

**Plug in, then set the USB mode to File transfer / MTP.** On "Charging only"
many devices never expose ADB.

**Accept the prompt.** A dialog says *Allow USB debugging?* — tick
**Always allow from this computer**, then Allow. If it never appears, revoke and
retry: Developer options → Revoke USB debugging authorisations, then replug.

---

## 2. Confirm the computer sees it

```bash
~/Android/Sdk/platform-tools/adb devices -l
```

Expect one line ending in `device`. Other states:

| Shown | Meaning |
|---|---|
| *(empty)* | Cable, port or USB mode. Try another cable — many are charge-only. |
| `unauthorized` | The prompt was not accepted. Replug and accept it. |
| `offline` | Replug, or `adb kill-server` then run the command again. |

---

## 3. Install and run

Debug build, with hot reload and a live log:

```bash
cd /var/www/html/home/cellMeter && flutter run
```

Or install the release build, which is what a user would actually get:

```bash
cd /var/www/html/home/cellMeter && flutter install --release
```

To watch what the native layer is doing while you use the app:

```bash
~/Android/Sdk/platform-tools/adb logcat -s CellMeter/Service CellMeter/Widget CellMeter/Sink CellMeter/Usage CellMeter/DesignCap
```

---

## 4. First-run checks

Work through onboarding, then confirm:

- [ ] The **ongoing notification** appears and shows live figures
- [ ] **Run without restrictions** prompt opens and can be accepted
- [ ] **Usage access** opens the right system screen
- [ ] The dashboard shows a level, and **current in mA is not a dash**

### If current or charge counter shows "—"

That is the single most important thing to find out, and it is a property of the
device rather than a bug. Settings → Diagnostics names exactly what this phone
reports. Check the raw values directly:

```bash
~/Android/Sdk/platform-tools/adb shell dumpsys battery
```

```bash
~/Android/Sdk/platform-tools/adb shell cat /sys/class/power_supply/battery/uevent
```

If `CHARGE_COUNTER` is absent, capacity falls back to integrating current, which
is expected and handled. If `CURRENT_NOW` is also absent, this device cannot
support capacity measurement at all and the app should say so rather than show
nothing — worth checking that it does.

---

## 5. Sampler reliability

This is what the app lives or dies on.

- [ ] Plug in and charge for a few minutes, then open History — a charge session
      should appear with a sensible mA figure
- [ ] Lock the phone for 30+ minutes, come back, pull to refresh. Readings should
      be continuous, **not** a gap
- [ ] Swipe the app away from recents. The notification must survive
- [ ] Reboot. The notification should return without opening the app

A gap after screen-off is the failure mode to hunt: it means Doze suspended the
sampler and capacity measurement will keep rejecting sessions.

---

## 6. Capacity measurement

The slow one. Let the battery fall to 50% or below, then charge in one go to 80%+.

- [ ] Health screen moves off "Still measuring"
- [ ] Measured capacity is plausible for this phone (within ~15% of its rating)
- [ ] Charges that did **not** count show a reason that makes sense

If health reads exactly 100% with a suspiciously round capacity, the device is
probably reporting a derived charge counter. The rejection message should say so
— if it does not, the detector needs its tolerance revisited.

---

## 7. Widgets

Never verified visually. Most likely place for something to look wrong.

- [ ] Settings → Home screen → **Battery widget** opens the system add dialog
- [ ] It lands on the home screen already showing data, not placeholders
- [ ] Resize 2×1 → 4×1 → 4×2; each size redraws with the right layout
- [ ] At 2×1, nothing is clipped — check with a four-digit current like `+1,840 mA`
- [ ] The gauge arc is centred and not pixelated
- [ ] With a charge alarm set, the yellow tick sits at the right angle
- [ ] The "updated ago" chronometer ticks and resets on each push
- [ ] Colours stay CellMeter navy/green regardless of wallpaper or app theme
- [ ] **Health widget** shows "Still measuring" before any measurement, not a
      zeroed ring
- [ ] Tapping either widget opens the app

If a widget stays blank, check logcat for `CellMeter/Widget`. A bitmap too large
for a Binder transaction fails silently.

---

## 8. Alerts

- [ ] Set the charge alarm low (just above the current level), plug in, confirm it fires
- [ ] It does **not** fire twice in one charge session
- [ ] It re-arms after unplugging
- [ ] Temperature alert fires under load (a game or video call will do it)

---

## Known OEM obstacles

| Manufacturer | What to expect |
|---|---|
| Xiaomi / Redmi / POCO | Aggressive killing. Set Autostart on and Battery saver to No restrictions, or sessions will have gaps. |
| Samsung | Add CellMeter to "Never sleeping apps" under Battery → Background usage limits. |
| Huawei / Honor | Set App launch to Manage manually with all three toggles on. |
| OnePlus / Oppo / Realme | Disable "Deep optimisation" and "Sleep standby optimisation". |

These are the real reason battery apps get one-star reviews about stopping
overnight, so they are worth reproducing deliberately rather than discovering
later.
