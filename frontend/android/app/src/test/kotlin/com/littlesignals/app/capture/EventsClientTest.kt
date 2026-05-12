package com.littlesignals.app.capture

import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class EventsClientTest {
    private lateinit var server: MockWebServer
    private lateinit var client: EventsClient

    @Before fun setUp() {
        server = MockWebServer()
        server.start()
        client = EventsClient(OkHttpClient(), backendBase = server.url("").toString().trimEnd('/'), accessToken = "tok123")
    }

    @After fun tearDown() { server.shutdown() }

    @Test fun `postStressEvent sends correct payload + auth header on 201`() = runBlocking {
        server.enqueue(MockResponse().setResponseCode(201).setBody("""{"id":"abc"}"""))
        val ok = client.postStressEvent(detectedAtMs = 1_700_000_000_000L, probStress = 0.81)
        assertTrue("expected ok=true on 201", ok)
        val req = server.takeRequest()
        assertEquals("POST", req.method)
        assertEquals("/api/v1/events", req.path)
        assertEquals("Bearer tok123", req.getHeader("Authorization"))
        val body = JSONObject(req.body.readUtf8())
        assertEquals(0.81, body.getDouble("model_confidence"), 1e-9)
        assertTrue("body.notified=true", body.getBoolean("notified"))
        assertTrue("detected_at non-empty", body.getString("detected_at").isNotEmpty())
    }

    @Test fun `postStressEvent returns false on 4xx`() = runBlocking {
        server.enqueue(MockResponse().setResponseCode(401).setBody("{}"))
        val ok = client.postStressEvent(detectedAtMs = 0L, probStress = 0.5)
        assertEquals(false, ok)
    }

    @Test fun `postStressEvent returns false on network failure`() = runBlocking {
        server.shutdown()  // force connection refused
        val ok = client.postStressEvent(detectedAtMs = 0L, probStress = 0.5)
        assertEquals(false, ok)
    }
}
