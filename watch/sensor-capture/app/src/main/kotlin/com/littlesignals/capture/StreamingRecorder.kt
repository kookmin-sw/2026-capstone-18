package com.littlesignals.capture

import com.samsung.android.service.health.tracking.HealthTracker
import com.samsung.android.service.health.tracking.HealthTrackingService
import com.samsung.android.service.health.tracking.data.DataPoint
import com.samsung.android.service.health.tracking.data.HealthTrackerType
import com.samsung.android.service.health.tracking.data.ValueKey
import timber.log.Timber

/**
 * Subscribes to one Samsung Health Sensor SDK tracker and routes each parsed
 * sample into a [PhoneSenderConsumer]. Mirrors the per-channel parsing in
 * [ChannelRecorder] but skips CSV writing and the [LiveSnapshot] publication.
 *
 * Parallel to ChannelRecorder — keeping them separate avoids touching the
 * stable manual-capture flow.
 */
sealed class StreamingRecorder(val type: HealthTrackerType) {
    private var tracker: HealthTracker? = null

    fun start(service: HealthTrackingService, consumer: PhoneSenderConsumer) {
        tracker = service.getHealthTracker(type).apply {
            setEventListener(object : HealthTracker.TrackerEventListener {
                override fun onDataReceived(list: MutableList<DataPoint>) {
                    list.forEach { dp ->
                        try {
                            route(dp, consumer)
                        } catch (t: Throwable) {
                            Timber.w(t, "parse error in %s", type.name)
                        }
                    }
                }

                override fun onFlushCompleted() = Unit

                override fun onError(error: HealthTracker.TrackerError) {
                    Timber.e("tracker error in %s: %s", type.name, error.name)
                }
            })
        }
    }

    fun stop() {
        try { tracker?.unsetEventListener() } catch (t: Throwable) { Timber.w(t) }
        tracker = null
    }

    protected abstract fun route(dp: DataPoint, consumer: PhoneSenderConsumer)

    class Hr : StreamingRecorder(HealthTrackerType.HEART_RATE_CONTINUOUS) {
        override fun route(dp: DataPoint, consumer: PhoneSenderConsumer) {
            val bpm = (dp.getValue(ValueKey.HeartRateSet.HEART_RATE) ?: return).toDouble()
            consumer.onHr(ScalarSample(dp.timestamp, bpm))
        }
    }

    class PpgGreen : StreamingRecorder(HealthTrackerType.PPG_GREEN) {
        override fun route(dp: DataPoint, consumer: PhoneSenderConsumer) {
            val v = (dp.getValue(ValueKey.PpgGreenSet.PPG_GREEN) ?: return).toDouble()
            consumer.onPpg(ScalarSample(dp.timestamp, v))
        }
    }

    class Eda : StreamingRecorder(HealthTrackerType.EDA_CONTINUOUS) {
        override fun route(dp: DataPoint, consumer: PhoneSenderConsumer) {
            val v = (dp.getValue(ValueKey.EdaSet.SKIN_CONDUCTANCE) ?: return).toDouble()
            consumer.onEda(ScalarSample(dp.timestamp, v))
        }
    }

    class Accel : StreamingRecorder(HealthTrackerType.ACCELEROMETER_CONTINUOUS) {
        override fun route(dp: DataPoint, consumer: PhoneSenderConsumer) {
            val x = (dp.getValue(ValueKey.AccelerometerSet.ACCELEROMETER_X) ?: return).toDouble()
            val y = (dp.getValue(ValueKey.AccelerometerSet.ACCELEROMETER_Y) ?: return).toDouble()
            val z = (dp.getValue(ValueKey.AccelerometerSet.ACCELEROMETER_Z) ?: return).toDouble()
            consumer.onAccel(AccelSample(dp.timestamp, x, y, z))
        }
    }

    companion object {
        fun all(): List<StreamingRecorder> = listOf(Hr(), PpgGreen(), Eda(), Accel())
    }
}
