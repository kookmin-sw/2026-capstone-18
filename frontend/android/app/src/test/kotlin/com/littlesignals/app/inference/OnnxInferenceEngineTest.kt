package com.littlesignals.app.inference

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.File

class OnnxInferenceEngineTest {
    private lateinit var engine: OnnxInferenceEngine

    @Before fun setUp() {
        val asset = File("src/main/assets/wesad_mamba_v1.onnx")
        assertTrue("asset present (run :app:syncInferenceAssets)", asset.isFile)
        engine = OnnxInferenceEngine.create(asset.absolutePath)
    }

    @After fun tearDown() { engine.close() }

    @Test fun `runChunk on a deterministic zero tensor returns finite prob`() {
        val tensor = Array(9) { FloatArray(1500) { 0f } }
        val prob = engine.runChunkProbStress(tensor)
        assertTrue("prob must be in [0,1], got $prob", prob in 0.0..1.0)
    }

    @Test fun `runChunk returns same output for same input (determinism)`() {
        val tensor = Array(9) { c -> FloatArray(1500) { i -> ((c + 1) * 0.001f * i) } }
        val a = engine.runChunkProbStress(tensor)
        val b = engine.runChunkProbStress(tensor)
        assertEquals(a, b, 1e-9)
    }
}
