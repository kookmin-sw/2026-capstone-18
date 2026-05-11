package com.littlesignals.app.inference

data class SyncedSignals(
    val ppgSmooth: DoubleArray,
    val eda: DoubleArray,
    val accMag: DoubleArray,
    val durationSeconds: Double,
) {
    init {
        require(ppgSmooth.size == eda.size && eda.size == accMag.size) {
            "channel arrays must have equal length"
        }
    }
}

data class ChunkResult(
    val timeSeconds: Int,
    val timeLabel: String,
    val probStress: Double,
    val state: String,
    val shouldNotify: Boolean,
    val inStressEvent: Boolean,
)

sealed class InferenceError(message: String, cause: Throwable? = null) : RuntimeException(message, cause) {
    class Preprocess(message: String, cause: Throwable? = null) : InferenceError(message, cause)
    class Runner(message: String, cause: Throwable? = null) : InferenceError(message, cause)
    class ModelLoad(message: String, cause: Throwable? = null) : InferenceError(message, cause)
}
