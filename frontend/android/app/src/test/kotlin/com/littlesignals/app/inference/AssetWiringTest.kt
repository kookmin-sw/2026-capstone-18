package com.littlesignals.app.inference

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class AssetWiringTest {
    @Test fun `ONNX model asset is bundled at expected path`() {
        // Resolved via the gradle Android asset directory at test time
        val asset = File("src/main/assets/wesad_mamba_v1.onnx")
        assertTrue("ONNX asset must exist at ${asset.absolutePath}", asset.isFile)
        assertTrue("ONNX asset must be > 100 KB", asset.length() > 100_000L)
    }

    @Test fun `synthetic capture fixture is available to JVM tests`() {
        val fixture = File("src/test/resources/synthetic_capture.zip")
        assertTrue("synthetic_capture.zip must exist", fixture.isFile)
    }

    @Test fun `onnxruntime android dependency is on the test classpath`() {
        val cls = Class.forName("ai.onnxruntime.OrtEnvironment")
        assertTrue(cls.name == "ai.onnxruntime.OrtEnvironment")
    }
}
