package com.littlesignals.capture

import android.content.Context
import com.samsung.android.service.health.tracking.ConnectionListener
import com.samsung.android.service.health.tracking.HealthTrackerException
import com.samsung.android.service.health.tracking.HealthTrackingService
import kotlinx.coroutines.CancellableContinuation
import kotlinx.coroutines.delay
import kotlinx.coroutines.suspendCancellableCoroutine
import timber.log.Timber
import kotlin.coroutines.coroutineContext
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

class CaptureSession(private val ctx: Context) {
    suspend fun run(
        durationMs: Long,
        onProgress: ((elapsedMs: Long) -> Unit)? = null,
    ) {
        val startMs = System.currentTimeMillis()
        CaptureBus.publishStart(startMs, durationMs)

        val service = try {
            connectService()
        } catch (t: Throwable) {
            CaptureBus.publishEnd(EndReason.ERROR, t.message ?: "service_connect_failed")
            throw t
        }

        val recorders = ChannelRecorder.all()
        var endReason = EndReason.COMPLETED
        var endError: String? = null
        try {
            recorders.forEach { it.start(service) }
            tickLoop(durationMs, startMs, onProgress)
        } catch (t: Throwable) {
            endReason = EndReason.ERROR
            endError = t.message
            throw t
        } finally {
            recorders.forEach { runCatching { it.stop() } }
            runCatching { service.disconnectService() }
            CaptureBus.publishEnd(endReason, endError)
        }
    }

    private suspend fun tickLoop(
        durationMs: Long,
        startMs: Long,
        onProgress: ((elapsedMs: Long) -> Unit)?,
    ) {
        while (coroutineContext[kotlinx.coroutines.Job]?.isActive == true) {
            delay(1_000)
            val elapsed = System.currentTimeMillis() - startMs
            onProgress?.invoke(elapsed)
            if (durationMs > 0 && elapsed >= durationMs) return
        }
    }

    private suspend fun connectService(): HealthTrackingService =
        suspendCancellableCoroutine { cont: CancellableContinuation<HealthTrackingService> ->
            val svc = HealthTrackingService(object : ConnectionListener {
                override fun onConnectionSuccess() { Timber.i("HealthTrackingService connected") }
                override fun onConnectionEnded() { Timber.i("HealthTrackingService ended") }
                override fun onConnectionFailed(e: HealthTrackerException) {
                    Timber.e(e, "HealthTrackingService connection failed")
                    if (cont.isActive) cont.resumeWithException(e)
                }
            }, ctx)
            try {
                svc.connectService()
                if (cont.isActive) cont.resume(svc)
            } catch (t: Throwable) {
                if (cont.isActive) cont.resumeWithException(t)
            }
            cont.invokeOnCancellation { runCatching { svc.disconnectService() } }
        }
}
