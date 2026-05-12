package com.littlesignals.app.inference

import com.littlesignals.app.capture.SyntheticSampleSource
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class StreamingIntegrationTest {
    @Test fun `synthetic source drives at least one detection through the streaming pipeline`() {
        val onnxFile = File("src/main/assets/wesad_mamba_v1.onnx")
        assertTrue("ONNX model asset must be present", onnxFile.isFile)
        OnnxInferenceEngine.create(onnxFile.absolutePath).use { engine ->
            val pre = StreamingPreprocessor()
            val detections = mutableListOf<DetectionResult>()
            val coord = StreamingInferenceCoordinator(
                pre,
                engine,
                tickIntervalSec = 60,
                listener = { detections += it },
            )

            // Simulate ~320 s of synthetic capture: drain every second, tick once.
            val source = SyntheticSampleSource(seed = 0L)
            val startMs = 1_700_000_000_000L
            var nowMs = startMs
            var lastDrainMs = startMs
            while (nowMs - startMs <= 320_000L) {
                source.advanceTo(toMs = nowMs, fromMs = lastDrainMs)
                pre.appendBatch(source.drainPpg(), source.drainEda(), source.drainAccel())
                coord.tick(currentMs = nowMs)
                lastDrainMs = nowMs
                nowMs += 1_000L
            }

            assertTrue("expected at least one detection within 320 s of synthetic data", detections.isNotEmpty())
            for (d in detections) {
                assertTrue("probStress must be a probability, got ${d.probStress}", d.probStress in 0.0..1.0)
                assertTrue("state must be valid, got ${d.state}", d.state in setOf("Baseline", "STRESS_EVENT"))
                assertTrue("detectedAtMs should be in range", d.detectedAtMs in startMs..nowMs)
            }
        }
    }
}
