package com.littlesignals.app.inference

import com.littlesignals.app.capture.ScalarSample
import com.littlesignals.app.capture.VectorSample
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class StreamingInferenceCoordinatorTest {

    private class ConstEngine(private val v: Double) : InferenceEngine {
        override fun runChunkProbStress(channels: Array<FloatArray>): Double = v
        override fun close() {}
    }

    private fun fill300Seconds(pre: StreamingPreprocessor, startMs: Long) {
        val ppg = mutableListOf<ScalarSample>()
        val eda = mutableListOf<ScalarSample>()
        val accel = mutableListOf<VectorSample>()
        var t = startMs
        while (t <= startMs + 305_000L) {
            ppg += ScalarSample(t, kotlin.math.sin(t.toDouble() / 1000.0))
            eda += ScalarSample(t, 5.0)
            accel += VectorSample(t, listOf(0.0, 0.0, 9.8))
            t += 40L
        }
        pre.appendBatch(ppg, eda, accel)
    }

    @Test fun `coordinator stays uncalibrated until 180s of data accumulated`() {
        val pre = StreamingPreprocessor()
        val engine = ConstEngine(0.0)
        val coord = StreamingInferenceCoordinator(pre, engine)
        // Push only 100 seconds of samples
        val t0 = 1_700_000_000_000L
        val ppg = (0 until 25 * 100).map { i -> ScalarSample(t0 + i * 40L, 1.0) }
        val eda = (0 until 100).map { i -> ScalarSample(t0 + i * 1000L, 5.0) }
        val accel = (0 until 25 * 100).map { i -> VectorSample(t0 + i * 40L, listOf(0.0, 0.0, 9.8)) }
        pre.appendBatch(ppg, eda, accel)
        coord.tick(currentMs = t0 + 100_000L)
        assertFalse("must not calibrate with < 180s of data", coord.isCalibrated())
    }

    @Test fun `coordinator calibrates on first tick after 180s+ of contiguous data`() {
        val pre = StreamingPreprocessor()
        val engine = ConstEngine(0.0)
        val coord = StreamingInferenceCoordinator(pre, engine)
        val t0 = 1_700_000_000_000L
        fill300Seconds(pre, t0)
        coord.tick(currentMs = t0 + 300_000L)
        assertTrue("must calibrate now that snapshot is full", coord.isCalibrated())
    }

    @Test fun `coordinator emits exactly one detection per tickIntervalSec after calibration`() {
        val pre = StreamingPreprocessor()
        val engine = ConstEngine(0.42)
        val detections = mutableListOf<DetectionResult>()
        val coord = StreamingInferenceCoordinator(pre, engine, tickIntervalSec = 60, listener = { detections += it })
        val t0 = 1_700_000_000_000L
        fill300Seconds(pre, t0)
        coord.tick(currentMs = t0 + 300_000L)  // calibrates + first inference
        coord.tick(currentMs = t0 + 320_000L)  // only 20s after — no new inference yet
        coord.tick(currentMs = t0 + 361_000L)  // 61s after first inference — second inference

        assertEquals("expected 2 detections", 2, detections.size)
        assertEquals(0.42, detections[0].probStress, 1e-12)
        assertEquals(t0 + 300_000L, detections[0].detectedAtMs)
        assertEquals(t0 + 361_000L, detections[1].detectedAtMs)
    }

    @Test fun `coordinator surfaces shouldNotify from StressPipeline decision`() {
        val pre = StreamingPreprocessor()
        // High probability + zero motion (calibrated against still data) → notify
        val engine = ConstEngine(0.95)
        val detections = mutableListOf<DetectionResult>()
        val coord = StreamingInferenceCoordinator(pre, engine, listener = { detections += it })
        val t0 = 1_700_000_000_000L
        fill300Seconds(pre, t0)
        coord.tick(currentMs = t0 + 300_000L)
        assertNotNull(detections.firstOrNull())
        assertTrue("first high-prob detection should notify", detections.first().shouldNotify)
        assertTrue("state should be STRESS_EVENT", detections.first().inStressEvent)
    }
}
