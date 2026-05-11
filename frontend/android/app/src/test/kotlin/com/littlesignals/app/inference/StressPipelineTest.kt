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
