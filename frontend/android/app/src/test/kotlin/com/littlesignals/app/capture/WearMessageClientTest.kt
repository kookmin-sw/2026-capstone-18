package com.littlesignals.app.capture

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WearMessageClientTest {

    @Test fun `connectedNodeId returns first id from supplier`() {
        val client = WearMessageClient(
            nodesSupplier = { listOf("node-a", "node-b") },
            sender = { _, _, _ -> true },
        )
        assertEquals("node-a", client.connectedNodeId())
    }

    @Test fun `connectedNodeId returns null on empty`() {
        val client = WearMessageClient(
            nodesSupplier = { emptyList() },
            sender = { _, _, _ -> true },
        )
        assertNull(client.connectedNodeId())
    }

    @Test fun `send returns false when no node`() {
        val client = WearMessageClient(
            nodesSupplier = { emptyList() },
            sender = { _, _, _ -> true },
        )
        assertEquals(false, client.send("/x", "{}"))
    }

    @Test fun `send forwards path and body to sender`() {
        var captured: Triple<String, String, ByteArray>? = null
        val client = WearMessageClient(
            nodesSupplier = { listOf("node-a") },
            sender = { node, path, bytes ->
                captured = Triple(node, path, bytes); true
            },
        )
        assertTrue(client.send("/biosignals/start", """{"durationSec":600}"""))
        assertEquals("node-a", captured!!.first)
        assertEquals("/biosignals/start", captured!!.second)
        assertEquals("""{"durationSec":600}""", String(captured!!.third, Charsets.UTF_8))
    }
}
