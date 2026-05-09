package com.littlesignals.capture

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
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.File

class BiosignalCaptureService : Service() {

    companion object {
        const val ACTION_START = "com.littlesignals.capture.START"
        const val ACTION_STOP = "com.littlesignals.capture.STOP"
        const val EXTRA_DURATION_MS = "duration_ms"
        private const val NOTIFICATION_ID = 2042
        private const val CHANNEL_ID = "watch_biosignal_capture"
        private const val MAX_DURATION_MS = 90L * 60_000L
    }

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var captureJob: Job? = null
    private var csvConsumer: CsvWriterConsumer? = null
    private var phoneSender: PhoneSenderConsumer? = null
    private var phoneFlushJob: Job? = null

    private val statsConsumer = object : CaptureConsumer {
        override fun onSessionStart(startedAtMs: Long, durationMs: Long) {
            CaptureState.flow.value = CaptureUiState(
                state = State.CAPTURING, elapsedMs = 0L, durationMs = durationMs,
            )
        }
        override fun onSample(channel: Channel, sample: Sample) {
            val s = CaptureState.flow.value
            CaptureState.flow.value = when (channel) {
                Channel.HR -> s.copy(hrCount = s.hrCount + 1)
                Channel.PPG -> s.copy(ppgCount = s.ppgCount + 1)
                Channel.EDA -> s.copy(edaCount = s.edaCount + 1)
                Channel.ACCEL -> s.copy(accelCount = s.accelCount + 1)
            }
        }
        override fun onSessionEnd(reason: EndReason, error: String?) {
            val nextState = if (reason == EndReason.ERROR) State.ERROR else State.DONE
            CaptureState.flow.value = CaptureState.flow.value.copy(state = nextState, error = error)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val rawMs = intent.getLongExtra(EXTRA_DURATION_MS, -1L)
                val durationMs = if (rawMs > 0) rawMs.coerceAtMost(MAX_DURATION_MS) else -1L
                startForeground(NOTIFICATION_ID, buildNotification(0L))
                startCapture(durationMs)
            }
            ACTION_STOP -> stopCapture()
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    private fun startCapture(durationMs: Long) {
        captureJob?.cancel()
        val csv = CsvWriterConsumer(baseDir = File(filesDir, "captures").apply { mkdirs() })
        csvConsumer = csv
        CaptureBus.subscribe(csv)
        CaptureBus.subscribe(statsConsumer)
        val sender = PhoneSenderConsumer { path, body ->
            try {
                val nodeId = com.google.android.gms.tasks.Tasks.await(
                    com.google.android.gms.wearable.Wearable.getNodeClient(this@BiosignalCaptureService).connectedNodes
                ).firstOrNull()?.id ?: return@PhoneSenderConsumer false
                com.google.android.gms.tasks.Tasks.await(
                    com.google.android.gms.wearable.Wearable.getMessageClient(this@BiosignalCaptureService)
                        .sendMessage(nodeId, path, body.toByteArray(Charsets.UTF_8))
                )
                true
            } catch (t: Throwable) {
                false
            }
        }
        phoneSender = sender
        CaptureBus.subscribe(sender)
        phoneFlushJob = scope.launch {
            while (true) {
                delay(1_000)
                sender.flushNow(System.currentTimeMillis())
            }
        }
        captureJob = scope.launch {
            try {
                CaptureSession(this@BiosignalCaptureService).run(durationMs) { elapsed ->
                    CaptureState.flow.value = CaptureState.flow.value.copy(elapsedMs = elapsed)
                    updateNotification(elapsed)
                }
            } catch (_: Throwable) {
                // CaptureSession publishes ERROR on the bus.
            } finally {
                phoneFlushJob?.cancel()
                phoneFlushJob = null
                phoneSender?.let { CaptureBus.unsubscribe(it) }
                phoneSender = null
                csvConsumer?.let { CaptureBus.unsubscribe(it) }
                CaptureBus.unsubscribe(statsConsumer)
                csvConsumer = null
                stopForegroundCompat()
                stopSelf()
            }
        }
    }

    private fun stopCapture() {
        captureJob?.cancel()
        CaptureBus.publishEnd(EndReason.USER_STOPPED, null)
        csvConsumer?.let { CaptureBus.unsubscribe(it) }
        CaptureBus.unsubscribe(statsConsumer)
        phoneFlushJob?.cancel()
        phoneFlushJob = null
        phoneSender?.let { CaptureBus.unsubscribe(it) }
        phoneSender = null
        csvConsumer = null
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
                        .apply { description = "Continuous watch capture" }
                )
            }
        }
    }

    private fun buildNotification(elapsedMs: Long): Notification {
        ensureNotificationChannel()
        val mm = (elapsedMs / 60_000L).toInt()
        val ss = ((elapsedMs / 1000L) % 60L).toInt()
        val text = "캡처 중 — %02d:%02d".format(mm, ss)
        val tapIntent = PendingIntent.getActivity(
            this, 0, Intent(this, CaptureActivity::class.java), PendingIntent.FLAG_IMMUTABLE,
        )
        val stopIntent = PendingIntent.getService(
            this, 1,
            Intent(this, BiosignalCaptureService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("LittleSignals 캡처")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_menu_recent_history)
            .setOngoing(true)
            .setContentIntent(tapIntent)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop", stopIntent)
            .build()
    }

    private fun updateNotification(elapsedMs: Long) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIFICATION_ID, buildNotification(elapsedMs))
    }
}
