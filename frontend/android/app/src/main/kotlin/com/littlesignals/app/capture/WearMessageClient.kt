package com.littlesignals.app.capture

import android.content.Context
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.Wearable

class WearMessageClient(
    private val nodesSupplier: () -> List<String>,
    private val sender: (nodeId: String, path: String, body: ByteArray) -> Boolean,
) {
    fun connectedNodeId(): String? = nodesSupplier().firstOrNull()

    fun send(path: String, jsonBody: String): Boolean {
        val node = connectedNodeId() ?: return false
        return sender(node, path, jsonBody.toByteArray(Charsets.UTF_8))
    }

    companion object {
        fun forContext(ctx: Context): WearMessageClient {
            val nodeClient = Wearable.getNodeClient(ctx)
            val msgClient = Wearable.getMessageClient(ctx)
            return WearMessageClient(
                nodesSupplier = {
                    runCatching { Tasks.await(nodeClient.connectedNodes).map { it.id } }
                        .getOrDefault(emptyList())
                },
                sender = { nodeId, path, bytes ->
                    runCatching { Tasks.await(msgClient.sendMessage(nodeId, path, bytes)); true }
                        .getOrDefault(false)
                },
            )
        }
    }
}
