package com.littlesignals.capture

import org.json.JSONArray
import org.json.JSONObject
import timber.log.Timber

class PhoneSenderConsumer(
    private val sender: (path: String, body: String) -> Boolean,
) : CaptureConsumer {

    private val hr = mutableListOf<Sample.Scalar>()
    private val ppg = mutableListOf<Sample.Scalar>()
    private val eda = mutableListOf<Sample.Scalar>()
    private val accel = mutableListOf<Sample.Vector>()
    private var sessionStartMs: Long = 0L

    override fun onSessionStart(startedAtMs: Long, durationMs: Long) {
        sessionStartMs = startedAtMs
        hr.clear(); ppg.clear(); eda.clear(); accel.clear()
    }

    override fun onSample(channel: Channel, sample: Sample) {
        when (channel) {
            Channel.HR -> if (sample is Sample.Scalar) hr.add(sample)
            Channel.PPG -> if (sample is Sample.Scalar) ppg.add(sample)
            Channel.EDA -> if (sample is Sample.Scalar) eda.add(sample)
            Channel.ACCEL -> if (sample is Sample.Vector) accel.add(sample)
        }
    }

    override fun onSessionEnd(reason: EndReason, error: String?) {
        flushNow(nowMs = System.currentTimeMillis())
        val body = JSONObject().apply {
            put("reason", when (reason) {
                EndReason.COMPLETED -> "completed"
                EndReason.USER_STOPPED -> "user_stopped"
                EndReason.ERROR -> "error"
            })
            put("error", error)
        }.toString()
        runCatching { sender("/biosignals/end", body) }
            .onFailure { Timber.w(it, "send /biosignals/end failed") }
    }

    fun flushNow(nowMs: Long) {
        if (hr.isEmpty() && ppg.isEmpty() && eda.isEmpty() && accel.isEmpty()) return
        val body = JSONObject().apply {
            put("tStartMs", sessionStartMs)
            put("hr", JSONArray().apply {
                for (s in hr) put(JSONObject().put("t", s.timestampMs).put("v", s.value))
            })
            put("ppg", JSONArray().apply {
                for (s in ppg) put(JSONObject().put("t", s.timestampMs).put("v", s.value))
            })
            put("eda", JSONArray().apply {
                for (s in eda) put(JSONObject().put("t", s.timestampMs).put("v", s.value))
            })
            put("accel", JSONArray().apply {
                for (s in accel) {
                    val v = s.values
                    put(JSONObject().put("t", s.timestampMs)
                        .put("x", v.getOrElse(0) { 0.0 })
                        .put("y", v.getOrElse(1) { 0.0 })
                        .put("z", v.getOrElse(2) { 0.0 }))
                }
            })
        }.toString()
        runCatching { sender("/biosignals/samples", body) }
            .onFailure { Timber.w(it, "send /biosignals/samples failed") }
        hr.clear(); ppg.clear(); eda.clear(); accel.clear()
    }
}
