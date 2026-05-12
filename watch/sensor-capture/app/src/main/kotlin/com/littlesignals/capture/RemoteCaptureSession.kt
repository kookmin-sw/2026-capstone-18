package com.littlesignals.capture

import android.content.Context
import com.samsung.android.service.health.tracking.ConnectionListener
import com.samsung.android.service.health.tracking.HealthTrackerException
import com.samsung.android.service.health.tracking.HealthTrackingService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.suspendCancellableCoroutine
import timber.log.Timber
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * Owns one phone-driven capture session: connects to the Samsung Health Tracking
 * Service, fans samples out into [PhoneSenderConsumer], runs for [durationMs]
 * (or until [stop] is called), then emits `/biosignals/end`.
 *
 * Mirrors the orchestration of [CaptureSession] but routes samples to the phone
 * instead of CSVs. Kept separate so the manual capture flow stays untouched.
 */
class RemoteCaptureSession(
    private val ctx: Context,
    private val sender: PhoneSender,
    private val scope: CoroutineScope,
) {
    private var service: HealthTrackingService? = null
    private val recorders = StreamingRecorder.all()
    private var consumer: PhoneSenderConsumer? = null
    @Volatile private var stopped = false

    suspend fun run(durationMs: Long) {
        if (stopped) return
        val s = connectService()
        service = s
        val c = PhoneSenderConsumer(sender = sender, scope = scope)
        consumer = c
        try {
            recorders.forEach { it.start(s, c) }
            c.start()
            val deadline = System.currentTimeMillis() + durationMs
            while (!stopped && (durationMs <= 0 || System.currentTimeMillis() < deadline)) {
                delay(1_000)
            }
            cleanupAndEnd(reason = if (stopped) "user_stop" else "duration_elapsed", error = null)
        } catch (t: Throwable) {
            Timber.e(t, "remote capture failed")
            cleanupAndEnd(reason = "sdk_error", error = t.message ?: t::class.simpleName)
        }
    }

    fun stop() { stopped = true }

    private suspend fun cleanupAndEnd(reason: String, error: String?) {
        recorders.forEach {
            try { it.stop() } catch (t: Throwable) { Timber.w(t) }
        }
        try { consumer?.stop(reason = reason, error = error) } catch (t: Throwable) { Timber.w(t) }
        try { service?.disconnectService() } catch (t: Throwable) { Timber.w(t) }
        consumer = null
        service = null
    }

    /** Identical to [CaptureSession.connectService] — same Samsung SDK quirk. */
    private suspend fun connectService(): HealthTrackingService =
        suspendCancellableCoroutine { cont ->
            val resumed = AtomicBoolean(false)
            lateinit var svc: HealthTrackingService
            val listener = object : ConnectionListener {
                override fun onConnectionSuccess() {
                    if (cont.isActive && resumed.compareAndSet(false, true)) cont.resume(svc)
                }
                override fun onConnectionEnded() {
                    if (cont.isActive && resumed.compareAndSet(false, true)) {
                        cont.resumeWithException(IllegalStateException("HealthTrackingService connection ended before success"))
                    }
                }
                override fun onConnectionFailed(e: HealthTrackerException) {
                    if (cont.isActive && resumed.compareAndSet(false, true)) cont.resumeWithException(e)
                }
            }
            svc = HealthTrackingService(listener, ctx)
            svc.connectService()
            cont.invokeOnCancellation {
                try { svc.disconnectService() } catch (_: Throwable) {}
            }
        }
}
