package com.littlesignals.app.capture

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SyntheticSampleSourceTest {
    @Test fun `produces correct sample counts for 1 second of capture`() {
        val source = SyntheticSampleSource(seed = 42L)
        source.advanceTo(toMs = 1_001_000L, fromMs = 1_000_000L)
        assertEquals(1, source.drainHr().size)
        assertEquals(25, source.drainPpg().size)
        assertEquals(25, source.drainEda().size)
        assertEquals(50, source.drainAccel().size)
    }
    @Test fun `hr values stay in plausible range`() {
        val source = SyntheticSampleSource(seed = 42L)
        source.advanceTo(toMs = 60_000L, fromMs = 0L)
        val hrSamples = source.drainHr()
        assertEquals(60, hrSamples.size)
        for (s in hrSamples) assertTrue("HR ${s.value} not in 50-110", s.value in 50.0..110.0)
    }
    @Test fun `accel values are 3-element vectors`() {
        val source = SyntheticSampleSource(seed = 42L)
        source.advanceTo(toMs = 1_000L, fromMs = 0L)
        val accel = source.drainAccel()
        assertTrue(accel.isNotEmpty())
        for (s in accel) assertEquals(3, s.values.size)
    }
}
