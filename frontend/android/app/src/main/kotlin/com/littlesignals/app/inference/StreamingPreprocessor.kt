package com.littlesignals.app.inference

import com.littlesignals.app.capture.ScalarSample
import com.littlesignals.app.capture.VectorSample

/**
 * Accumulates raw watch samples in per-channel ring buffers; produces a
 * 25 Hz 7500-sample [SyncedSignals] snapshot on demand. One instance per
 * capture session — owned by [StreamingInferenceCoordinator].
 *
 * Thread model: assume single-threaded access from the capture coroutine.
 * Adding synchronization here would add lock contention with no gain — the
 * capture loop is the only writer and the only snapshot caller.
 */
class StreamingPreprocessor(
    private val targetHz: Int = 25,
    private val bufferSec: Int = 300,
    private val overlapSec: Int = 5,
) {
    private data class Scalar(val ts: Long, val v: Double)
    private data class Vector(val ts: Long, val x: Double, val y: Double, val z: Double)

    private val ppg = ArrayDeque<Scalar>()
    private val eda = ArrayDeque<Scalar>()
    private val accel = ArrayDeque<Vector>()
    private var latestMs: Long = 0L

    fun appendBatch(ppg: List<ScalarSample>, eda: List<ScalarSample>, accel: List<VectorSample>) {
        for (s in ppg) { this.ppg.addLast(Scalar(s.timestampMs, s.value)); if (s.timestampMs > latestMs) latestMs = s.timestampMs }
        for (s in eda) { this.eda.addLast(Scalar(s.timestampMs, s.value)); if (s.timestampMs > latestMs) latestMs = s.timestampMs }
        for (s in accel) {
            this.accel.addLast(Vector(s.timestampMs, s.values[0], s.values[1], s.values[2]))
            if (s.timestampMs > latestMs) latestMs = s.timestampMs
        }
        evictOlderThan(latestMs - (bufferSec + overlapSec) * 1000L)
    }

    private fun evictOlderThan(cutoffMs: Long) {
        while (ppg.isNotEmpty() && ppg.first().ts < cutoffMs) ppg.removeFirst()
        while (eda.isNotEmpty() && eda.first().ts < cutoffMs) eda.removeFirst()
        while (accel.isNotEmpty() && accel.first().ts < cutoffMs) accel.removeFirst()
    }

    fun ppgSampleCount(): Int = ppg.size
    fun edaSampleCount(): Int = eda.size
    fun accelSampleCount(): Int = accel.size
    fun latestSampleAtMs(): Long = latestMs

    fun snapshot25Hz(): SyncedSignals? {
        if (ppg.isEmpty() || eda.isEmpty() || accel.isEmpty()) return null
        val tEnd = minOf(ppg.last().ts, eda.last().ts, accel.last().ts)
        val tStart = tEnd - bufferSec * 1000L
        if (ppg.first().ts > tStart || eda.first().ts > tStart || accel.first().ts > tStart) return null

        val nSamples = bufferSec * targetHz  // 7500
        val targetTimes = DoubleArray(nSamples) { i -> i.toDouble() / targetHz }

        val ppgInWindow = ppg.dropWhile { it.ts < tStart }
        val edaInWindow = eda.dropWhile { it.ts < tStart }
        val accelInWindow = accel.dropWhile { it.ts < tStart }

        val ppgTimes = LongArray(ppgInWindow.size) { ppgInWindow[it].ts }
        val ppgValues = DoubleArray(ppgInWindow.size) { ppgInWindow[it].v }
        val edaTimes = LongArray(edaInWindow.size) { edaInWindow[it].ts }
        val edaValues = DoubleArray(edaInWindow.size) { edaInWindow[it].v }
        val accelTimes = LongArray(accelInWindow.size) { accelInWindow[it].ts }
        val accelX = DoubleArray(accelInWindow.size) { accelInWindow[it].x }
        val accelY = DoubleArray(accelInWindow.size) { accelInWindow[it].y }
        val accelZ = DoubleArray(accelInWindow.size) { accelInWindow[it].z }

        if (ppgTimes.size < 2 || edaTimes.isEmpty() || accelTimes.size < 2) return null

        fun rebase(times: LongArray): DoubleArray =
            DoubleArray(times.size) { i -> (times[i] - tStart) / 1000.0 }

        val ppgRaw = DspPrimitives.linearInterp(rebase(ppgTimes), ppgValues, targetTimes)
        val edaRaw = DspPrimitives.previousInterp(rebase(edaTimes), edaValues, targetTimes)
        val accX = DspPrimitives.linearInterp(rebase(accelTimes), accelX, targetTimes)
        val accY = DspPrimitives.linearInterp(rebase(accelTimes), accelY, targetTimes)
        val accZ = DspPrimitives.linearInterp(rebase(accelTimes), accelZ, targetTimes)

        val ppgSmooth = DspPrimitives.savgolWindow5Poly2(
            DspPrimitives.butterworthBandpassFiltFilt(ppgRaw)
        )
        val accMag = DoubleArray(nSamples) { i -> kotlin.math.sqrt(accX[i] * accX[i] + accY[i] * accY[i] + accZ[i] * accZ[i]) }

        return SyncedSignals(
            ppgSmooth = ppgSmooth,
            eda = edaRaw,
            accMag = accMag,
            durationSeconds = bufferSec.toDouble(),
        )
    }
}
