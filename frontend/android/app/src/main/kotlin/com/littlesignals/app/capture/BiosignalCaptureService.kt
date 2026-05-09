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
                startForeground(NOTIFICATION_ID, buildNotification(0))
                startCapture(durationSec, token, backendBase)
            }
            ACTION_STOP -> stopCapture()
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    private fun startCapture(durationSec: Int, accessToken: String, backendBase: String) {
        captureJob?.cancel()
        captureJob = scope.launch {
            val source = SyntheticSampleSource()
            val client = OkHttpClient()
            val uploader = WindowUploader(client, backendBase, accessToken)
            val startedAtMs = System.currentTimeMillis()
            var windowsUploaded = 0
            var lastWindowStart = startedAtMs

            CaptureChannels.emit(state = "capturing", elapsedSec = 0, windowsUploaded = 0)

            while (true) {
                delay(1_000)
                val nowMs = System.currentTimeMillis()
                val elapsedSec = ((nowMs - startedAtMs) / 1000L).toInt()

                source.advanceTo(toMs = nowMs, fromMs = lastWindowStart + (windowsUploaded * 60_000L))

                updateNotification(elapsedSec)
                CaptureChannels.emit(state = "capturing", elapsedSec = elapsedSec, windowsUploaded = windowsUploaded)

                if (nowMs - lastWindowStart >= 60_000L) {
                    val window = WindowPayload(
                        recordedAtMs = lastWindowStart,
                        hr = source.drainHr(),
                        ppg = source.drainPpg(),
                        eda = source.drainEda(),
                        accel = source.drainAccel(),
                    )
                    val result = uploader.upload(window)
                    if (result.success) {
                        windowsUploaded++
                    } else if (result.errorCode == "auth_expired" || result.errorCode == "consent_required") {
                        CaptureChannels.emit(state = "error", error = result.errorCode)
                        stopForegroundCompat(); stopSelf(); return@launch
                    } else {
                        CaptureChannels.emit(
                            state = "capturing", elapsedSec = elapsedSec,
                            windowsUploaded = windowsUploaded, error = result.errorCode,
                        )
                    }
                    lastWindowStart = nowMs
                }

                if (durationSec > 0 && elapsedSec >= durationSec) {
                    CaptureChannels.emit(state = "done", elapsedSec = elapsedSec, windowsUploaded = windowsUploaded)
                    stopForegroundCompat(); stopSelf(); return@launch
                }
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
            .setContentTitle("LittleSignals")
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
