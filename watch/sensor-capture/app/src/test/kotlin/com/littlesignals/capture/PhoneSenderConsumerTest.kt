package com.littlesignals.capture

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PhoneSenderConsumerTest {

    private class Recorded(val path: String, val body: String)

    private class FakeSender : (String, String) -> Boolean {
        val sent = mutableListOf<Recorded>()
        override fun invoke(path: String, body: String): Boolean {
            sent.add(Recorded(path, body)); return true
        }
    }

    @Test fun `flush emits a batch with all four channels`() {
        val sender = FakeSender()
        val consumer = PhoneSenderConsumer(sender)
        consumer.onSessionStart(startedAtMs = 1_700_000_000_000, durationMs = 60_000)
        consumer.onSample(Channel.HR, Sample.Scalar(1_700_000_000_001, 72.5))
        consumer.onSample(Channel.PPG, Sample.Scalar(1_700_000_000_005, 0.123))
        consumer.onSample(Channel.EDA, Sample.Scalar(1_700_000_000_010, 5.4))
        consumer.onSample(Channel.ACCEL, Sample.Vector(1_700_000_000_020, listOf(0.0, 0.0, 9.8)))

        consumer.flushNow(nowMs = 1_700_000_001_000)

        assertEquals(1, sender.sent.size)
        assertEquals("/biosignals/samples", sender.sent[0].path)
        val obj = JSONObject(sender.sent[0].body)
        assertEquals(1_700_000_000_000, obj.getLong("tStartMs"))
        assertEquals(1, obj.getJSONArray("hr").length())
        assertEquals(1, obj.getJSONArray("ppg").length())
        assertEquals(1, obj.getJSONArray("eda").length())
        assertEquals(1, obj.getJSONArray("accel").length())
        val a0 = obj.getJSONArray("accel").getJSONObject(0)
        assertEquals(1_700_000_000_020, a0.getLong("t"))
        assertEquals(0.0, a0.getDouble("x"), 1e-9)
        assertEquals(9.8, a0.getDouble("z"), 1e-9)
    }

    @Test fun `flush after session end sends end message with reason`() {
        val sender = FakeSender()
        val consumer = PhoneSenderConsumer(sender)
        consumer.onSessionStart(0, -1)
        consumer.onSample(Channel.HR, Sample.Scalar(1, 70.0))
        consumer.onSessionEnd(EndReason.USER_STOPPED, null)

        assertTrue(sender.sent.any { it.path == "/biosignals/end" })
        val end = sender.sent.first { it.path == "/biosignals/end" }
        assertEquals("user_stopped", JSONObject(end.body).getString("reason"))
    }

    @Test fun `flush does not send if buffers empty`() {
        val sender = FakeSender()
        val consumer = PhoneSenderConsumer(sender)
        consumer.onSessionStart(0, -1)
        consumer.flushNow(nowMs = 1000)
        assertTrue(sender.sent.none { it.path == "/biosignals/samples" })
    }
}
