package com.littlesignals.capture

import kotlinx.coroutines.flow.MutableStateFlow

enum class State { IDLE, CAPTURING, DONE, ERROR }

data class CaptureUiState(
    val state: State = State.IDLE,
    val elapsedMs: Long = 0L,
    val durationMs: Long = -1L,
    val hrCount: Long = 0L,
    val ppgCount: Long = 0L,
    val edaCount: Long = 0L,
    val accelCount: Long = 0L,
    val error: String? = null,
)

object CaptureState {
    val flow = MutableStateFlow(CaptureUiState())
}
