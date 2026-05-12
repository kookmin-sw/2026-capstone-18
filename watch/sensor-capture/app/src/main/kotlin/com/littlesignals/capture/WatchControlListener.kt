package com.littlesignals.capture

import android.content.Intent
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService
import org.json.JSONObject
import timber.log.Timber

class WatchControlListener : WearableListenerService() {
    override fun onMessageReceived(event: MessageEvent) {
        val body = String(event.data, Charsets.UTF_8)
        when (event.path) {
            "/biosignals/start" -> {
                val durationSec = runCatching {
                    if (body.isBlank()) -1 else JSONObject(body).optInt("durationSec", -1)
                }.getOrDefault(-1)
                val intent = Intent(applicationContext, RemoteCaptureService::class.java).apply {
                    action = RemoteCaptureService.ACTION_START
                    putExtra(RemoteCaptureService.EXTRA_DURATION_SEC, durationSec)
                }
                applicationContext.startForegroundService(intent)
            }
            "/biosignals/stop" -> {
                val intent = Intent(applicationContext, RemoteCaptureService::class.java).apply {
                    action = RemoteCaptureService.ACTION_STOP
                }
                applicationContext.startService(intent)
            }
            else -> Timber.i("unhandled wear path: %s", event.path)
        }
    }
}
