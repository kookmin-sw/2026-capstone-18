package com.littlesignals.app.capture

import org.json.JSONObject

class WatchSourceController {
    private val hr = mutableListOf<ScalarSample>()
    private val ppg = mutableListOf<ScalarSample>()
    private val eda = mutableListOf<ScalarSample>()
    private val accel = mutableListOf<VectorSample>()

    @Volatile var lastSampleAtMs: Long = 0L
        private set
    @Volatile var lastEndReason: String? = null
        private set
    @Volatile var lastEndError: String? = null
        private set

    fun acceptBatch(json: String) {
        val obj = JSONObject(json)
        readScalar(obj, "hr", hr)
        readScalar(obj, "ppg", ppg)
        readScalar(obj, "eda", eda)
        readVector(obj, "accel", accel)
    }

    fun acceptEnd(reason: String, error: String?) {
        lastEndReason = reason; lastEndError = error
    }

    fun drainHr(): List<ScalarSample> = synchronized(hr) { hr.toList().also { hr.clear() } }
    fun drainPpg(): List<ScalarSample> = synchronized(ppg) { ppg.toList().also { ppg.clear() } }
    fun drainEda(): List<ScalarSample> = synchronized(eda) { eda.toList().also { eda.clear() } }
    fun drainAccel(): List<VectorSample> = synchronized(accel) { accel.toList().also { accel.clear() } }

    private fun readScalar(obj: JSONObject, key: String, out: MutableList<ScalarSample>) {
        if (!obj.has(key)) return
        val arr = obj.getJSONArray(key)
        synchronized(out) {
            for (i in 0 until arr.length()) {
                val s = arr.getJSONObject(i)
                val ts = s.getLong("t"); val v = s.getDouble("v")
                out.add(ScalarSample(ts, v))
                if (ts > lastSampleAtMs) lastSampleAtMs = ts
            }
        }
    }

    private fun readVector(obj: JSONObject, key: String, out: MutableList<VectorSample>) {
        if (!obj.has(key)) return
        val arr = obj.getJSONArray(key)
        synchronized(out) {
            for (i in 0 until arr.length()) {
                val s = arr.getJSONObject(i)
                val ts = s.getLong("t")
                val xs = listOf(s.getDouble("x"), s.getDouble("y"), s.getDouble("z"))
                out.add(VectorSample(ts, xs))
                if (ts > lastSampleAtMs) lastSampleAtMs = ts
            }
        }
    }

    fun reset() {
        synchronized(hr) { hr.clear() }
        synchronized(ppg) { ppg.clear() }
        synchronized(eda) { eda.clear() }
        synchronized(accel) { accel.clear() }
        lastSampleAtMs = 0L; lastEndReason = null; lastEndError = null
    }

    companion object {
        @JvmStatic
        val instance: WatchSourceController = WatchSourceController()
    }
}
