package com.littlesignals.app.capture

import kotlin.math.cos
import kotlin.random.Random

data class ScalarSample(val timestampMs: Long, val value: Double)
data class VectorSample(val timestampMs: Long, val values: List<Double>)

class SyntheticSampleSource(seed: Long = System.currentTimeMillis()) {
    private val rng = Random(seed)
    private val hrBuf = ArrayDeque<ScalarSample>()
    private val ppgBuf = ArrayDeque<ScalarSample>()
    private val edaBuf = ArrayDeque<ScalarSample>()
    private val accelBuf = ArrayDeque<VectorSample>()
    private var hrCurrent = 75.0

    fun advanceTo(toMs: Long, fromMs: Long) {
        var t = (fromMs / 1000L) * 1000L
        if (t < fromMs) t += 1000L
        while (t < toMs) {
            hrCurrent = (hrCurrent + rng.nextDouble(-2.0, 2.0)).coerceIn(55.0, 105.0)
            hrBuf.add(ScalarSample(t, hrCurrent)); t += 1000L
        }
        t = (fromMs / 40L) * 40L
        if (t < fromMs) t += 40L
        while (t < toMs) {
            val v = 0.5 * cos(t * 2 * Math.PI / 1000.0) + rng.nextDouble(-0.05, 0.05)
            ppgBuf.add(ScalarSample(t, v)); t += 40L
        }
        t = (fromMs / 40L) * 40L
        if (t < fromMs) t += 40L
        while (t < toMs) {
            val v = 5.0 + rng.nextDouble(-0.1, 0.1)
            edaBuf.add(ScalarSample(t, v)); t += 40L
        }
        t = (fromMs / 20L) * 20L
        if (t < fromMs) t += 20L
        while (t < toMs) {
            val x = rng.nextDouble(-0.1, 0.1); val y = rng.nextDouble(-0.1, 0.1)
            val z = 9.8 + rng.nextDouble(-0.1, 0.1)
            accelBuf.add(VectorSample(t, listOf(x, y, z))); t += 20L
        }
    }
    fun drainHr(): List<ScalarSample> = hrBuf.toList().also { hrBuf.clear() }
    fun drainPpg(): List<ScalarSample> = ppgBuf.toList().also { ppgBuf.clear() }
    fun drainEda(): List<ScalarSample> = edaBuf.toList().also { edaBuf.clear() }
    fun drainAccel(): List<VectorSample> = accelBuf.toList().also { accelBuf.clear() }
}
