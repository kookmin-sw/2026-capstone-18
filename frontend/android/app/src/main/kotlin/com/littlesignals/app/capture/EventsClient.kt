package com.littlesignals.app.capture

import java.time.Instant
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject

private val JSON_MT = "application/json".toMediaType()

class EventsClient(
    private val client: OkHttpClient,
    private val backendBase: String,
    private val accessToken: String,
) {
    suspend fun postStressEvent(detectedAtMs: Long, probStress: Double): Boolean {
        val body = JSONObject().apply {
            put("detected_at", Instant.ofEpochMilli(detectedAtMs).toString())
            put("model_confidence", probStress)
            put("notified", true)
        }.toString().toRequestBody(JSON_MT)
        val req = Request.Builder()
            .url("$backendBase/api/v1/events")
            .header("Authorization", "Bearer $accessToken")
            .post(body)
            .build()
        return try {
            client.newCall(req).execute().use { resp -> resp.isSuccessful }
        } catch (_: Exception) {
            false
        }
    }
}
