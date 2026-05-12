package com.littlesignals.capture

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import org.json.JSONObject

/**
 * Drains [SampleBatch] every [flushIntervalMs] and pushes each non-empty drain
 * to the phone as `/biosignals/samples`. [stop] sends a final drain (if any)
 * then `/biosignals/end` with the given reason/error.
 *
 * Lifecycle: caller creates an instance, registers sample callbacks via [onHr]/
 * [onPpg]/[onEda]/[onAccel] (typically from a StreamingRecorder's TrackerEventListener),
 * then calls [start] to launch the flush coroutine. Caller MUST call [stop] exactly
 * once at session end to flush the remainder and emit the end marker.
 *
 * [scope] is injected so tests can use [kotlinx.coroutines.test.TestScope] + virtual time.
 * [nowMs] is injected so tests don't depend on `System.currentTimeMillis()`.
 */
class PhoneSenderConsumer(
    private val sender: PhoneSender,
    private val scope: CoroutineScope,
    private val flushIntervalMs: Long = 1_000L,
    private val nowMs: () -> Long = { System.currentTimeMillis() },
) {
    private val batch = SampleBatch()
    private var flushJob: Job? = null

    fun onHr(s: ScalarSample) = batch.addHr(s)
    fun onPpg(s: ScalarSample) = batch.addPpg(s)
    fun onEda(s: ScalarSample) = batch.addEda(s)
    fun onAccel(s: AccelSample) = batch.addAccel(s)

    fun start() {
        if (flushJob != null) return
        flushJob = scope.launch {
            while (isActive) {
                delay(flushIntervalMs)
                flushIfNonEmpty()
            }
        }
    }

    suspend fun stop(reason: String, error: String?) {
        flushJob?.cancel()
        flushJob = null
        flushIfNonEmpty()
        val end = JSONObject().apply {
            put("reason", reason)
            put("error", error ?: JSONObject.NULL)
        }.toString()
        sender.send("/biosignals/end", end)
    }

    private suspend fun flushIfNonEmpty() {
        if (batch.isEmpty()) return
        val drain = batch.drain()
        val body = serializeBatchPayload(tStartMs = nowMs(), drain = drain)
        val sent = sender.send("/biosignals/samples", body)
        if (!sent) {
            // Phone unreachable — re-queue drained samples so the next flush retries.
            // batch.restore() caps the merged buffer at MAX_SAMPLES_PER_CHANNEL per channel.
            batch.restore(drain)
        }
    }
}
