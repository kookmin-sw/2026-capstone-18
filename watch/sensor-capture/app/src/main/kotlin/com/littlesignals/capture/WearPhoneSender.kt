package com.littlesignals.capture

import android.content.Context
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.Wearable
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import timber.log.Timber

/**
 * Production [PhoneSender] using the Wear Data Layer MessageClient.
 * Picks the first connected phone node and sends synchronously (via [Tasks.await]).
 * All IO runs on [Dispatchers.IO] because Tasks.await blocks.
 */
class WearPhoneSender(context: Context) : PhoneSender {
    private val appContext = context.applicationContext
    private val nodeClient = Wearable.getNodeClient(appContext)
    private val messageClient = Wearable.getMessageClient(appContext)

    override suspend fun send(path: String, body: String): Boolean = withContext(Dispatchers.IO) {
        try {
            val nodes = Tasks.await(nodeClient.connectedNodes)
            val node = nodes.firstOrNull()
            if (node == null) {
                Timber.w("no connected phone node — dropping %s (%d bytes)", path, body.length)
                return@withContext false
            }
            Tasks.await(messageClient.sendMessage(node.id, path, body.toByteArray(Charsets.UTF_8)))
            true
        } catch (t: Throwable) {
            Timber.w(t, "send failed for %s", path)
            false
        }
    }

    companion object {
        fun forContext(context: Context): WearPhoneSender = WearPhoneSender(context)
    }
}
