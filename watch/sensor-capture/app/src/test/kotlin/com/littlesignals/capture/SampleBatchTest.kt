package com.littlesignals.capture

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SampleBatchTest {

    @Test fun `serializeBatchPayload produces phone-compatible JSON shape`() {
        val drain = SampleBatch.Drain(
            hr = listOf(ScalarSample(1700000000_001L, 72.5)),
            ppg = listOf(ScalarSample(1700000000_005L, 0.123), ScalarSample(1700000000_045L, 0.124)),
            eda = listOf(ScalarSample(1700000000_010L, 5.4)),
            accel = listOf(AccelSample(1700000000_020L, 0.0, 0.0, 9.8)),
        )
        val json = serializeBatchPayload(tStartMs = 1700000000_000L, drain = drain)
        val obj = JSONObject(json)
        assertEquals(1700000000_000L, obj.getLong("tStartMs"))

        val hr = obj.getJSONArray("hr")
        assertEquals(1, hr.length())
        assertEquals(1700000000_001L, hr.getJSONObject(0).getLong("t"))
        assertEquals(72.5, hr.getJSONObject(0).getDouble("v"), 1e-12)

        val ppg = obj.getJSONArray("ppg")
        assertEquals(2, ppg.length())
        assertEquals(0.123, ppg.getJSONObject(0).getDouble("v"), 1e-12)
        assertEquals(0.124, ppg.getJSONObject(1).getDouble("v"), 1e-12)

        val accel = obj.getJSONArray("accel")
        assertEquals(1, accel.length())
        assertEquals(0.0, accel.getJSONObject(0).getDouble("x"), 1e-12)
        assertEquals(0.0, accel.getJSONObject(0).getDouble("y"), 1e-12)
        assertEquals(9.8, accel.getJSONObject(0).getDouble("z"), 1e-12)
    }

    @Test fun `serializeBatchPayload includes empty arrays for missing channels`() {
        val drain = SampleBatch.Drain(
            hr = emptyList(),
            ppg = listOf(ScalarSample(1L, 0.5)),
            eda = emptyList(),
            accel = emptyList(),
        )
        val json = serializeBatchPayload(tStartMs = 0L, drain = drain)
        val obj = JSONObject(json)
        assertEquals(0, obj.getJSONArray("hr").length())
        assertEquals(1, obj.getJSONArray("ppg").length())
        assertEquals(0, obj.getJSONArray("eda").length())
        assertEquals(0, obj.getJSONArray("accel").length())
    }

    @Test fun `SampleBatch drain returns and clears in one atomic step`() {
        val batch = SampleBatch()
        batch.addPpg(ScalarSample(1L, 0.1))
        batch.addPpg(ScalarSample(2L, 0.2))
        assertTrue("not empty before drain", !batch.isEmpty())
        val drain1 = batch.drain()
        assertEquals(2, drain1.ppg.size)
        assertTrue("empty after drain", batch.isEmpty())
        val drain2 = batch.drain()
        assertEquals(0, drain2.ppg.size)
    }
}
