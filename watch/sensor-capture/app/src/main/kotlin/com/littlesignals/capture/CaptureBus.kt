package com.littlesignals.capture

import java.util.concurrent.CopyOnWriteArrayList

enum class EndReason { COMPLETED, USER_STOPPED, ERROR }

interface CaptureConsumer {
    fun onSessionStart(startedAtMs: Long, durationMs: Long)
    fun onSample(channel: Channel, sample: Sample)
    fun onSessionEnd(reason: EndReason, error: String? = null)
}

object CaptureBus {
    private val subs = CopyOnWriteArrayList<CaptureConsumer>()

    fun subscribe(c: CaptureConsumer) { subs.add(c) }
    fun unsubscribe(c: CaptureConsumer) { subs.remove(c) }

    fun publishStart(startedAtMs: Long, durationMs: Long) =
        subs.forEach { runCatching { it.onSessionStart(startedAtMs, durationMs) } }

    fun publishSample(channel: Channel, sample: Sample) =
        subs.forEach { runCatching { it.onSample(channel, sample) } }

    fun publishEnd(reason: EndReason, error: String? = null) =
        subs.forEach { runCatching { it.onSessionEnd(reason, error) } }
}
