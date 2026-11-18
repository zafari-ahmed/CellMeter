# Google Play listing — CellMeter

## App name
CellMeter – Battery Monitor

## Short description (80 characters max)
> Monitor battery health, charging speed, usage statistics, and battery drain.

78 characters.

## Full description (4000 characters max)

CellMeter gives you detailed insights into your battery's health, charging
performance, power consumption and usage patterns. Understand how your battery
behaves, find what is draining it, and make smarter charging decisions.

🔋 BATTERY HEALTH, MEASURED

CellMeter reads your battery's own charge gauge to work out what it really holds
today — not what the manufacturer claimed when it was new.

• Measured capacity in mAh, and health as a share of the original capacity
• Battery wear and charge cycles consumed
• No full charge required — any charge covering 20% or more counts
• See exactly which charges were used, and why others were not

📊 LIVE BATTERY MONITORING

• Charge level, current in mA, and power in watts
• Battery temperature and voltage
• Charging state, plug type and charging speed
• Optional live figures in the notification shade

⚡ CHARGING ANALYTICS

• Measure the current your charger actually delivers to this phone
• Compare chargers and cables to find the fastest
• Time remaining to full — and to your own charge limit
• Charging current curve for the session in progress
• Full history of every charge session

📉 BATTERY DRAIN

• Screen-on and screen-off drain measured separately
• Runtime estimates for active use and for standby
• Spot unusual consumption as it happens
• Discharge history with rates, temperature and charge used

📱 APP BATTERY USAGE

• Battery attributed across apps by time on screen
• Drain rate while each app is open
• Standby and background consumption shown separately, never hidden

🏠 HOME SCREEN WIDGETS

• Battery widget, resizable from a compact readout to a full panel
• Health widget showing measured capacity at a glance
• Updates in seconds, not every half hour, because CellMeter is already measuring
• Shows how long ago it last updated, so a stale reading is never mistaken for a
  current one

🔔 ALERTS

• Charge alarm — get told to unplug at your chosen limit
• High drain alert, measured over a window so brief spikes don't trigger it
• Low battery and high temperature warnings

🎨 BUILT FOR READING AT A GLANCE

• Light, dark and true-black AMOLED themes
• Clear charts, honest numbers, no clutter

🔒 PRIVATE BY DESIGN

CellMeter has no internet permission at all. Every measurement stays on your
device. No account, no analytics, no data collection.

WHY CELLMETER IS DIFFERENT

Most battery apps repeat figures the system hands them. CellMeter measures, and it
tells you how confident it is. When a charge session cannot be used, it says so and
explains why. When a device reports a charge counter that is really just the battery
percentage in disguise, CellMeter detects it and refuses to pretend it has measured
anything. When battery use cannot be attributed to an app, it stays in a visible
"standby and background" figure rather than being quietly spread around.

Replaced your battery? One tap clears the measurement history so the new cell is
measured from scratch.

CellMeter — Monitor. Analyze. Optimize.

---

## Category
Tools

## Tags
battery, battery health, battery monitor, charging, battery usage, mAh, battery
drain, charge alarm, battery analytics

## Content rating
Everyone / PEGI 3

## Data safety declaration

| Question | Answer |
|---|---|
| Does your app collect or share any user data? | **No** |
| Is all user data encrypted in transit? | N/A — no data leaves the device |
| Do you provide a way to request data deletion? | N/A — no data is collected; in-app reset clears local data |

The release build declares no `INTERNET` permission, which makes this verifiable
rather than a promise.

## Permissions to justify in the listing

| Permission | Why |
|---|---|
| `FOREGROUND_SERVICE_SPECIAL_USE` | Continuous battery sampling. A capacity measurement is a difference between readings taken tens of minutes apart; an interruption invalidates the session. |
| `PACKAGE_USAGE_STATS` | Foreground time per app, used to attribute measured battery consumption. Optional — the rest of the app works without it. |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | Prevents Doze from suspending sampling mid-charge. Optional, prompted once, explained in the app. |
| `RECEIVE_BOOT_COMPLETED` | Resume sampling after a reboot so the record has no hole. |
| `POST_NOTIFICATIONS` | Charge alarm and battery alerts. |

### Note on the special-use foreground service

Android 14+ requires a `PROPERTY_SPECIAL_USE_FGS_SUBTYPE` declaration and Play
review of the justification. The declared subtype is in `AndroidManifest.xml`.
Expect to repeat that reasoning in the Play Console form.

## Screenshot plan

| # | Screen | Caption |
|---|---|---|
| 1 | Dashboard, charging | Everything your battery is doing, right now |
| 2 | Health | What your battery really holds — measured, not claimed |
| 3 | Health, evidence section | See the evidence behind every number |
| 4 | Charging, live | Find out which charger is actually the fastest |
| 5 | History | Every charge and discharge, in detail |
| 6 | Apps | Where your battery actually went |
| 7 | Settings, charge alarm | Charge to 80% and make your battery last longer |
| 8 | Home screen with widgets | Your battery at a glance, without opening the app |

Feature graphic: 1024×500, deep navy (#101B2D) background, electric green (#39E75F)
battery-and-magnifier mark, wordmark plus "Monitor. Analyze. Optimize."

## Pre-launch checklist

- [ ] Replace the debug signing config with a real upload key
- [ ] Add a privacy policy URL (required even with no data collection)
- [ ] Generate launcher icons at every density from the brand mark
- [ ] Complete the special-use FGS declaration in the Play Console
- [ ] Test on at least one device per major OEM — battery property support varies
      most by manufacturer
