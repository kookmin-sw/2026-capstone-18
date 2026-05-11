package com.littlesignals.app.inference

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.File
import java.nio.file.Files

class ModelAssetsTest {
    @Test fun `extractAsset copies asset stream to destination and returns path`() {
        val targetDir = Files.createTempDirectory("modelassets").toFile()
        val payload = "hello-onnx".toByteArray()
        val openAsset = { ByteArrayInputStream(payload) }
        val out = ModelAssets.extractToFile(openAsset, targetDir, "wesad_mamba_v1.onnx")
        assertEquals(File(targetDir, "wesad_mamba_v1.onnx").absolutePath, out.absolutePath)
        assertTrue(out.isFile)
        assertEquals(payload.size.toLong(), out.length())
    }

    @Test fun `extractAsset is idempotent when destination exists with correct size`() {
        val targetDir = Files.createTempDirectory("modelassets").toFile()
        val payload = "hello-onnx".toByteArray()
        ModelAssets.extractToFile({ ByteArrayInputStream(payload) }, targetDir, "wesad_mamba_v1.onnx")
        val mtimeBefore = File(targetDir, "wesad_mamba_v1.onnx").lastModified()
        Thread.sleep(20)
        ModelAssets.extractToFile({ ByteArrayInputStream(payload) }, targetDir, "wesad_mamba_v1.onnx")
        val mtimeAfter = File(targetDir, "wesad_mamba_v1.onnx").lastModified()
        assertEquals("must not rewrite on idempotent extract", mtimeBefore, mtimeAfter)
    }

    @Test fun `extractAsset re-copies when destination size differs`() {
        val targetDir = Files.createTempDirectory("modelassets").toFile()
        ModelAssets.extractToFile({ ByteArrayInputStream("v1".toByteArray()) }, targetDir, "x.onnx")
        ModelAssets.extractToFile({ ByteArrayInputStream("longer-v2".toByteArray()) }, targetDir, "x.onnx")
        assertEquals(9L, File(targetDir, "x.onnx").length())
    }
}
