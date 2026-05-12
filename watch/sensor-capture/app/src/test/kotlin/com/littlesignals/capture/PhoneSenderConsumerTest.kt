package com.littlesignals.capture

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runTest
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class PhoneSenderConsumerTest {

    private class FakeSender : PhoneSender {
        data class Sent(val path: String, val body: String)
        val sent = mutableListOf<Sent>()
        override suspend fun send(path: String, body: String): Boolean {
            sent.add(Sent(path, body))
            return true
        }
    }

    @Test fun `consumer flushes accumulated samples every flushIntervalMs`() = runTest {
        val sender = FakeSender()
        val consumer = PhoneSenderConsumer(
            sender = sender,
            scope = TestScope(testScheduler),
            flushIntervalMs = 1_000,
            nowMs = { currentTime + 1_700_000_000_000L },
        )
        consumer.start()

        consumer.onPpg(ScalarSample(1_700_000_000_005L, 0.1))
        consumer.onPpg(ScalarSample(1_700_000_000_045L, 0.2))
        advanceTimeBy(1_001)

        assertEquals(1, sender.sent.size)
        assertEquals("/biosignals/samples", sender.sent[0].path)
        val obj = JSONObject(sender.sent[0].body)
        assertEquals(2, obj.getJSONArray("ppg").length())
    }

    @Test fun `consumer skips flush when batch is empty`() = runTest {
        val sender = FakeSender()
        val consumer = PhoneSenderConsumer(
            sender = sender,
            scope = TestScope(testScheduler),
            flushIntervalMs = 1_000,
            nowMs = { currentTime + 1_700_000_000_000L },
        )
        consumer.start()
        advanceTimeBy(3_001)
        assertEquals(0, sender.sent.size)
    }

    @Test fun `stop drains final batch and sends biosignals end`() = runTest {
        val sender = FakeSender()
        val consumer = PhoneSenderConsumer(
            sender = sender,
            scope = TestScope(testScheduler),
            flushIntervalMs = 10_000,
            nowMs = { currentTime + 1_700_000_000_000L },
        )
        consumer.start()
        consumer.onEda(ScalarSample(1_700_000_000_500L, 5.5))
        consumer.stop(reason = "duration_elapsed", error = null)

        assertEquals(2, sender.sent.size)
        assertEquals("/biosignals/samples", sender.sent[0].path)
        assertEquals(1, JSONObject(sender.sent[0].body).getJSONArray("eda").length())
        assertEquals("/biosignals/end", sender.sent[1].path)
        val end = JSONObject(sender.sent[1].body)
        assertEquals("duration_elapsed", end.getString("reason"))
        assertTrue("null error must serialize as JSON null", end.isNull("error"))
    }

    @Test fun `stop sends only end marker when batch is empty`() = runTest {
        val sender = FakeSender()
        val consumer = PhoneSenderConsumer(
            sender = sender,
            scope = TestScope(testScheduler),
            flushIntervalMs = 10_000,
            nowMs = { currentTime + 1_700_000_000_000L },
        )
        consumer.start()
        consumer.stop(reason = "user_stop", error = null)
        assertEquals(1, sender.sent.size)
        assertEquals("/biosignals/end", sender.sent[0].path)
    }

    @Test fun `stop propagates error string to phone`() = runTest {
        val sender = FakeSender()
        val consumer = PhoneSenderConsumer(
            sender = sender,
            scope = TestScope(testScheduler),
            flushIntervalMs = 10_000,
            nowMs = { currentTime + 1_700_000_000_000L },
        )
        consumer.start()
        consumer.stop(reason = "sdk_error", error = "tracker_unavailable")
        assertEquals(1, sender.sent.size)
        val end = JSONObject(sender.sent[0].body)
        assertEquals("sdk_error", end.getString("reason"))
        assertEquals("tracker_unavailable", end.getString("error"))
    }
}
