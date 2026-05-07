# sensor-capture

A Wear OS utility app for the Galaxy Watch 8 that records 10 minutes of raw sensor data across four channels and packs the result as a ZIP that can be `adb pull`'d off the watch and shared with the ML team.

This is a one-off research tool, not part of the production phone/watch app. It exists so we can hand Nika fresh capture files for model verification without building the full opt-in upload flow described in spec §11 / Sprint 5.

## What it captures

| Channel | Samsung tracker | Approx rate | What Nika uses it for |
|---|---|---|---|
| Heart rate + IBI | `HEART_RATE_CONTINUOUS` | ~1 Hz event-driven | HRV (the foundation of the stress model) |
| PPG green | `PPG_GREEN` | ~25 Hz | Raw optical signal, model input |
| EDA | `EDA_CONTINUOUS` | ~25 Hz | Skin conductance — second core stress signal |
| Accelerometer | `ACCELEROMETER_CONTINUOUS` | ~25–50 Hz | Motion artifact filter / activity gating |

Skin temperature is intentionally skipped — it's low-rate cycle context, not stress-model input.

## Output layout

After a successful 10-min capture you'll find on the watch:

```
/data/data/com.littlesignals.capture/files/captures/
├── 2026-05-06T15-30-00Z/
│   ├── heart_rate.csv          timestamp_ms, hr_bpm, ibi_ms, hr_status
│   ├── ppg_green.csv           timestamp_ms, ppg_green, status
│   ├── eda.csv                 timestamp_ms, resistance_kohm, status
│   ├── accel.csv               timestamp_ms, x, y, z
│   └── metadata.json           start/end ts, watch model, observed sample rates
└── 2026-05-06T15-30-00Z.zip    same contents, zipped — this is what you send Nika
```

`timestamp_ms` is the SDK's `DataPoint.timestamp` (wall-clock UTC milliseconds).

## Setup

You need:

- Android Studio (Iguana / Koala or newer)
- A Galaxy Watch 8 with developer mode enabled and `adb devices` listing it
- The vendored SDK AAR at `libs/samsung-health-sensor-api-1.4.1.aar` (already in this repo)

```bash
cd watch/sensor-capture
# Open the project in Android Studio. On first sync it generates the gradle
# wrapper jar and pulls the dependencies. If you prefer the CLI:
gradle wrapper --gradle-version 8.11.1
./gradlew :app:assembleDebug
```

If Android Studio reports unresolved references inside `ChannelRecorder.kt` (e.g. `ValueKey.HeartRateSet.HEART_RATE`), it's because the SDK's exact constant names drift between minor versions. Use the IDE's autocomplete on `ValueKey.` and pick the matching constant — the contract (HR bpm value, IBI list, status code, accelerometer x/y/z) is stable; only the field names vary. Common alternates:

- `ValueKey.HeartRateSet.HEART_RATE` ⇄ `HEART_RATE_VALUE`
- `ValueKey.HeartRateSet.IBI_LIST` ⇄ `IBI_VALUES`
- `ValueKey.EdaSet.RESISTANCE` ⇄ `SCL`
- `ValueKey.PpgGreenSet.PPG_GREEN` ⇄ `PPG_GREEN_VALUE`

Fix these in `ChannelRecorder.kt`; everything else compiles unchanged.

## Run the capture

1. Charge the watch to ≥80%. Continuous PPG + EDA pulls ~5%/hour.
2. Connect the watch via USB or Wi-Fi adb. Confirm: `adb devices`.
3. Install + launch:
   ```bash
   ./gradlew :app:installDebug
   adb shell am start -n com.littlesignals.capture/.CaptureActivity
   ```
4. On the watch: tap **Start 10 min**. Grant the body sensors permission if prompted.
5. **Sit still for the first 2 minutes**, then go about normal activity (walk a hallway, type, drink water, stand up, sit down). Nika needs both rest and motion segments to validate the activity-gating logic.
6. The screen shows the remaining-seconds countdown. When it says **Done — pull from …**, the capture is complete.

## Pull the data off the watch

```bash
# List capture sessions
adb shell run-as com.littlesignals.capture ls files/captures/

# Copy the zip out via run-as (debug builds only)
SESSION="2026-05-06T15-30-00Z"
adb exec-out run-as com.littlesignals.capture cat files/captures/${SESSION}.zip > ${SESSION}.zip

# Sanity-check
unzip -l ${SESSION}.zip
```

`adb exec-out run-as ... cat ...` is the canonical way to extract files from a debug app's private storage on Wear OS — `adb pull` of `/data/data/...` paths fails on non-rooted watches.

## Sanity-check before sending

```bash
unzip -p ${SESSION}.zip metadata.json | jq .

unzip -p ${SESSION}.zip heart_rate.csv | wc -l    # ~600 rows for 10 min
unzip -p ${SESSION}.zip ppg_green.csv | wc -l     # ~15000 rows
unzip -p ${SESSION}.zip eda.csv | wc -l           # ~15000 rows
unzip -p ${SESSION}.zip accel.csv | wc -l         # ~15000–30000 rows

unzip -p ${SESSION}.zip ppg_green.csv | head -5   # values should not all be 0/-1
```

Empty files or all-zero values mean the SDK didn't deliver events — usually a permission denied silently, or the watch wasn't worn skin-tight. Re-check `adb logcat | grep -i capture` and re-run.

## Send to Nika

Drop the zip into the team's shared Drive folder (or KakaoTalk file attachment). Include a short note:

> Galaxy Watch 8, Sensor SDK 1.4.1, captured 2026-05-06 15:30 UTC.
> First 2 min sitting still, last 8 min normal activity (walking + typing).
> Channels: HR/IBI, PPG green, EDA, accel. Per-channel CSVs in the zip;
> metadata.json has the observed sample rates.

## Reusing this app

The `CaptureActivity` is parameterized only by the constant `DURATION_MIN`. If Nika asks for longer captures or different channels, edit:

- Duration: `CaptureActivity.kt` → `DURATION_MIN`
- Channels: `ChannelRecorder.kt` → `companion object { fun all() = listOf(...) }`

Future production work for multi-user research-mode capture is tracked separately as a Sprint 7 follow-up (see backend's privacy + audit sprint).
