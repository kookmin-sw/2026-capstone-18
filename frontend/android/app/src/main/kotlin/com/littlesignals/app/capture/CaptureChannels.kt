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
private const val DETECTION_CHANNEL = "littlesignals/capture/detections"

object CaptureChannels {
    private var statusSink: EventChannel.EventSink? = null
    private var detectionSink: EventChannel.EventSink? = null
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
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { statusSink = events }
                override fun onCancel(arguments: Any?) { statusSink = null }
            }
        )
        EventChannel(engine.dartExecutor.binaryMessenger, DETECTION_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { detectionSink = events }
                override fun onCancel(arguments: Any?) { detectionSink = null }
            }
        )
    }

    fun emit(state: String, elapsedSec: Int = 0, windowsUploaded: Int = 0, error: String? = null) {
        val event = mapOf(
            "state" to state, "elapsed_sec" to elapsedSec,
            "windows_uploaded" to windowsUploaded, "error" to error,
        )
        mainHandler.post { statusSink?.success(event) }
    }

    fun emitDetection(
        sessionElapsedSec: Int,
        detectedAtMs: Long,
        probStress: Double,
        state: String,
        inStressEvent: Boolean,
        shouldNotify: Boolean,
    ) {
        val event = mapOf(
            "session_elapsed_sec" to sessionElapsedSec,
            "detected_at_ms" to detectedAtMs,
            "prob_stress" to probStress,
            "state" to state,
            "in_stress_event" to inStressEvent,
            "should_notify" to shouldNotify,
        )
        mainHandler.post { detectionSink?.success(event) }
    }
}
