package com.littlesignals.app.capture

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import com.littlesignals.app.MainActivity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import okhttp3.OkHttpClient

class BiosignalCaptureService : Service() {
    companion object {
        const val ACTION_START = "com.littlesignals.app.capture.START"
        const val ACTION_STOP = "com.littlesignals.app.capture.STOP"
        const val EXTRA_DURATION_SEC = "duration_sec"
        const val EXTRA_ACCESS_TOKEN = "access_token"
        const val EXTRA_BACKEND_BASE = "backend_base"
        const val EXTRA_SOURCE = "source"  // "watch" or "synthetic"
        private const val NOTIFICATION_ID = 1042
        private const val CHANNEL_ID = "biosignal_capture"
    }

    private var captureJob: Job? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val durationSec = intent.getIntExtra(EXTRA_DURATION_SEC, -1)
                val token = intent.getStringExtra(EXTRA_ACCESS_TOKEN) ?: run {
                    CaptureChannels.emit(state = "error", error = "missing_token")
                    stopSelf(); return START_NOT_STICKY
                }
                val backendBase = intent.getStringExtra(EXTRA_BACKEND_BASE) ?: "https://api-staging.friendlykr.com"
                val source = intent.getStringExtra(EXTRA_SOURCE) ?: "synthetic"
                startForeground(NOTIFICATION_ID, buildNotification(0))
                startCapture(durationSec, token, backendBase, source)
            }
            ACTION_STOP -> stopCapture()
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    private fun startCapture(durationSec: Int, accessToken: String, backendBase: String, source: String) {
        captureJob?.cancel()

        val wear = WearMessageClient.forContext(applicationContext)

        captureJob = scope.launch {
            // Wear API calls (Tasks.await) must run off the main thread.
            if (source == "watch") {
                val nodeId = wear.connectedNodeId()
                if (nodeId == null) {
                    CaptureChannels.emit(state = "error", error = "watch_not_connected")
                    stopForegroundCompat(); stopSelf(); return@launch
                }
                val ok = wear.send(
                    "/biosignals/start",
                    """{"durationSec":${if (durationSec > 0) durationSec else -1}}""",
                )
                if (!ok) {
                    CaptureChannels.emit(state = "error", error = "watch_send_failed")
                    stopForegroundCompat(); stopSelf(); return@launch
                }
                WatchSourceController.instance.reset()
            }

            val syntheticSource = if (source == "synthetic") SyntheticSampleSource() else null
            val watchSource = if (source == "watch") WatchSourceController.instance else null
            val client = OkHttpClient()
            val eventsClient = EventsClient(client, backendBase, accessToken)

            // Phase 2: streaming inference path.
            val onnxPath = com.littlesignals.app.inference.ModelAssets.extractFromContext(applicationContext).absolutePath
            val engine = com.littlesignals.app.inference.OnnxInferenceEngine.create(onnxPath)
            val preprocessor = com.littlesignals.app.inference.StreamingPreprocessor()
            val coordinator = com.littlesignals.app.inference.StreamingInferenceCoordinator(
                preprocessor,
                engine,
                listener = com.littlesignals.app.inference.DetectionListener { detection ->
                    CaptureChannels.emitDetection(
                        sessionElapsedSec = detection.sessionElapsedSec,
                        detectedAtMs = detection.detectedAtMs,
                        probStress = detection.probStress,
                        state = detection.state,
                        inStressEvent = detection.inStressEvent,
                        shouldNotify = detection.shouldNotify,
                    )
                    if (detection.shouldNotify) {
                        scope.launch { eventsClient.postStressEvent(detection.detectedAtMs, detection.probStress) }
                    }
                },
            )

            val uploader = WindowUploader(client, backendBase, accessToken)
            val windowHr    = mutableListOf<ScalarSample>()
            val windowPpg   = mutableListOf<ScalarSample>()
            val windowEda   = mutableListOf<ScalarSample>()
            val windowAccel = mutableListOf<VectorSample>()

            val startedAtMs = System.currentTimeMillis()
            var windowRecordedAtMs = startedAtMs
            var windowsUploaded = 0
            var lastWindowStart = startedAtMs

            CaptureChannels.emit(state = "capturing", elapsedSec = 0, windowsUploaded = 0)

            try {
                while (true) {
                    delay(1_000)
                    val nowMs = System.currentTimeMillis()
                    val elapsedSec = ((nowMs - startedAtMs) / 1000L).toInt()

                    syntheticSource?.advanceTo(toMs = nowMs, fromMs = lastWindowStart + (windowsUploaded * 60_000L))

                    updateNotification(elapsedSec)
                    CaptureChannels.emit(state = "capturing", elapsedSec = elapsedSec, windowsUploaded = windowsUploaded)

                    // Drain samples every second so streaming inference can keep up.
                    val drainedHr    = syntheticSource?.drainHr()    ?: watchSource?.drainHr()    ?: emptyList()
                    val drainedPpg   = syntheticSource?.drainPpg()   ?: watchSource?.drainPpg()   ?: emptyList()
                    val drainedEda   = syntheticSource?.drainEda()   ?: watchSource?.drainEda()   ?: emptyList()
                    val drainedAccel = syntheticSource?.drainAccel() ?: watchSource?.drainAccel() ?: emptyList()

                    // Inference path — unchanged
                    preprocessor.appendBatch(drainedPpg, drainedEda, drainedAccel)
                    coordinator.tick(currentMs = nowMs)

                    // Window accumulation for S3 upload
                    windowHr.addAll(drainedHr)
                    windowPpg.addAll(drainedPpg)
                    windowEda.addAll(drainedEda)
                    windowAccel.addAll(drainedAccel)

                    if (watchSource != null) {
                        val sinceLast = nowMs - watchSource.lastSampleAtMs
                        if (watchSource.lastSampleAtMs > 0 && sinceLast > 5_000) {
                            CaptureChannels.emit(state = "error", error = "watch_disconnected")
                            wear.send("/biosignals/stop", "{}")
                            stopForegroundCompat(); stopSelf(); return@launch
                        }
                    }

                    if (nowMs - lastWindowStart >= 60_000L) {
                        val payload = WindowPayload(
                            recordedAtMs = windowRecordedAtMs,
                            hr    = windowHr.toList(),
                            ppg   = windowPpg.toList(),
                            eda   = windowEda.toList(),
                            accel = windowAccel.toList(),
                        )
                        windowHr.clear(); windowPpg.clear(); windowEda.clear(); windowAccel.clear()
                        windowRecordedAtMs = nowMs
                        windowsUploaded += 1
                        lastWindowStart = nowMs
                        scope.launch {
                            val result = uploader.upload(payload)
                            if (!result.success) {
                                CaptureChannels.emit(state = "capturing", elapsedSec = elapsedSec,
                                    windowsUploaded = windowsUploaded, error = "upload_warn_${result.errorCode}")
                            }
                        }
                    }

                    if (durationSec > 0 && elapsedSec >= durationSec) {
                        CaptureChannels.emit(state = "done", elapsedSec = elapsedSec, windowsUploaded = windowsUploaded)
                        if (source == "watch") wear.send("/biosignals/stop", "{}")
                        stopForegroundCompat(); stopSelf(); return@launch
                    }
                }
            } finally {
                engine.close()
            }
        }
    }

    private fun stopCapture() {
        captureJob?.cancel()
        CaptureChannels.emit(state = "done")
        stopForegroundCompat()
        stopSelf()
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) stopForeground(STOP_FOREGROUND_REMOVE)
        else @Suppress("DEPRECATION") stopForeground(true)
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(CHANNEL_ID, "Biosignal capture", NotificationManager.IMPORTANCE_LOW)
                        .apply { description = "Foreground capture session" }
                )
            }
        }
    }

    private fun buildNotification(elapsedSec: Int): Notification {
        ensureNotificationChannel()
        val mm = elapsedSec / 60
        val ss = elapsedSec % 60
        val text = "Capturing — %02d:%02d".format(mm, ss)
        val tapIntent = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE,
        )
        val stopIntent = PendingIntent.getService(
            this, 1,
            Intent(this, BiosignalCaptureService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Luma")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_menu_recent_history)
            .setOngoing(true)
            .setContentIntent(tapIntent)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop", stopIntent)
            .build()
    }

    private fun updateNotification(elapsedSec: Int) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIFICATION_ID, buildNotification(elapsedSec))
    }
}
