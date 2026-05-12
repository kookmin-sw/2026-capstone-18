package com.littlesignals.capture

/**
 * Abstraction over the Wear Data Layer for sending a message to the paired phone.
 * Production impl: [WearPhoneSender]. Fake impl in tests.
 *
 * Returns `true` if the message was acknowledged by at least one phone node,
 * `false` if no node is connected or the send failed. Callers must not throw on
 * `false` — Wear connectivity is intermittent by design.
 */
interface PhoneSender {
    suspend fun send(path: String, body: String): Boolean
}
