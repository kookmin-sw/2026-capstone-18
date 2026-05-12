package com.littlesignals.capture

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import timber.log.Timber

class RemoteCaptureService : Service() {

    companion object {
        const val ACTION_START = "com.littlesignals.capture.REMOTE_START"
        const val ACTION_STOP = "com.littlesignals.capture.REMOTE_STOP"
        const val EXTRA_DURATION_SEC = "duration_sec"
        private const val NOTIFICATION_ID = 2042
        private const val CHANNEL_ID = "remote_capture"
    }

    private var session: RemoteCaptureSession? = null
    private var job: Job? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> handleStart(intent.getIntExtra(EXTRA_DURATION_SEC, -1))
            ACTION_STOP -> handleStop()
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    private fun handleStart(durationSec: Int) {
        if (session != null) {
            Timber.w("remote capture already running — ignoring duplicate start")
            return
        }
        startForegroundWithType()
        val sender = WearPhoneSender.forContext(applicationContext)
        val s = RemoteCaptureSession(ctx = applicationContext, sender = sender, scope = scope)
        session = s
        val durMs = if (durationSec > 0) durationSec.toLong() * 1_000L else -1L
        job = scope.launch {
            try {
                s.run(durMs)
            } finally {
                session = null
                stopForegroundCompat()
                stopSelf()
            }
        }
    }

    private fun handleStop() {
        session?.stop()
        // The run() coroutine will see the flag, clean up, and stopSelf() in its finally block.
    }

    private fun startForegroundWithType() {
        ensureNotificationChannel()
        val notif = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("스트레스 측정")
            .setContentText("폰과 연결되어 스트레스를 측정하고 있어요")
            .setSmallIcon(android.R.drawable.ic_menu_recent_history)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notif, ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH)
        } else {
            startForeground(NOTIFICATION_ID, notif)
        }
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
                    NotificationChannel(CHANNEL_ID, "Remote capture", NotificationManager.IMPORTANCE_LOW)
                        .apply { description = "Phone-driven biosignal streaming" }
                )
            }
        }
    }
}
