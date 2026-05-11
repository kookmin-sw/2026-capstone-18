package com.littlesignals.app.inference

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File

class GalaxyParityTest {
    private val expectedProbs = doubleArrayOf(0.441, 0.691, 0.450, 0.289, 0.280)
    private val tolerance = 0.01

    @Test fun `Galaxy_Test capture matches Python reference probs within 0_01`() {
        val zipFile = File("src/test/resources/galaxy_test.zip")
        assumeTrue(
            "galaxy_test.zip not present — run: python3 AI/scripts/build_kotlin_parity_fixture.py " +
                "(requires AI/data/raw/Galaxy_Test/ locally)",
            zipFile.isFile,
        )
        val onnxFile = File("src/main/assets/wesad_mamba_v1.onnx")
        assertTrue("model asset missing", onnxFile.isFile)

        val synced = CapturePreprocessor.preprocessZip(zipFile.readBytes())
        OnnxInferenceEngine.create(onnxFile.absolutePath).use { engine ->
            val results = PipelineRunner.run(synced, engine)
            assertEquals("expected ${expectedProbs.size} chunks", expectedProbs.size, results.size)
            for (i in expectedProbs.indices) {
                val diff = kotlin.math.abs(results[i].probStress - expectedProbs[i])
                assertTrue(
                    "chunk $i: prob ${results[i].probStress} not within $tolerance of ${expectedProbs[i]} (diff=$diff)",
                    diff < tolerance,
                )
                assertEquals("chunk $i state", "Baseline", results[i].state)
                assertFalse("chunk $i shouldNotify", results[i].shouldNotify)
            }
        }
    }
}
