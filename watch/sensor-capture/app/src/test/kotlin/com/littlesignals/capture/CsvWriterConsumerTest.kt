package com.littlesignals.capture

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.util.zip.ZipFile

class CsvWriterConsumerTest {
    @get:Rule val tmp = TemporaryFolder()

    @Test fun `writes per-channel CSVs with headers and rows`() {
        val baseDir = tmp.newFolder("captures")
        val consumer = CsvWriterConsumer(baseDir)
        consumer.onSessionStart(startedAtMs = 1_700_000_000_000, durationMs = 60_000)
        consumer.onSample(Channel.HR, Sample.Scalar(1_700_000_000_000, 72.5))
        consumer.onSample(Channel.HR, Sample.Scalar(1_700_000_001_000, 73.0))
        consumer.onSample(Channel.PPG, Sample.Scalar(1_700_000_000_040, 0.123))
        consumer.onSample(Channel.EDA, Sample.Scalar(1_700_000_000_040, 5.4))
        consumer.onSample(Channel.ACCEL, Sample.Vector(1_700_000_000_020, listOf(0.0, 0.0, 9.8)))
        consumer.onSessionEnd(EndReason.USER_STOPPED)

        val captureDir = baseDir.listFiles()?.firstOrNull { it.isDirectory }
        assertTrue(captureDir != null && captureDir.isDirectory)

        val hr = File(captureDir, "heart_rate.csv").readLines()
        assertEquals("timestamp_ms,value", hr[0])
        assertEquals("1700000000000,72.5", hr[1])
        assertEquals("1700000001000,73.0", hr[2])

        val accel = File(captureDir, "accel.csv").readLines()
        assertEquals("timestamp_ms,x,y,z", accel[0])
        assertEquals("1700000000020,0.0,0.0,9.8", accel[1])
    }

    @Test fun `zips capture directory on COMPLETED end`() {
        val baseDir = tmp.newFolder("captures")
        val consumer = CsvWriterConsumer(baseDir)
        consumer.onSessionStart(startedAtMs = 1_700_000_000_000, durationMs = 1_000)
        consumer.onSample(Channel.HR, Sample.Scalar(1_700_000_000_000, 72.0))
        consumer.onSessionEnd(EndReason.COMPLETED)

        val zip = baseDir.listFiles()?.firstOrNull { it.name.endsWith(".zip") }
        assertTrue("zip created", zip != null)
        ZipFile(zip).use { zf ->
            val names = zf.entries().toList().map { it.name }
            assertTrue(names.any { it.endsWith("heart_rate.csv") })
        }
    }
}
