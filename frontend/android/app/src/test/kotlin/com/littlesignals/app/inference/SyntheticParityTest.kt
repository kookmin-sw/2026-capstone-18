package com.littlesignals.app.inference

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class SyntheticParityTest {
    @Test fun `synthetic capture produces valid chunks via real ONNX`() {
        val zipFile = File("src/test/resources/synthetic_capture.zip")
        assertTrue("fixture missing", zipFile.isFile)
        val onnxFile = File("src/main/assets/wesad_mamba_v1.onnx")
        assertTrue("model missing", onnxFile.isFile)

        val synced = CapturePreprocessor.preprocessZip(zipFile.readBytes())
        OnnxInferenceEngine.create(onnxFile.absolutePath).use { engine ->
            val results = PipelineRunner.run(synced, engine)
            assertTrue("at least 1 chunk", results.isNotEmpty())
            for (r in results) {
                assertTrue("prob ∈ [0,1] got ${r.probStress}", r.probStress in 0.0..1.0)
                assertTrue("state ${r.state}", r.state in setOf("Baseline", "STRESS_EVENT"))
                assertTrue("label has m/s: ${r.timeLabel}", "m" in r.timeLabel && "s" in r.timeLabel)
            }
        }
    }
}
