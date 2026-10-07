# Phase 0 – on-device test protocol

Throwaway spikes. Nothing here is production code. Each test writes a JSON log you
pull back to the PC and send to me (or paste the "Copy summary" text).

## 0. One-time setup

1. Phone: Settings > About phone > tap "Build number" 7x > Developer options >
   enable **USB debugging**. Connect by USB and accept the RSA prompt.
2. PC (PowerShell):
   ```
   $adb = "$env:LOCALAPPDATA\Android\sdk\platform-tools\adb.exe"
   & $adb devices -l          # phone must be listed as "device"
   flutter devices
   ```
3. Note: phone model, Android version, and whether the phone is on
   https://developers.google.com/ar/devices

## 1. Wi-Fi spike (`spikes/wifi_spike`)

Install both permission variants (they install side by side):
```
cd "spikes\wifi_spike"
flutter run --flavor standard      # app name "Wi-Fi spike"
flutter run --flavor neverloc      # app name "Wi-Fi spike (neverloc)"
```

Run in the `standard` app first. Connect the phone to the Wi-Fi network you will
survey later.

| # | Step | What it answers |
|---|------|-----------------|
| W1 | Open app **before** granting anything. Run "Scan once" and "Run cadence test" (10 s is enough; you can go back). | What is redacted / blocked with no permissions |
| W2 | "Request location" → allow **Precise**. Repeat "Scan once". | Scan results + BSSID with location |
| W3 | Turn **Location services OFF** (quick settings). "Scan once" + cadence test. Turn back on. | Location-off behaviour |
| W4 | Developer options: note "Wi-Fi scan throttling" state (also shown as `scanThrottleEnabled`). With throttling **ON**: "Run burst" (2.5 min). | Real throttling: accepted vs rejected, `updated=false` broadcasts |
| W5 | If throttling can be turned OFF: turn it off, kill & reopen the app, "Run burst" again. | Whether the developer option removes the limit |
| W6 | Phone lying still on a table, screen on: "Run cadence test" (60 s). | How often connected RSSI really changes per source |
| W7 | Repeat W6 while slowly walking around. | Cadence under movement, roaming / BSSID changes |
| W8 | "Save JSON log". | — |

Then in the **neverloc** app (Android 13+ only): deny location, grant
"Nearby Wi-Fi devices" only, repeat W1/W2/W6 and save the log.

## 2. AR spike (`spikes/ar_spike`)

```
cd "spikes\ar_spike"
flutter run --profile        # profile mode: realistic frame timings
```

Prepare a room: put **masking tape crosses** on the floor at a start point and,
if possible, measure the room width with a tape measure.

| # | Step | What it answers |
|---|------|-----------------|
| A1 | Gate screen: note ARCore availability text. Install ARCore if offered. Grant camera. | Availability states |
| A2 | Mode **Hybrid Composition** → "Start AR test". Move the phone slowly over the floor until `floorY` appears. "Drop marker", then "Grid 0.5 m". | Floor detection |
| A3 | Pan / rotate the phone quickly left-right. Watch whether markers **slide** relative to the floor ("swimming"), and note the `render->paint ms` line. | Option A sync / latency |
| A4 | Hold still for 30 s, then "Save log". | Steady-state latency & jitter |
| A5 | Repeat A2–A4 with mode **Texture Layer / default**. Note if the camera image is black, frozen or works. | PlatformView mode compatibility |
| A6 | Well-lit room: stand phone over the tape cross at chest height, "Mark start". Walk the whole room perimeter slowly (≥ 1 lap), return, hold the phone over the same cross, "Mark return". "Save log". | Drift over a full-room walk |
| A7 | Repeat A6 in a **dim** room (lights off / curtains). | Tracking in low light |
| A8 | Point the camera at a **blank wall** from 0.5 m for 20 s, then a plain floor, "Save log". | Featureless-surface failure modes |

Also report subjectively: did markers visibly swim? Did the app stutter? Did the
phone get hot?

## 3. Pull logs back to the PC

```
$adb = "$env:LOCALAPPDATA\Android\sdk\platform-tools\adb.exe"
mkdir phase0_logs
& $adb pull /sdcard/Android/data/dev.rssimapper.wifi_spike/files/ phase0_logs\wifi_standard
& $adb pull /sdcard/Android/data/dev.rssimapper.wifi_spike.neverloc/files/ phase0_logs\wifi_neverloc
& $adb pull /sdcard/Android/data/dev.rssimapper.ar_spike/files/ phase0_logs\ar
```
Put `phase0_logs` in this `spikes/` folder and tell me. I will analyse the logs and
write the final Phase 0 findings report.

## Privacy

Logs contain nearby SSIDs/BSSIDs and AR poses only. No camera images are stored
(the AR spike never reads pixels back). Do not share logs publicly if nearby network
names are sensitive.
