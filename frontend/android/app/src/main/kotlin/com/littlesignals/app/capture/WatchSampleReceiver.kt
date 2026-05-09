package com.littlesignals.app.capture

import android.util.Log
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService
import org.json.JSONObject

class WatchSampleReceiver : WearableListenerService() {
    override fun onMessageReceived(event: MessageEvent) {
        val body = String(event.data, Charsets.UTF_8)
        when (event.path) {
            "/biosignals/samples" -> {
                runCatching { WatchSourceController.instance.acceptBatch(body) }
                    .onFailure { Log.w("WatchSampleReceiver", "failed to parse /biosignals/samples", it) }
            }
            "/biosignals/end" -> {
                runCatching {
                    val obj = JSONObject(body)
                    WatchSourceController.instance.acceptEnd(
                        obj.getString("reason"),
                        if (obj.isNull("error")) null else obj.getString("error"),
                    )
                }.onFailure { Log.w("WatchSampleReceiver", "failed to parse /biosignals/end", it) }
            }
            else -> Log.i("WatchSampleReceiver", "unhandled wear path: ${event.path}")
        }
    }
}
