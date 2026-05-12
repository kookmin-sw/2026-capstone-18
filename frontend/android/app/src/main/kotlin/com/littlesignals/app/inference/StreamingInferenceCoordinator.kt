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
        val sessionElapsedSec = ((currentMs - sessionStartMs) / 1000L).toInt()

        if (!pipeline.isCalibrated) {
            val snap = preprocessor.snapshot25Hz() ?: return
            val baselineSteps = 180 * 25
            pipeline.calibrate(
                snap.ppgSmooth.copyOfRange(0, baselineSteps),
                snap.eda.copyOfRange(0, baselineSteps),
                snap.accMag.copyOfRange(0, baselineSteps),
            )
            // Fall through to also run inference on this tick — calibration finished
            // means snap is a full 300s window, which is exactly what processBuffer wants.
            runInference(snap, sessionElapsedSec, currentMs)
            lastInferenceTickSec = sessionElapsedSec
            return
        }

        // Throttle to one inference per tickIntervalSec.
        if (sessionElapsedSec - lastInferenceTickSec < tickIntervalSec) return
        val snap = preprocessor.snapshot25Hz() ?: return
        runInference(snap, sessionElapsedSec, currentMs)
        lastInferenceTickSec = sessionElapsedSec
    }

    private fun runInference(snap: SyncedSignals, sessionElapsedSec: Int, currentMs: Long) {
        val (notify, prob) = pipeline.processBuffer(
            snap.ppgSmooth,
            snap.eda,
            snap.accMag,
            currentTimeSec = sessionElapsedSec,
        )
        listener.onDetection(
            DetectionResult(
                sessionElapsedSec = sessionElapsedSec,
                detectedAtMs = currentMs,
                probStress = prob,
                state = if (pipeline.isInStressEvent) "STRESS_EVENT" else "Baseline",
                inStressEvent = pipeline.isInStressEvent,
                shouldNotify = notify,
            )
        )
    }
}
