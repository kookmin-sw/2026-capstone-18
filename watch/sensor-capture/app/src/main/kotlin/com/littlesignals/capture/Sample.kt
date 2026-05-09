package com.littlesignals.capture

sealed class Sample {
    abstract val timestampMs: Long
    data class Scalar(override val timestampMs: Long, val value: Double) : Sample()
    data class Vector(override val timestampMs: Long, val values: List<Double>) : Sample()
}

enum class Channel { HR, PPG, EDA, ACCEL }
