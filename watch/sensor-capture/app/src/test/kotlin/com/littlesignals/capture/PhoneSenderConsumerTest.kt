package com.littlesignals.capture

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.json.JSONObject
import org.junit.Assert.assertEquals
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
            scope = backgroundScope,
            flushIntervalMs = 1_000,
            nowMs = { testScheduler.currentTime + 1_700_000_000_000L },
        )
        consumer.start()

        consumer.onPpg(ScalarSample(1_700_000_000_005L, 0.1))
        consumer.onPpg(ScalarSample(1_700_000_000_045L, 0.2))
        advanceTimeBy(1_001)
        runCurrent()

        assertEquals(1, sender.sent.size)
        assertEquals("/biosignals/samples", sender.sent[0].path)
        val obj = JSONObject(sender.sent[0].body)
        assertEquals(2, obj.getJSONArray("ppg").length())
    }

    @Test fun `consumer skips flush when batch is empty`() = runTest {
        val sender = FakeSender()
        val consumer = PhoneSenderConsumer(
            sender = sender,
            scope = backgroundScope,
            flushIntervalMs = 1_000,
            nowMs = { testScheduler.currentTime + 1_700_000_000_000L },
        )
        consumer.start()
        advanceTimeBy(3_001)
        runCurrent()
        assertEquals(0, sender.sent.size)
    }

    @Test fun `stop drains final batch and sends biosignals end`() = runTest {
        val sender = FakeSender()
        val consumer = PhoneSenderConsumer(
            sender = sender,
            scope = backgroundScope,
            flushIntervalMs = 10_000,
            nowMs = { testScheduler.currentTime + 1_700_000_000_000L },
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
            scope = backgroundScope,
            flushIntervalMs = 10_000,
            nowMs = { testScheduler.currentTime + 1_700_000_000_000L },
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
            scope = backgroundScope,
            flushIntervalMs = 10_000,
            nowMs = { testScheduler.currentTime + 1_700_000_000_000L },
        )
        consumer.start()
        consumer.stop(reason = "sdk_error", error = "tracker_unavailable")
        assertEquals(1, sender.sent.size)
        val end = JSONObject(sender.sent[0].body)
        assertEquals("sdk_error", end.getString("reason"))
        assertEquals("tracker_unavailable", end.getString("error"))
    }

    @Test fun `samples are restored to batch when send returns false`() = runTest {
        // FakeSender that fails for the first biosignals/samples send, then succeeds.
        var failsRemaining = 1
        val sentPaths = mutableListOf<String>()
        val sentBodies = mutableListOf<String>()
        val failThenSucceedSender = object : PhoneSender {
            override suspend fun send(path: String, body: String): Boolean {
                return if (path == "/biosignals/samples" && failsRemaining-- > 0) {
                    false  // simulate phone unreachable
                } else {
                    sentPaths.add(path)
                    sentBodies.add(body)
                    true
                }
            }
        }

        val consumer = PhoneSenderConsumer(
            sender = failThenSucceedSender,
            scope = backgroundScope,
            flushIntervalMs = 1_000,
            nowMs = { testScheduler.currentTime + 1_700_000_000_000L },
        )
        consumer.start()

        // Add 2 HR samples before the first flush (which will fail)
        consumer.onHr(ScalarSample(1_700_000_000_001L, 60.0))
        consumer.onHr(ScalarSample(1_700_000_000_002L, 61.0))
        advanceTimeBy(1_001)  // first flush fires → send returns false → samples restored
        runCurrent()

        // No successful sends yet
        assertEquals(0, sentPaths.size)

        // Add 1 more HR sample — it joins the restored 2 in the batch
        consumer.onHr(ScalarSample(1_700_000_000_003L, 62.0))
        advanceTimeBy(1_001)  // second flush fires → send returns true
        runCurrent()

        // Exactly 1 successful samples send, containing all 3 HR samples
        val sampleSendIndices = sentPaths.indices.filter { sentPaths[it] == "/biosignals/samples" }
        assertEquals(1, sampleSendIndices.size)
        val obj = org.json.JSONObject(sentBodies[sampleSendIndices[0]])
        assertEquals(
            "Restored samples (2) + new sample (1) = 3 total",
            3,
            obj.getJSONArray("hr").length(),
        )
    }
}
