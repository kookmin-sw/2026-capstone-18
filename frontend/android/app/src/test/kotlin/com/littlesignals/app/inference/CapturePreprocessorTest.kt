package com.littlesignals.app.inference

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File

class CapturePreprocessorTest {
    private fun loadSynthetic(): ByteArray {
        val f = File("src/test/resources/synthetic_capture.zip")
        assertTrue("fixture missing — run :app:syncInferenceFixtures", f.isFile)
        return f.readBytes()
    }

    @Test fun `synthetic capture produces equal-length 25Hz arrays`() {
        val synced = CapturePreprocessor.preprocessZip(loadSynthetic())
        assertEquals(synced.ppgSmooth.size, synced.eda.size)
        assertEquals(synced.eda.size, synced.accMag.size)
        // ~360 s × 25 Hz = ~9000 samples (matches python tests: TARGET_HZ * (SYNTHETIC_DURATION_SEC ± a couple seconds))
        assertTrue("len=${synced.ppgSmooth.size}", synced.ppgSmooth.size in 25 * 358..25 * 361)
        assertTrue(synced.durationSeconds in 358.0..361.0)
        for (v in synced.ppgSmooth) assertTrue(v.isFinite())
        for (v in synced.eda) assertTrue(v.isFinite())
        for (v in synced.accMag) assertTrue(v >= 0.0 && v.isFinite())
    }

    @Test fun `rejects zip missing eda csv`() {
        val bad = TestZipBuilder.makeMinimalZipMissing("eda.csv")
        try {
            CapturePreprocessor.preprocessZip(bad)
            fail("expected InferenceError.Preprocess")
        } catch (e: InferenceError.Preprocess) {
            assertNotNull(e.message)
            assertTrue("got: ${e.message}", e.message!!.contains("eda.csv"))
        }
    }

    @Test fun `rejects non-zip bytes`() {
        try {
            CapturePreprocessor.preprocessZip("not a zip".toByteArray())
            fail("expected InferenceError.Preprocess")
        } catch (_: InferenceError.Preprocess) { /* ok */ }
    }
}
