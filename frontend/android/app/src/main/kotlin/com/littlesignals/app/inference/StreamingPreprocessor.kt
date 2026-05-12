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
        // Concrete snapshot construction lives in Task 3.
        TODO("snapshot25Hz implementation lands in Task 3")
    }
}
