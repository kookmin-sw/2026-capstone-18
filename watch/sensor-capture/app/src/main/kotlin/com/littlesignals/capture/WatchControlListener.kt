package com.littlesignals.capture

import android.content.Intent
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService
import org.json.JSONObject
import timber.log.Timber

class WatchControlListener : WearableListenerService() {
    override fun onMessageReceived(event: MessageEvent) {
        when (event.path) {
            "/biosignals/start" -> {
                val body = runCatching { JSONObject(String(event.data, Charsets.UTF_8)) }.getOrNull()
                val durationSec = body?.optInt("durationSec", -1) ?: -1
                val intent = Intent(this, BiosignalCaptureService::class.java).apply {
                    action = BiosignalCaptureService.ACTION_START
                    putExtra(BiosignalCaptureService.EXTRA_DURATION_MS,
                        if (durationSec > 0) durationSec * 1000L else -1L)
                }
                startForegroundService(intent)
            }
            "/biosignals/stop" -> {
                val intent = Intent(this, BiosignalCaptureService::class.java).apply {
                    action = BiosignalCaptureService.ACTION_STOP
                }
                startService(intent)
            }
            else -> Timber.i("unhandled wear path: %s", event.path)
        }
    }
}
