package com.littlesignals.capture

/**
 * Latest live readings from the four channels, emitted to the UI as a
 * MutableStateFlow<LiveSnapshot> so the capturing screen can render real
 * sensor activity in real time.
 *
 * Each channel updates independently; consumers should treat any field
 * being null as "no sample yet" rather than "channel inactive".
 */
data class LiveSnapshot(
    /** Latest heart-rate reading in BPM (only emitted when status is locked). */
    val hrBpm: Int? = null,
    /** Monotonic system-millis timestamp of the most recent HR sample (for pulse animation). */
    val hrTickMs: Long = 0,

    /** Recent PPG green values (auto-normalised at the UI layer). Newest at the end. */
    val ppgRecent: List<Int> = emptyList(),

    /** Latest EDA reading in microsiemens. */
    val edaUs: Float? = null,

    /** Latest 3-axis accel magnitude (Euclidean norm of the raw integer axes). */
    val accelMag: Float? = null,
) {
    companion object {
        /** Sliding window length for the PPG sparkline. ~2.4 s at 25 Hz. */
        const val PPG_WINDOW_SIZE = 60
    }
}
