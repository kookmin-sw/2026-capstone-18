package com.littlesignals.capture

/** One HR/PPG/EDA sample. Times are Galaxy Watch SDK `DataPoint.timestamp` (UTC ms). */
data class ScalarSample(val timestampMs: Long, val value: Double)

/** One accelerometer sample (x/y/z, m/s² per Samsung SDK convention). */
data class AccelSample(val timestampMs: Long, val x: Double, val y: Double, val z: Double)

/**
 * Maximum number of samples held per channel before the oldest is evicted.
 *
 * At PPG 25 Hz this caps ~20 s of buffered data. If the phone is unreachable
 * for longer, older samples are dropped to keep memory bounded. Matches the
 * buffer-size that `restore()` respects when re-queuing a failed send.
 */
const val MAX_SAMPLES_PER_CHANNEL = 500

/**
 * Thread-safe accumulator for one second of samples across four channels.
 * One instance per phone-initiated capture session — owned by [PhoneSenderConsumer].
 *
 * Producers are the four StreamingRecorders (each on its own SDK callback thread).
 * Consumer is the 1 Hz flush coroutine in [PhoneSenderConsumer].
 *
 * Each channel is bounded at [MAX_SAMPLES_PER_CHANNEL] samples. When full,
 * the oldest sample is evicted on each new add to keep memory bounded during
 * prolonged phone-unreachability periods.
 */
class SampleBatch {
    private val hr = ArrayDeque<ScalarSample>()
    private val ppg = ArrayDeque<ScalarSample>()
    private val eda = ArrayDeque<ScalarSample>()
    private val accel = ArrayDeque<AccelSample>()

    @Synchronized fun addHr(s: ScalarSample) {
        if (hr.size >= MAX_SAMPLES_PER_CHANNEL) hr.removeFirst()
        hr.addLast(s)
    }

    @Synchronized fun addPpg(s: ScalarSample) {
        if (ppg.size >= MAX_SAMPLES_PER_CHANNEL) ppg.removeFirst()
        ppg.addLast(s)
    }

    @Synchronized fun addEda(s: ScalarSample) {
        if (eda.size >= MAX_SAMPLES_PER_CHANNEL) eda.removeFirst()
        eda.addLast(s)
    }

    @Synchronized fun addAccel(s: AccelSample) {
        if (accel.size >= MAX_SAMPLES_PER_CHANNEL) accel.removeFirst()
        accel.addLast(s)
    }

    @Synchronized fun isEmpty(): Boolean =
        hr.isEmpty() && ppg.isEmpty() && eda.isEmpty() && accel.isEmpty()

    /**
     * Atomically take a snapshot of all buffered samples and clear the deques.
     * Returns a [Drain] whose lists are detached copies — safe to serialize off-thread.
     */
    @Synchronized fun drain(): Drain {
        val out = Drain(hr.toList(), ppg.toList(), eda.toList(), accel.toList())
        hr.clear(); ppg.clear(); eda.clear(); accel.clear()
        return out
    }

    /**
     * Re-queue samples from a failed send drain back into the batch.
     *
     * Old samples (from [drain]) are prepended before new samples so timestamps
     * remain chronological. If the combined size exceeds [MAX_SAMPLES_PER_CHANNEL]
     * per channel, the oldest samples are dropped.
     *
     * Called by [PhoneSenderConsumer.flushIfNonEmpty] when [PhoneSender.send] returns false.
     */
    @Synchronized fun restore(drain: Drain) {
        fun <T> mergeChannel(old: List<T>, current: ArrayDeque<T>): ArrayDeque<T> {
            val combined = old + current.toList()
            val trimmed = combined.takeLast(MAX_SAMPLES_PER_CHANNEL)
            return ArrayDeque<T>(trimmed.size).also { dq -> trimmed.forEach { dq.addLast(it) } }
        }
        val newHr = mergeChannel(drain.hr, hr)
        val newPpg = mergeChannel(drain.ppg, ppg)
        val newEda = mergeChannel(drain.eda, eda)
        val newAccel = mergeChannel(drain.accel, accel)
        hr.clear(); hr.addAll(newHr)
        ppg.clear(); ppg.addAll(newPpg)
        eda.clear(); eda.addAll(newEda)
        accel.clear(); accel.addAll(newAccel)
    }

    data class Drain(
        val hr: List<ScalarSample>,
        val ppg: List<ScalarSample>,
        val eda: List<ScalarSample>,
        val accel: List<AccelSample>,
    )
}

/**
 * Serialize a [SampleBatch.Drain] to the JSON shape the phone's `WatchSourceController`
 * parses. Schema is locked by the phone-side test
 * `frontend/android/app/src/test/kotlin/com/littlesignals/app/capture/WatchSourceControllerTest.kt`
 * — do not change keys without updating the phone side first.
 */
fun serializeBatchPayload(tStartMs: Long, drain: SampleBatch.Drain): String {
    val root = org.json.JSONObject()
    root.put("tStartMs", tStartMs)
    val hrArr = org.json.JSONArray()
    for (s in drain.hr) {
        hrArr.put(org.json.JSONObject().put("t", s.timestampMs).put("v", s.value))
    }
    root.put("hr", hrArr)
    val ppgArr = org.json.JSONArray()
    for (s in drain.ppg) {
        ppgArr.put(org.json.JSONObject().put("t", s.timestampMs).put("v", s.value))
    }
    root.put("ppg", ppgArr)
    val edaArr = org.json.JSONArray()
    for (s in drain.eda) {
        edaArr.put(org.json.JSONObject().put("t", s.timestampMs).put("v", s.value))
    }
    root.put("eda", edaArr)
    val accelArr = org.json.JSONArray()
    for (s in drain.accel) {
        accelArr.put(
            org.json.JSONObject()
                .put("t", s.timestampMs)
                .put("x", s.x)
                .put("y", s.y)
                .put("z", s.z)
        )
    }
    root.put("accel", accelArr)
    return root.toString()
}
