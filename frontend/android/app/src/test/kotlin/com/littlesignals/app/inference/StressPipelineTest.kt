package com.littlesignals.app.inference

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class StressPipelineTest {
    @Test fun `calibrate sets baselines and flips calibrated flag`() {
        val pipeline = StressPipeline(engine = NullEngine())
        assertFalse(pipeline.isCalibrated)
        val n = 4500  // 180s at 25Hz
        val ppg = DoubleArray(n) { i -> 1.0 + 0.01 * i }
        val eda = DoubleArray(n) { 5.0 }
        val acc = DoubleArray(n) { 9.8 }
        pipeline.calibrate(ppg, eda, acc)
        assertTrue(pipeline.isCalibrated)
        // EDA is constant → mean=5.0, std=0 + 1e-8
        assertEquals(5.0, pipeline.meanEdaBase, 1e-9)
        assertEquals(1e-8, pipeline.stdEdaBase, 1e-12)
        // Acc 1g baseline
        assertEquals(9.8, pipeline.acc1gBaseline, 1e-9)
    }
}

private class NullEngine : InferenceEngine {
    override fun runChunkProbStress(channels: Array<FloatArray>): Double = 0.0
    override fun close() {}
}

class StressPipelineDecisionTest {

    private class ScriptedEngine(private val probs: ArrayDeque<Double>) : InferenceEngine {
        override fun runChunkProbStress(channels: Array<FloatArray>): Double = probs.removeFirst()
        override fun close() {}
    }

    private fun calibratedPipeline(engine: InferenceEngine): StressPipeline {
        val p = StressPipeline(engine)
        val n = 7500
        p.calibrate(DoubleArray(n) { i -> 1.0 + 0.001 * i },
                    DoubleArray(n) { 5.0 },
                    DoubleArray(n) { 9.8 })
        return p
    }

    private fun zeroBuffer(): Triple<DoubleArray, DoubleArray, DoubleArray> =
        Triple(DoubleArray(7500), DoubleArray(7500) { 5.0 }, DoubleArray(7500) { 9.8 })

    @Test fun `processBuffer below threshold does not notify`() {
        val p = calibratedPipeline(ScriptedEngine(ArrayDeque(listOf(0.3))))
        val (ppg, eda, acc) = zeroBuffer()
        val (notify, prob) = p.processBuffer(ppg, eda, acc, currentTimeSec = 300)
        assertFalse(notify); assertEquals(0.3, prob, 1e-12)
        assertFalse(p.isInStressEvent)
    }

    @Test fun `processBuffer above threshold notifies and sets stress event`() {
        val p = calibratedPipeline(ScriptedEngine(ArrayDeque(listOf(0.8))))
        val (ppg, eda, acc) = zeroBuffer()
        val (notify, prob) = p.processBuffer(ppg, eda, acc, currentTimeSec = 300)
        assertTrue(notify); assertEquals(0.8, prob, 1e-12)
        assertTrue(p.isInStressEvent)
        assertEquals(300, p.lastNotificationSec)
    }

    @Test fun `cooldown suppresses second notification within 300s`() {
        val p = calibratedPipeline(ScriptedEngine(ArrayDeque(listOf(0.8, 0.8))))
        val (ppg, eda, acc) = zeroBuffer()
        val (n1, _) = p.processBuffer(ppg, eda, acc, 300)
        val (n2, _) = p.processBuffer(ppg, eda, acc, 400)
        assertTrue(n1); assertFalse(n2)
    }

    @Test fun `motion gate suppresses high-confidence detection`() {
        val p = calibratedPipeline(ScriptedEngine(ArrayDeque(listOf(0.95))))
        val ppg = DoubleArray(7500); val eda = DoubleArray(7500) { 5.0 }
        // Strong motion: acc_global mean > 0.10 after calibration → gate fires.
        val acc = DoubleArray(7500) { 12.0 }  // raw mag well above 9.8 baseline
        val (notify, _) = p.processBuffer(ppg, eda, acc, 300)
        assertFalse("motion gate must suppress", notify)
        assertFalse(p.isInStressEvent)
    }

    @Test fun `processBuffer before calibration returns zero`() {
        val p = StressPipeline(ScriptedEngine(ArrayDeque()))
        val (ppg, eda, acc) = zeroBuffer()
        val (notify, prob) = p.processBuffer(ppg, eda, acc, 100)
        assertFalse(notify); assertEquals(0.0, prob, 1e-12)
    }
}
