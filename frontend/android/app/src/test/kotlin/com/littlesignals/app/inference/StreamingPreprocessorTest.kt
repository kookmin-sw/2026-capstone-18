package com.littlesignals.app.inference

import com.littlesignals.app.capture.ScalarSample
import com.littlesignals.app.capture.VectorSample
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class StreamingPreprocessorTest {

    @Test fun `appendBatch buffers samples by channel`() {
        val pre = StreamingPreprocessor()
        val t0 = 1_700_000_000_000L
        pre.appendBatch(
            ppg = listOf(ScalarSample(t0, 1.0), ScalarSample(t0 + 40, 2.0)),
            eda = listOf(ScalarSample(t0, 5.0)),
            accel = listOf(VectorSample(t0, listOf(0.0, 0.0, 9.8))),
        )
        assertEquals(2, pre.ppgSampleCount())
        assertEquals(1, pre.edaSampleCount())
        assertEquals(1, pre.accelSampleCount())
    }

    @Test fun `evicts samples older than 305s from latest`() {
        val pre = StreamingPreprocessor()
        val t0 = 1_700_000_000_000L
        val old = listOf(ScalarSample(t0, 1.0))                           // ts = t0
        val fresh = listOf(ScalarSample(t0 + 310_000L, 2.0))               // ts = t0 + 310s
        pre.appendBatch(ppg = old, eda = emptyList(), accel = emptyList())
        pre.appendBatch(ppg = fresh, eda = emptyList(), accel = emptyList())
        // The old sample is > 305s before the freshest → evicted.
        assertEquals(1, pre.ppgSampleCount())
    }

    @Test fun `snapshot25Hz returns null when not enough samples to fill window`() {
        val pre = StreamingPreprocessor()
        val t0 = 1_700_000_000_000L
        // 100 PPG samples at 25Hz spans only 4 s — far short of 300 s.
        val ppg = (0 until 100).map { i -> ScalarSample(t0 + i * 40L, i.toDouble()) }
        pre.appendBatch(ppg, eda = emptyList(), accel = emptyList())
        assertNull(pre.snapshot25Hz())
    }

    @Test fun `snapshot25Hz produces 7500-sample SyncedSignals from a 300s synthetic stream`() {
        val pre = StreamingPreprocessor()
        val t0 = 1_700_000_000_000L
        // Generate ~305 s of synthetic samples at ~25 Hz each.
        val ppg = mutableListOf<ScalarSample>()
        val eda = mutableListOf<ScalarSample>()
        val accel = mutableListOf<VectorSample>()
        var t = t0
        while (t <= t0 + 305_000L) {
            ppg += ScalarSample(t, kotlin.math.sin(t.toDouble() / 1000.0))
            eda += ScalarSample(t, 5.0)
            accel += VectorSample(t, listOf(0.0, 0.0, 9.8))
            t += 40L  // 25 Hz
        }
        pre.appendBatch(ppg, eda, accel)
        val snap = pre.snapshot25Hz()
        assertTrue("snapshot must be non-null when buffer is full", snap != null)
        assertEquals(7500, snap!!.ppgSmooth.size)
        assertEquals(7500, snap.eda.size)
        assertEquals(7500, snap.accMag.size)
        assertEquals(300.0, snap.durationSeconds, 0.5)
        for (v in snap.ppgSmooth) assertTrue("ppg finite", v.isFinite())
        for (v in snap.eda) assertTrue("eda finite", v.isFinite())
        for (v in snap.accMag) assertTrue("accMag positive + finite", v >= 0.0 && v.isFinite())
    }
}
