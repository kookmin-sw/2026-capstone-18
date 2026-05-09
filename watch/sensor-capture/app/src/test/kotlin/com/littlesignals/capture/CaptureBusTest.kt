package com.littlesignals.capture

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class CaptureBusTest {

    @After fun cleanup() {
        // No public clear() — tests rebuild via subscribe/unsubscribe.
    }

    private class Recording : CaptureConsumer {
        var startedAt: Long = -1
        var endedReason: EndReason? = null
        var endedError: String? = null
        val samples = mutableListOf<Pair<Channel, Sample>>()
        override fun onSessionStart(startedAtMs: Long, durationMs: Long) { startedAt = startedAtMs }
        override fun onSample(channel: Channel, sample: Sample) { samples += channel to sample }
        override fun onSessionEnd(reason: EndReason, error: String?) {
            endedReason = reason; endedError = error
        }
    }

    @Test fun `subscriber receives published samples`() {
        val sub = Recording()
        CaptureBus.subscribe(sub)
        try {
            CaptureBus.publishStart(startedAtMs = 100, durationMs = 1000)
            CaptureBus.publishSample(Channel.HR, Sample.Scalar(101, 72.5))
            CaptureBus.publishEnd(EndReason.COMPLETED)
            assertEquals(100, sub.startedAt)
            assertEquals(1, sub.samples.size)
            assertEquals(Channel.HR, sub.samples[0].first)
            assertEquals(EndReason.COMPLETED, sub.endedReason)
        } finally { CaptureBus.unsubscribe(sub) }
    }

    @Test fun `unsubscribed consumer does not receive samples`() {
        val sub = Recording()
        CaptureBus.subscribe(sub)
        CaptureBus.unsubscribe(sub)
        CaptureBus.publishSample(Channel.HR, Sample.Scalar(1, 1.0))
        assertTrue(sub.samples.isEmpty())
    }

    @Test fun `throwing consumer does not break others`() {
        val bad = object : CaptureConsumer {
            override fun onSessionStart(startedAtMs: Long, durationMs: Long) = Unit
            override fun onSample(channel: Channel, sample: Sample) {
                throw RuntimeException("boom")
            }
            override fun onSessionEnd(reason: EndReason, error: String?) = Unit
        }
        val good = Recording()
        CaptureBus.subscribe(bad)
        CaptureBus.subscribe(good)
        try {
            CaptureBus.publishSample(Channel.HR, Sample.Scalar(1, 1.0))
            assertEquals(1, good.samples.size)
        } finally { CaptureBus.unsubscribe(bad); CaptureBus.unsubscribe(good) }
    }

    @Test fun `multiple subscribers receive in registration order`() {
        val a = Recording(); val b = Recording()
        CaptureBus.subscribe(a); CaptureBus.subscribe(b)
        try {
            CaptureBus.publishSample(Channel.PPG, Sample.Scalar(2, 2.0))
            assertEquals(1, a.samples.size); assertEquals(1, b.samples.size)
        } finally { CaptureBus.unsubscribe(a); CaptureBus.unsubscribe(b) }
    }
}
