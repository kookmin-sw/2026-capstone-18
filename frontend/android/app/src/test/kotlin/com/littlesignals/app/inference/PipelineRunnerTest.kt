package com.littlesignals.app.inference

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class PipelineRunnerTest {
    private class ConstEngine(private val v: Double) : InferenceEngine {
        override fun runChunkProbStress(channels: Array<FloatArray>): Double = v
        override fun close() {}
    }

    @Test fun `rejects recording shorter than 300s buffer`() {
        val n = 25 * 200  // 200s
        val synced = SyncedSignals(DoubleArray(n), DoubleArray(n) { 5.0 }, DoubleArray(n) { 9.8 }, 200.0)
        try {
            PipelineRunner.run(synced, ConstEngine(0.0))
            fail("expected InferenceError.Runner")
        } catch (e: InferenceError.Runner) {
            assertTrue("got: ${e.message}", e.message!!.contains("too short"))
        }
    }

    @Test fun `produces 5 chunks for 10-minute recording`() {
        val n = 25 * 600  // 600s
        val synced = SyncedSignals(DoubleArray(n), DoubleArray(n) { 5.0 }, DoubleArray(n) { 9.8 }, 600.0)
        val results = PipelineRunner.run(synced, ConstEngine(0.1))
        // Python loop: range(BUFFER_STEPS=7500, len=15000, CHUNK_STEPS=1500) → indices 7500, 9000, ..., 13500 → 5 chunks
        assertEquals(5, results.size)
        assertEquals(300, results[0].timeSeconds)
        assertEquals(360, results[1].timeSeconds)
        assertEquals(540, results[4].timeSeconds)
        for (r in results) {
            assertEquals(0.1, r.probStress, 1e-12)
            assertEquals("Baseline", r.state)
            assertTrue(!r.shouldNotify)
        }
    }
}
