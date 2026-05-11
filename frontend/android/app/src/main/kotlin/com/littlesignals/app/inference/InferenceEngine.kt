package com.littlesignals.app.inference

interface InferenceEngine : AutoCloseable {
    fun runChunkProbStress(channels: Array<FloatArray>): Double
}
