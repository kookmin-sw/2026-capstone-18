package com.littlesignals.capture

/** One HR/PPG/EDA sample. Times are Galaxy Watch SDK `DataPoint.timestamp` (UTC ms). */
data class ScalarSample(val timestampMs: Long, val value: Double)

/** One accelerometer sample (x/y/z, m/s² per Samsung SDK convention). */
data class AccelSample(val timestampMs: Long, val x: Double, val y: Double, val z: Double)

/**
 * Thread-safe accumulator for one second of samples across four channels.
 * One instance per phone-initiated capture session — owned by [PhoneSenderConsumer].
 *
 * Producers are the four StreamingRecorders (each on its own SDK callback thread).
 * Consumer is the consumer's 1 Hz flush coroutine.
 */
class SampleBatch {
    private val hr = mutableListOf<ScalarSample>()
    private val ppg = mutableListOf<ScalarSample>()
    private val eda = mutableListOf<ScalarSample>()
    private val accel = mutableListOf<AccelSample>()

    @Synchronized fun addHr(s: ScalarSample) { hr.add(s) }
    @Synchronized fun addPpg(s: ScalarSample) { ppg.add(s) }
    @Synchronized fun addEda(s: ScalarSample) { eda.add(s) }
    @Synchronized fun addAccel(s: AccelSample) { accel.add(s) }

    @Synchronized fun isEmpty(): Boolean = hr.isEmpty() && ppg.isEmpty() && eda.isEmpty() && accel.isEmpty()

    /**
     * Atomically take a snapshot of all buffered samples and clear them.
     * Returns a [Drain] whose lists are detached copies — safe to serialize.
     */
    @Synchronized fun drain(): Drain {
        val out = Drain(hr.toList(), ppg.toList(), eda.toList(), accel.toList())
        hr.clear(); ppg.clear(); eda.clear(); accel.clear()
        return out
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
