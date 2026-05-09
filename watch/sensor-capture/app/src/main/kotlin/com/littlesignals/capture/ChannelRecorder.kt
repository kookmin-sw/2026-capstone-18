package com.littlesignals.capture

import com.samsung.android.service.health.tracking.HealthTracker
import com.samsung.android.service.health.tracking.HealthTrackingService
import com.samsung.android.service.health.tracking.data.DataPoint
import com.samsung.android.service.health.tracking.data.HealthTrackerType
import com.samsung.android.service.health.tracking.data.ValueKey
import timber.log.Timber

sealed class ChannelRecorder(
    val channel: Channel,
    val type: HealthTrackerType,
) {
    private var tracker: HealthTracker? = null

    var sampleCount: Long = 0
        private set

    var firstSampleTsMs: Long? = null
        private set

    var lastSampleTsMs: Long? = null
        private set

    abstract fun toSample(point: DataPoint): Sample?

    fun start(service: HealthTrackingService) {
        tracker = service.getHealthTracker(type).apply {
            setEventListener(object : HealthTracker.TrackerEventListener {
                override fun onDataReceived(list: MutableList<DataPoint>) {
                    list.forEach { dp ->
                        val sample = try {
                            toSample(dp)
                        } catch (t: Throwable) {
                            Timber.e(t, "toSample error in %s", channel)
                            null
                        }
                        if (sample != null) {
                            CaptureBus.publishSample(channel, sample)
                            sampleCount += 1
                            val ts = sample.timestampMs
                            if (firstSampleTsMs == null) firstSampleTsMs = ts
                            lastSampleTsMs = ts
                        }
                    }
                }
                override fun onFlushCompleted() {}
                override fun onError(error: HealthTracker.TrackerError) {
                    Timber.e("tracker error in %s: %s", channel, error)
                }
            })
        }
    }

    fun stop() {
        try { tracker?.unsetEventListener() } catch (t: Throwable) { Timber.w(t) }
        tracker = null
    }

    fun observedHz(): Double? {
        val first = firstSampleTsMs ?: return null
        val last = lastSampleTsMs ?: return null
        if (last <= first || sampleCount < 2) return null
        val seconds = (last - first) / 1000.0
        return if (seconds > 0) sampleCount / seconds else null
    }

    object HeartRate : ChannelRecorder(Channel.HR, HealthTrackerType.HEART_RATE_CONTINUOUS) {
        override fun toSample(point: DataPoint): Sample {
            val hr = point.getValue(ValueKey.HeartRateSet.HEART_RATE).toDouble()
            return Sample.Scalar(point.timestamp, hr)
        }
    }
    object PpgGreen : ChannelRecorder(Channel.PPG, HealthTrackerType.PPG_GREEN) {
        override fun toSample(point: DataPoint): Sample {
            val v = point.getValue(ValueKey.PpgGreenSet.PPG_GREEN).toDouble()
            return Sample.Scalar(point.timestamp, v)
        }
    }
    object Eda : ChannelRecorder(Channel.EDA, HealthTrackerType.EDA_CONTINUOUS) {
        override fun toSample(point: DataPoint): Sample {
            val v = point.getValue(ValueKey.EdaSet.SKIN_CONDUCTANCE).toDouble()
            return Sample.Scalar(point.timestamp, v)
        }
    }
    object Accelerometer : ChannelRecorder(Channel.ACCEL, HealthTrackerType.ACCELEROMETER_CONTINUOUS) {
        override fun toSample(point: DataPoint): Sample {
            val x = point.getValue(ValueKey.AccelerometerSet.ACCELEROMETER_X).toDouble()
            val y = point.getValue(ValueKey.AccelerometerSet.ACCELEROMETER_Y).toDouble()
            val z = point.getValue(ValueKey.AccelerometerSet.ACCELEROMETER_Z).toDouble()
            return Sample.Vector(point.timestamp, listOf(x, y, z))
        }
    }

    companion object { fun all(): List<ChannelRecorder> = listOf(HeartRate, PpgGreen, Eda, Accelerometer) }
}
