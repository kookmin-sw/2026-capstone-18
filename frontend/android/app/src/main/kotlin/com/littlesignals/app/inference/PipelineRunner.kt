package com.littlesignals.app.inference

object PipelineRunner {
    private const val TARGET_HZ = 25
    private const val CHUNK_STEPS = 60 * TARGET_HZ
    private const val BUFFER_STEPS = 300 * TARGET_HZ
    private const val BASELINE_STEPS = 180 * TARGET_HZ

    fun run(synced: SyncedSignals, engine: InferenceEngine): List<ChunkResult> {
        if (synced.ppgSmooth.size < BUFFER_STEPS) {
            throw InferenceError.Runner(
                "recording too short: need at least ${BUFFER_STEPS / TARGET_HZ}s, got ${synced.ppgSmooth.size / TARGET_HZ}s"
            )
        }
        val pipeline = StressPipeline(engine)
        pipeline.calibrate(
            synced.ppgSmooth.copyOfRange(0, BASELINE_STEPS),
            synced.eda.copyOfRange(0, BASELINE_STEPS),
            synced.accMag.copyOfRange(0, BASELINE_STEPS),
        )
        val results = mutableListOf<ChunkResult>()
        var currentStep = BUFFER_STEPS
        while (currentStep < synced.ppgSmooth.size) {
            val currentTimeSec = currentStep / TARGET_HZ
            val bufferStart = currentStep - BUFFER_STEPS
            val (notify, prob) = pipeline.processBuffer(
                synced.ppgSmooth.copyOfRange(bufferStart, currentStep),
                synced.eda.copyOfRange(bufferStart, currentStep),
                synced.accMag.copyOfRange(bufferStart, currentStep),
                currentTimeSec,
            )
            results += ChunkResult(
                timeSeconds = currentTimeSec,
                timeLabel = "${currentTimeSec / 60}m ${"%02d".format(currentTimeSec % 60)}s",
                probStress = prob,
                state = if (pipeline.isInStressEvent) "STRESS_EVENT" else "Baseline",
                shouldNotify = notify,
                inStressEvent = pipeline.isInStressEvent,
            )
            currentStep += CHUNK_STEPS
        }
        return results
    }
}
