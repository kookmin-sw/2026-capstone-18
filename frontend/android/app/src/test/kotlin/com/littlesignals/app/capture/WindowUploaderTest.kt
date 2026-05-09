package com.littlesignals.app.capture

import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class WindowUploaderTest {
    private lateinit var server: MockWebServer
    @Before fun setUp() { server = MockWebServer(); server.start() }
    @After fun tearDown() { server.shutdown() }

    @Test fun `uploads four channels per window`() = runBlocking {
        val s3Base = server.url("/s3").toString()
        val batchResponseJson = """
            {"items":[
              {"upload_id":"a","s3_object_key":"k1","presigned_put_url":"$s3Base/hrv","expires_in":3600,"expires_at":"2027-05-10T00:00:00Z"},
              {"upload_id":"b","s3_object_key":"k2","presigned_put_url":"$s3Base/ppg","expires_in":3600,"expires_at":"2027-05-10T00:00:00Z"},
              {"upload_id":"c","s3_object_key":"k3","presigned_put_url":"$s3Base/eda","expires_in":3600,"expires_at":"2027-05-10T00:00:00Z"},
              {"upload_id":"d","s3_object_key":"k4","presigned_put_url":"$s3Base/accel","expires_in":3600,"expires_at":"2027-05-10T00:00:00Z"}
            ]}
        """.trimIndent()
        server.enqueue(MockResponse().setResponseCode(201).setBody(batchResponseJson))
        repeat(4) { server.enqueue(MockResponse().setResponseCode(200)) }
        val uploader = WindowUploader(OkHttpClient(), server.url("").toString().trimEnd('/'), "fake-token")
        val window = WindowPayload(
            recordedAtMs = 1_700_000_000_000L,
            hr = listOf(ScalarSample(1_700_000_000_000L, 72.5)),
            ppg = listOf(ScalarSample(1_700_000_000_000L, 0.1)),
            eda = listOf(ScalarSample(1_700_000_000_000L, 5.0)),
            accel = listOf(VectorSample(1_700_000_000_000L, listOf(0.0, 0.0, 9.8))),
        )
        val result = uploader.upload(window)
        assertTrue(result.success)
        assertEquals(5, server.requestCount)
        val batchReq = server.takeRequest()
        assertEquals("/api/v1/sync/biosignals/batch", batchReq.path)
        assertEquals("Bearer fake-token", batchReq.getHeader("Authorization"))
        for (i in 0 until 4) {
            val putReq = server.takeRequest()
            assertEquals("PUT", putReq.method)
        }
    }

    @Test fun `returns failure on backend 401 without retrying PUT`() = runBlocking {
        server.enqueue(MockResponse().setResponseCode(401).setBody("""{"reason":"unauthorized"}"""))
        val uploader = WindowUploader(OkHttpClient(), server.url("").toString().trimEnd('/'), "expired")
        val window = WindowPayload(0L, emptyList(), emptyList(), emptyList(), emptyList())
        val result = uploader.upload(window)
        assertFalse(result.success)
        assertEquals("auth_expired", result.errorCode)
    }
}
