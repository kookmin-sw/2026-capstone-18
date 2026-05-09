package com.littlesignals.app.capture

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class WatchSourceControllerTest {

    private val sampleBatch = """
        {
          "tStartMs": 1700000000000,
          "hr": [{"t": 1700000000001, "v": 72.5}],
          "ppg": [{"t": 1700000000005, "v": 0.123}, {"t": 1700000000045, "v": 0.124}],
          "eda": [{"t": 1700000000010, "v": 5.4}],
          "accel": [{"t": 1700000000020, "x": 0.0, "y": 0.0, "z": 9.8}]
        }
    """.trimIndent()

    @Test fun `acceptBatch buffers samples and drains return them`() {
        val controller = WatchSourceController()
        controller.acceptBatch(sampleBatch)
        assertEquals(1, controller.drainHr().size)
        assertEquals(2, controller.drainPpg().size)
        assertEquals(1, controller.drainEda().size)
        assertEquals(1, controller.drainAccel().size)
        assertTrue(controller.drainHr().isEmpty())
    }

    @Test fun `acceptEnd records reason`() {
        val controller = WatchSourceController()
        controller.acceptBatch(sampleBatch)
        controller.acceptEnd("user_stopped", null)
        assertEquals("user_stopped", controller.lastEndReason)
    }

    @Test fun `lastSampleAtMs reflects most recent sample`() {
        val controller = WatchSourceController()
        controller.acceptBatch(sampleBatch)
        assertEquals(1700000000045L, controller.lastSampleAtMs)
    }
}
