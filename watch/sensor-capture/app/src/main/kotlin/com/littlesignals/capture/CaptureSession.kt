package com.littlesignals.capture

import android.content.Context
import android.os.Build
import com.samsung.android.service.health.tracking.ConnectionListener
import com.samsung.android.service.health.tracking.HealthTrackerException
import com.samsung.android.service.health.tracking.HealthTrackingService
import kotlinx.coroutines.CancellableContinuation
import kotlinx.coroutines.suspendCancellableCoroutine
import org.json.JSONObject
import timber.log.Timber
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.atomic.AtomicBoolean
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * Drives the four channel recorders, packs the result as a ZIP.
 *
 * Output layout (under filesDir/captures/<isoStartTs>/):
 *   heart_rate.csv
 *   ppg_green.csv
 *   eda.csv
 *   accel.csv
 *   metadata.json
 * After completion, a sibling <isoStartTs>.zip is written next to the directory.
 */
class CaptureSession(private val ctx: Context) {

    suspend fun run(
        durationMs: Long,
        onProgress: (remainingSec: Int) -> Unit,
    ): File {
        val startMs = System.currentTimeMillis()
        val captureDir = createCaptureDir(startMs)

        val service = connectService()
        val recorders = ChannelRecorder.all()
        try {
            recorders.forEach { it.start(captureDir, service) }
            countdown(durationMs, onProgress)
        } finally {
            recorders.forEach {
                try { it.stop() } catch (t: Throwable) { Timber.w(t) }
            }
            try { service.disconnectService() } catch (t: Throwable) { Timber.w(t) }
        }

        val endMs = System.currentTimeMillis()
        writeMetadata(captureDir, startMs, endMs, recorders)
        return zipDirectory(captureDir)
    }

    private fun createCaptureDir(startMs: Long): File {
        val parent = File(ctx.filesDir, "captures").apply { mkdirs() }
        val dir = File(parent, isoUtc(startMs).replace(":", "-")).apply { mkdirs() }
        return dir
    }

    /**
     * Connects to the Samsung Health Tracking Service and resumes ONLY after
     * onConnectionSuccess fires (per Samsung Health support response).
     * Calling getHealthTracker before that callback throws "Client binder is null".
     */
    private suspend fun connectService(): HealthTrackingService =
        suspendCancellableCoroutine { cont: CancellableContinuation<HealthTrackingService> ->
            val resumed = AtomicBoolean(false)
            lateinit var service: HealthTrackingService
            val listener = object : ConnectionListener {
                override fun onConnectionSuccess() {
                    Timber.i("HealthTrackingService connected")
                    if (cont.isActive && resumed.compareAndSet(false, true)) {
                        cont.resume(service)
                    }
                }

                override fun onConnectionEnded() {
                    Timber.w("HealthTrackingService connection ended")
                    if (cont.isActive && resumed.compareAndSet(false, true)) {
                        cont.resumeWithException(
                            IllegalStateException("HealthTrackingService connection ended before success"),
                        )
                    }
                }

                override fun onConnectionFailed(e: HealthTrackerException) {
                    Timber.e(e, "HealthTrackingService connection failed")
                    if (cont.isActive && resumed.compareAndSet(false, true)) {
                        cont.resumeWithException(e)
                    }
                }
            }
            service = HealthTrackingService(listener, ctx)
            service.connectService()
            cont.invokeOnCancellation {
                try { service.disconnectService() } catch (_: Throwable) {}
            }
        }

    private suspend fun countdown(
        durationMs: Long,
        onProgress: (Int) -> Unit,
    ) {
        val deadline = System.currentTimeMillis() + durationMs
        while (true) {
            val remaining = ((deadline - System.currentTimeMillis()) / 1000).toInt()
            if (remaining <= 0) {
                onProgress(0)
                break
            }
            onProgress(remaining)
            kotlinx.coroutines.delay(1000)
        }
    }

    private fun writeMetadata(
        dir: File,
        startMs: Long,
        endMs: Long,
        recorders: List<ChannelRecorder>,
    ) {
        val obj = JSONObject().apply {
            put("start_ts_utc", isoUtc(startMs))
            put("end_ts_utc", isoUtc(endMs))
            put("duration_seconds", (endMs - startMs) / 1000)
            put("watch_model", Build.MODEL)
            put("watch_manufacturer", Build.MANUFACTURER)
            put("os_release", Build.VERSION.RELEASE)
            put("sdk_version", "samsung-health-sensor-1.4.1")
            put("app_version_name", BuildInfo.VERSION_NAME)
            val channels = JSONObject()
            recorders.forEach { r ->
                val ch = JSONObject().apply {
                    put("samples", r.sampleCount)
                    put("first_ts_ms", r.firstSampleTsMs ?: JSONObject.NULL)
                    put("last_ts_ms", r.lastSampleTsMs ?: JSONObject.NULL)
                    put("observed_hz", r.observedHz()?.let { String.format("%.2f", it) } ?: JSONObject.NULL)
                    put("tracker_type", r.type.name)
                }
                channels.put(r.name, ch)
            }
            put("channels", channels)
        }
        File(dir, "metadata.json").writeText(obj.toString(2))
    }

    private fun zipDirectory(dir: File): File {
        val zipFile = File(dir.parentFile, "${dir.name}.zip")
        ZipOutputStream(FileOutputStream(zipFile).buffered()).use { zos ->
            dir.listFiles()?.sortedBy { it.name }?.forEach { f ->
                zos.putNextEntry(ZipEntry(f.name))
                f.inputStream().use { it.copyTo(zos) }
                zos.closeEntry()
            }
        }
        return zipFile
    }

    private fun isoUtc(ms: Long): String {
        val sdf = SimpleDateFormat("yyyy-MM-dd'T'HH-mm-ss'Z'", Locale.US)
        sdf.timeZone = TimeZone.getTimeZone("UTC")
        return sdf.format(Date(ms))
    }
}
