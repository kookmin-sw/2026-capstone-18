package com.littlesignals.app.inference

/**
 * One inference result emitted by [StreamingInferenceCoordinator] every ~60 s.
 *
 * - [sessionElapsedSec] is the seconds since the capture session started (mirrors
 *   `currentTimeSec` in [StressPipeline.processBuffer] / Phase 1).
 * - [detectedAtMs] is wall-clock UTC ms at the moment the inference completed —
 *   this is what gets posted to `POST /api/v1/events` as `detected_at`.
 * - [shouldNotify] is the pipeline's user-facing notification decision (post to
 *   backend, surface on UI). Sub-threshold/in-cooldown chunks get `shouldNotify=false`.
 */
data class DetectionResult(
    val sessionElapsedSec: Int,
    val detectedAtMs: Long,
    val probStress: Double,
    val state: String,            // "Baseline" or "STRESS_EVENT"
    val inStressEvent: Boolean,
    val shouldNotify: Boolean,
)
