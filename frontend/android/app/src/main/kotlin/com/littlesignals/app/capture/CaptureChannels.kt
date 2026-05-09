package com.littlesignals.app.capture

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

private const val METHOD_CHANNEL = "littlesignals/capture"
private const val EVENT_CHANNEL = "littlesignals/capture/status"

object CaptureChannels {
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    fun register(context: Context, engine: FlutterEngine) {
        val appContext = context.applicationContext
        MethodChannel(engine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val durationSec = call.argument<Int>("durationSec") ?: -1
                    val token = call.argument<String>("accessToken")
                    val backendBase = call.argument<String>("backendBase") ?: "https://api-staging.friendlykr.com"
                    val source = call.argument<String>("source") ?: "synthetic"
                    if (token.isNullOrBlank()) {
                        result.error("missing_token", "accessToken is required", null)
                        return@setMethodCallHandler
                    }
                    val intent = Intent(appContext, BiosignalCaptureService::class.java).apply {
                        action = BiosignalCaptureService.ACTION_START
                        putExtra(BiosignalCaptureService.EXTRA_DURATION_SEC, durationSec)
                        putExtra(BiosignalCaptureService.EXTRA_ACCESS_TOKEN, token)
                        putExtra(BiosignalCaptureService.EXTRA_BACKEND_BASE, backendBase)
                        putExtra(BiosignalCaptureService.EXTRA_SOURCE, source)
                    }
                    appContext.startForegroundService(intent)
                    result.success(null)
                }
                "stop" -> {
                    val intent = Intent(appContext, BiosignalCaptureService::class.java).apply {
                        action = BiosignalCaptureService.ACTION_STOP
                    }
                    appContext.startService(intent)
                    result.success(null)
                }
                "isWatchConnected" -> {
                    // Tasks.await blocks; must not run on the main thread.
                    Thread {
                        val client = WearMessageClient.forContext(appContext)
                        val connected = client.connectedNodeId() != null
                        mainHandler.post { result.success(connected) }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(engine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { eventSink = events }
                override fun onCancel(arguments: Any?) { eventSink = null }
            }
        )
    }

    fun emit(state: String, elapsedSec: Int = 0, windowsUploaded: Int = 0, error: String? = null) {
        val event = mapOf(
            "state" to state, "elapsed_sec" to elapsedSec,
            "windows_uploaded" to windowsUploaded, "error" to error,
        )
        mainHandler.post { eventSink?.success(event) }
    }
}
