package com.littlesignals.app.inference

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import java.nio.FloatBuffer
import kotlin.math.exp

class OnnxInferenceEngine private constructor(
    private val env: OrtEnvironment,
    private val session: OrtSession,
    private val inputName: String,
) : InferenceEngine {

    override fun runChunkProbStress(channels: Array<FloatArray>): Double {
        require(channels.size == 9) { "expected 9 channels, got ${channels.size}" }
        val steps = channels[0].size
        require(steps == 1500) { "expected 1500 steps, got $steps" }
        val buf = FloatBuffer.allocate(9 * steps)
        for (c in 0 until 9) buf.put(channels[c])
        buf.rewind()
        OnnxTensor.createTensor(env, buf, longArrayOf(1L, 9L, steps.toLong())).use { input ->
            val out = session.run(mapOf(inputName to input))
            out.use {
                @Suppress("UNCHECKED_CAST")
                val logits = (out[0].value as Array<FloatArray>)[0]
                val e0 = exp(logits[0].toDouble()); val e1 = exp(logits[1].toDouble())
                return e1 / (e0 + e1)
            }
        }
    }

    override fun close() {
        runCatching { session.close() }
        runCatching { env.close() }
    }

    companion object {
        fun create(onnxPath: String): OnnxInferenceEngine {
            val env = OrtEnvironment.getEnvironment()
            val opts = OrtSession.SessionOptions().apply { setIntraOpNumThreads(1) }
            val session = try { env.createSession(onnxPath, opts) }
            catch (e: Exception) { throw InferenceError.ModelLoad("failed to load ONNX: $onnxPath", e) }
            val input = session.inputNames.first()
            return OnnxInferenceEngine(env, session, input)
        }
    }
}
