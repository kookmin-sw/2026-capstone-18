package com.littlesignals.app.capture

import java.security.MessageDigest
import java.time.Instant
import kotlinx.coroutines.delay
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject

data class WindowPayload(
    val recordedAtMs: Long,
    val hr: List<ScalarSample>,
    val ppg: List<ScalarSample>,
    val eda: List<ScalarSample>,
    val accel: List<VectorSample>,
)

data class UploadResult(val success: Boolean, val errorCode: String? = null)

private val JSON_MT = "application/json".toMediaType()
private val OCTET_MT = "application/octet-stream".toMediaType()

class WindowUploader(
    private val client: OkHttpClient,
    private val backendBase: String,
    private val accessToken: String,
) {
    suspend fun upload(window: WindowPayload): UploadResult = uploadAttempt(window, attempt = 0)

    private suspend fun uploadAttempt(window: WindowPayload, attempt: Int): UploadResult {
        val blobs = buildBlobs(window)
        val recordedAtIso = Instant.ofEpochMilli(window.recordedAtMs).toString()
        val batchBody = JSONObject().apply {
            put("items", JSONArray().apply {
                for ((signalType, bytes) in blobs) {
                    put(JSONObject().apply {
                        put("signal_type", signalType)
                        put("recorded_at", recordedAtIso)
                        put("byte_size", bytes.size)
                        put("content_hash", "sha256:" + sha256Hex(bytes))
                    })
                }
            })
        }.toString()
        val batchReq = Request.Builder()
            .url("$backendBase/api/v1/sync/biosignals/batch")
            .header("Authorization", "Bearer $accessToken")
            .post(batchBody.toRequestBody(JSON_MT))
            .build()
        val batchResp = runCatching { client.newCall(batchReq).execute() }.getOrNull()
            ?: return retryOrFail(window, attempt, "network_failure")
        batchResp.use { r ->
            if (r.code == 401) return UploadResult(false, "auth_expired")
            if (r.code == 403) return UploadResult(false, "consent_required")
            if (r.code !in 200..299) return retryOrFail(window, attempt, "batch_failed_${r.code}")
            val items = JSONObject(r.body!!.string()).getJSONArray("items")
            for (i in 0 until items.length()) {
                val url = items.getJSONObject(i).getString("presigned_put_url")
                val (_, bytes) = blobs[i]
                val putReq = Request.Builder().url(url)
                    .header("x-amz-server-side-encryption", "AES256")
                    .put(bytes.toRequestBody(OCTET_MT)).build()
                val putResp = runCatching { client.newCall(putReq).execute() }.getOrNull()
                    ?: return UploadResult(false, "s3_put_failed")
                putResp.use { pr ->
                    if (pr.code !in 200..299) return UploadResult(false, "s3_put_${pr.code}")
                }
            }
        }
        return UploadResult(true)
    }

    private suspend fun retryOrFail(window: WindowPayload, attempt: Int, code: String): UploadResult {
        if (attempt >= 1) return UploadResult(false, code)
        delay(5_000)
        return uploadAttempt(window, attempt + 1)
    }

    private fun buildBlobs(window: WindowPayload): List<Pair<String, ByteArray>> = listOf(
        "hrv" to encodeScalar(window.hr),
        "ppg" to encodeScalar(window.ppg),
        "eda" to encodeScalar(window.eda),
        "accel" to encodeVector(window.accel),
    )

    private fun encodeScalar(samples: List<ScalarSample>): ByteArray {
        val arr = JSONArray()
        for (s in samples) arr.put(JSONObject().apply { put("t", s.timestampMs); put("v", s.value) })
        return JSONObject().apply { put("samples", arr) }.toString().toByteArray(Charsets.UTF_8)
    }

    private fun encodeVector(samples: List<VectorSample>): ByteArray {
        val arr = JSONArray()
        for (s in samples) {
            arr.put(JSONObject().apply {
                put("t", s.timestampMs)
                put("v", JSONArray().apply { for (v in s.values) put(v) })
            })
        }
        return JSONObject().apply { put("samples", arr) }.toString().toByteArray(Charsets.UTF_8)
    }

    private fun sha256Hex(bytes: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(bytes)
        return digest.joinToString("") { "%02x".format(it) }
    }
}
