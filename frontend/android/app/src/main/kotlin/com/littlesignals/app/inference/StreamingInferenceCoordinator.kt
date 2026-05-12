package com.littlesignals.app.inference

/**
 * Owns the [StressPipeline] for one capture session. Called once per second by
 * the capture loop; runs calibration as soon as we have 180s of contiguous
 * data, then inference once per [tickIntervalSec] (default 60s) thereafter.
 * Detections go to [listener].
 *
 * Thread model: single-writer (the capture coroutine). No locks.
 */
class StreamingInferenceCoordinator(
    private val preprocessor: StreamingPreprocessor,
    engine: InferenceEngine,
    private val tickIntervalSec: Int = 60,
    private val listener: DetectionListener = DetectionListener { /* default no-op */ },
) {
    private val pipeline = StressPipeline(engine)
    private var lastInferenceTickSec: Int = -1
    private var sessionStartMs: Long = 0L

    fun isCalibrated(): Boolean = pipeline.isCalibrated

    fun tick(currentMs: Long) {
        if (sessionStartMs == 0L) sessionStartMs = currentMs
        if (pipeline.isCalibrated) return  // chunk inference lands in Task 5

        // Try to calibrate as soon as we have a 300s window (which contains the
        // first 180s as baseline). Matches Phase 1 PipelineRunner behavior.
        val snap = preprocessor.snapshot25Hz() ?: return
        val baselineSteps = 180 * 25
        pipeline.calibrate(
            snap.ppgSmooth.copyOfRange(0, baselineSteps),
            snap.eda.copyOfRange(0, baselineSteps),
            snap.accMag.copyOfRange(0, baselineSteps),
        )
    }
}
