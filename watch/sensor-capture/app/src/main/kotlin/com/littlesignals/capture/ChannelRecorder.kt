package com.littlesignals.capture

import com.samsung.android.service.health.tracking.HealthTracker
import com.samsung.android.service.health.tracking.HealthTrackingService
import com.samsung.android.service.health.tracking.data.DataPoint
import com.samsung.android.service.health.tracking.data.HealthTrackerType
import com.samsung.android.service.health.tracking.data.ValueKey
import timber.log.Timber
import java.io.BufferedWriter
import java.io.File

/**
 * One ChannelRecorder per Samsung Health Sensor SDK tracker channel.
 * Subscribes via HealthTracker.setEventListener and writes each DataPoint
 * as a CSV row.
 *
 * Sample-rate facts (Galaxy Watch 8, SDK 1.4.1):
 *   HEART_RATE_CONTINUOUS  ~1 Hz event-driven
 *   PPG_GREEN              ~25 Hz
 *   EDA_CONTINUOUS         ~25 Hz
 *   ACCELEROMETER_CONTINUOUS  ~25-50 Hz
 */
sealed class ChannelRecorder(
    val name: String,
    val type: HealthTrackerType,
) {
    private var writer: BufferedWriter? = null
    private var tracker: HealthTracker? = null

    var sampleCount: Long = 0
        private set

    var firstSampleTsMs: Long? = null
        private set

    var lastSampleTsMs: Long? = null
        private set

    abstract fun header(): String
    abstract fun formatRow(point: DataPoint): String?

    fun start(captureDir: File, service: HealthTrackingService) {
        val file = File(captureDir, "$name.csv")
        writer = file.bufferedWriter().apply {
            write(header())
            newLine()
        }
        tracker = service.getHealthTracker(type).apply {
            setEventListener(object : HealthTracker.TrackerEventListener {
                override fun onDataReceived(list: MutableList<DataPoint>) {
                    list.forEach { dp ->
                        val row = try {
                            formatRow(dp)
                        } catch (t: Throwable) {
                            Timber.e(t, "format error in %s", name)
                            null
                        }
                        if (row != null) {
                            writer?.write(row)
                            writer?.newLine()
                            // Flush eagerly so 1 Hz channels (HR, EDA) survive Activity
                            // death — BufferedWriter's default 8 KB buffer would otherwise
                            // hold ~5 min of HR data before auto-flush.
                            writer?.flush()
                            sampleCount += 1
                            val ts = dp.timestamp
                            if (firstSampleTsMs == null) firstSampleTsMs = ts
                            lastSampleTsMs = ts
                        }
                    }
                }

                override fun onFlushCompleted() {}

                override fun onError(error: HealthTracker.TrackerError) {
                    Timber.e("tracker error in %s: %s", name, error)
                }
            })
        }
    }

    fun stop() {
        try { tracker?.unsetEventListener() } catch (t: Throwable) { Timber.w(t) }
        tracker = null
        writer?.flush()
        writer?.close()
        writer = null
    }

    fun observedHz(): Double? {
        val first = firstSampleTsMs ?: return null
        val last = lastSampleTsMs ?: return null
        if (last <= first || sampleCount < 2) return null
        val seconds = (last - first) / 1000.0
        return if (seconds > 0) sampleCount / seconds else null
    }

    // --- channel implementations ---

    object HeartRate : ChannelRecorder("heart_rate", HealthTrackerType.HEART_RATE_CONTINUOUS) {
        override fun header() = "timestamp_ms,hr_bpm,ibi_ms,hr_status"
        override fun formatRow(point: DataPoint): String {
            val ts = point.timestamp
            val hr = point.getValue(ValueKey.HeartRateSet.HEART_RATE)
            val ibi = point.getValue(ValueKey.HeartRateSet.IBI_LIST)
                ?.joinToString("|") { it.toString() } ?: ""
            val status = point.getValue(ValueKey.HeartRateSet.HEART_RATE_STATUS)
            return "$ts,$hr,$ibi,$status"
        }
    }

    object PpgGreen : ChannelRecorder("ppg_green", HealthTrackerType.PPG_GREEN) {
        override fun header() = "timestamp_ms,ppg_green,status"
        override fun formatRow(point: DataPoint): String {
            val ts = point.timestamp
            val v = point.getValue(ValueKey.PpgGreenSet.PPG_GREEN)
            val status = point.getValue(ValueKey.PpgGreenSet.STATUS)
            return "$ts,$v,$status"
        }
    }

    object Eda : ChannelRecorder("eda", HealthTrackerType.EDA_CONTINUOUS) {
        override fun header() = "timestamp_ms,skin_conductance,status"
        override fun formatRow(point: DataPoint): String {
            val ts = point.timestamp
            val v = point.getValue(ValueKey.EdaSet.SKIN_CONDUCTANCE)
            val status = point.getValue(ValueKey.EdaSet.STATUS)
            return "$ts,$v,$status"
        }
    }

    object Accelerometer : ChannelRecorder(
        "accel",
        HealthTrackerType.ACCELEROMETER_CONTINUOUS,
    ) {
        override fun header() = "timestamp_ms,x,y,z"
        override fun formatRow(point: DataPoint): String {
            val ts = point.timestamp
            val x = point.getValue(ValueKey.AccelerometerSet.ACCELEROMETER_X)
            val y = point.getValue(ValueKey.AccelerometerSet.ACCELEROMETER_Y)
            val z = point.getValue(ValueKey.AccelerometerSet.ACCELEROMETER_Z)
            return "$ts,$x,$y,$z"
        }
    }

    companion object {
        fun all(): List<ChannelRecorder> = listOf(HeartRate, PpgGreen, Eda, Accelerometer)
    }
}
