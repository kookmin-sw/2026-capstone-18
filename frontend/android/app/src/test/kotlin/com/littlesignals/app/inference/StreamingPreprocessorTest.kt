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
}
