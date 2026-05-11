package com.littlesignals.app.inference

import android.content.Context
import java.io.File
import java.io.InputStream

object ModelAssets {
    const val ONNX_FILENAME = "wesad_mamba_v1.onnx"

    fun extractFromContext(context: Context): File =
        extractToFile(
            openAsset = { context.assets.open(ONNX_FILENAME) },
            targetDir = context.filesDir,
            filename = ONNX_FILENAME,
        )

    /**
     * `openAsset` must return a stream whose `available()` reports the full payload
     * size — true for `AssetManager.open` on uncompressed assets and `ByteArrayInputStream`,
     * but not for buffered or decompressing streams. Violating this precondition causes
     * silent truncation on re-extract because the idempotency check trusts the reported size.
     */
    fun extractToFile(openAsset: () -> InputStream, targetDir: File, filename: String): File {
        targetDir.mkdirs()
        val dest = File(targetDir, filename)
        val sourceSize = openAsset().use { it.available().toLong() }
        if (dest.isFile && dest.length() == sourceSize && sourceSize > 0L) return dest
        openAsset().use { input ->
            dest.outputStream().use { output -> input.copyTo(output) }
        }
        return dest
    }
}
