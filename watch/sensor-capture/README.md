# sensor-capture

The Wear OS app that runs on the Galaxy Watch 8 — both as part of the production Little Signals pipeline (phone-driven streaming for live stress inference) and as a standalone research tool (10-minute ZIP exports for model verification).

## What it captures

| Channel | Samsung tracker | Approx rate | Used for |
|---|---|---|---|
| Heart rate + IBI | `HEART_RATE_CONTINUOUS` | ~1 Hz event-driven | HRV (the foundation of the stress model) |
| PPG green | `PPG_GREEN` | ~25 Hz | Raw optical signal, model input |
| EDA | `EDA_CONTINUOUS` | ~25 Hz | Skin conductance — second core stress signal |
| Accelerometer | `ACCELEROMETER_CONTINUOUS` | ~25–50 Hz | Motion artifact filter / activity gating |

Skin temperature is intentionally skipped — it's low-rate cycle context, not stress-model input.

## Two modes

The app exposes two independent capture entry points that share the same underlying `ChannelRecorder` and Samsung Health Sensor SDK code:

### Mode 1 — Phone-driven streaming (production)

When the user opts in via the phone app's Biosignal Capture screen, the phone sends control messages over the Wear Data Layer and the watch streams 4-channel sample batches back to the phone in real time. The phone runs ONNX Mamba inference against each window and creates `stress_event` rows via the backend REST API.

**Wear Data Layer paths (phone → watch):**

| Path | Body | Watch behavior |
|---|---|---|
| `/biosignals/start` | `{"durationSec": <int> or omitted}` | `WatchControlListener` starts `RemoteCaptureService` as a foreground service; opens all four channels. |
| `/biosignals/stop` | `{}` | Stops the foreground service and tears down channels. |

**Watch → phone:** `WearPhoneSender` batches `SampleBatch` payloads (per-channel buffered samples with millisecond timestamps) and posts them back over the Data Layer for the phone-side `BiosignalCaptureService` to consume. `LiveSnapshot` + `StreamingRecorder` keep the watch UI in sync without blocking the sender.

Key files: [`WatchControlListener.kt`](app/src/main/kotlin/com/littlesignals/capture/WatchControlListener.kt), [`RemoteCaptureService.kt`](app/src/main/kotlin/com/littlesignals/capture/RemoteCaptureService.kt), [`RemoteCaptureSession.kt`](app/src/main/kotlin/com/littlesignals/capture/RemoteCaptureSession.kt), [`WearPhoneSender.kt`](app/src/main/kotlin/com/littlesignals/capture/WearPhoneSender.kt), [`PhoneSender.kt`](app/src/main/kotlin/com/littlesignals/capture/PhoneSender.kt), [`StreamingRecorder.kt`](app/src/main/kotlin/com/littlesignals/capture/StreamingRecorder.kt).

### Mode 2 — Standalone 10-minute ZIP capture (research)

Used when the ML team needs fresh raw capture files for model verification without going through the full phone/backend round-trip. The user taps **Start 10 min** on the watch directly; the watch records into a per-session folder under its app-private storage and zips it for `adb pull`.

This mode predates the production streaming flow and remains useful for offline experiments. Both modes can coexist in the same APK — they share `ChannelRecorder` and the SDK glue, but neither depends on the other.

Key files: [`CaptureActivity.kt`](app/src/main/kotlin/com/littlesignals/capture/CaptureActivity.kt), [`CaptureSession.kt`](app/src/main/kotlin/com/littlesignals/capture/CaptureSession.kt), [`ChannelRecorder.kt`](app/src/main/kotlin/com/littlesignals/capture/ChannelRecorder.kt), [`SampleBatch.kt`](app/src/main/kotlin/com/littlesignals/capture/SampleBatch.kt).

## Output layout (Mode 2 only)

After a successful 10-min capture you'll find on the watch:

```
/data/data/com.littlesignals.capture/files/captures/
├── 2026-05-06T15-30-00Z/
│   ├── heart_rate.csv          timestamp_ms, hr_bpm, ibi_ms, hr_status
│   ├── ppg_green.csv           timestamp_ms, ppg_green, status
│   ├── eda.csv                 timestamp_ms, resistance_kohm, status
│   ├── accel.csv               timestamp_ms, x, y, z
│   └── metadata.json           start/end ts, watch model, observed sample rates
└── 2026-05-06T15-30-00Z.zip    same contents, zipped — this is what you send the ML team
```

`timestamp_ms` is the SDK's `DataPoint.timestamp` (wall-clock UTC milliseconds). Mode 1 streams the same per-sample tuples in `SampleBatch` form without ever materializing CSV/ZIP files on the watch.

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

## Mode 1 — Triggering a streaming capture from the phone

This is the production path. The phone app's Biosignal Capture screen handles it; the watch needs no manual interaction. Under the hood the phone calls `MessageClient.sendMessage(nodeId, "/biosignals/start", ...)`. The watch's `WatchControlListener` responds by launching `RemoteCaptureService` as a foreground service, which:

1. Posts a persistent notification (Android 14+ foreground-service requirement)
2. Subscribes to all four SDK channels via `ChannelRecorder`
3. Streams sample batches back over the Data Layer through `WearPhoneSender`
4. Tears down cleanly on `/biosignals/stop` or when the duration timer elapses

To smoke-test without the phone, you can use `wear-debug` to push messages:

```bash
adb shell "am startservice -n com.littlesignals.capture/.RemoteCaptureService -a com.littlesignals.capture.REMOTE_START --ei duration_sec 60"
```

## Mode 2 — Running a 10-minute ZIP capture

1. Charge the watch to ≥80%. Continuous PPG + EDA pulls ~5%/hour.
2. Connect the watch via USB or Wi-Fi adb. Confirm: `adb devices`.
3. Install + launch:
   ```bash
   ./gradlew :app:installDebug
   adb shell am start -n com.littlesignals.capture/.CaptureActivity
   ```
4. On the watch: tap **Start 10 min**. Grant the body sensors permission if prompted.
5. **Sit still for the first 2 minutes**, then go about normal activity (walk a hallway, type, drink water, stand up, sit down). Both rest and motion segments are needed to validate the activity-gating logic.
6. The screen shows the remaining-seconds countdown. When it says **Done — pull from …**, the capture is complete.

## Pull the data off the watch (Mode 2)

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

## Sanity-check before sending (Mode 2)

```bash
unzip -p ${SESSION}.zip metadata.json | jq .

unzip -p ${SESSION}.zip heart_rate.csv | wc -l    # ~600 rows for 10 min
unzip -p ${SESSION}.zip ppg_green.csv | wc -l     # ~15000 rows
unzip -p ${SESSION}.zip eda.csv | wc -l           # ~15000 rows
unzip -p ${SESSION}.zip accel.csv | wc -l         # ~15000–30000 rows

unzip -p ${SESSION}.zip ppg_green.csv | head -5   # values should not all be 0/-1
```

Empty files or all-zero values mean the SDK didn't deliver events — usually a permission denied silently, or the watch wasn't worn skin-tight. Re-check `adb logcat | grep -i capture` and re-run.

## Customizing capture

Both modes are parameterized only by duration and the channel list:

- Duration (Mode 2 default): `CaptureActivity.kt` → `DURATION_MIN`
- Duration (Mode 1): supplied by the phone in the `/biosignals/start` payload (`durationSec`); the watch defaults to indefinite-until-stop if omitted
- Channels (both modes): `ChannelRecorder.kt` → `companion object { fun all() = listOf(...) }`
