package com.littlesignals.app.inference

import kotlin.math.ln1p

class StressPipeline(
    private val engine: InferenceEngine,
    val confThresh: Double = 0.60,
    val marThresh: Double = 0.10,
    val maxGapChunks: Int = 2,
    val cooldownSec: Int = 300,
) {
    var isCalibrated: Boolean = false; private set
    var meanPpgBase: Double = 0.0; private set
    var stdPpgBase: Double = 1.0; private set
    var meanEdaBase: Double = 0.0; private set
    var stdEdaBase: Double = 1.0; private set
    var acc1gBaseline: Double = 1.0; private set
    var meanLogStdEdaBase: Double = 0.0; private set
    var stdLogStdEdaBase: Double = 1.0; private set
    var meanLogStdBvpBase: Double = 0.0; private set
    var stdLogStdBvpBase: Double = 1.0; private set

    var isInStressEvent: Boolean = false; private set
    var silentChunksSinceStress: Int = 0; private set
    var lastNotificationSec: Int = -99999; private set

    fun calibrate(rawPpg: DoubleArray, rawEda: DoubleArray, rawAccMag: DoubleArray) {
        require(rawPpg.size == rawEda.size && rawEda.size == rawAccMag.size)
        require(rawPpg.size >= 4500) { "need at least 180s at 25Hz" }

        val validPpg = rawPpg.copyOfRange(250, rawPpg.size)
        val validEda = rawEda.copyOfRange(250, rawEda.size)
        meanPpgBase = validPpg.average()
        stdPpgBase = stddev(validPpg) + 1e-8
        meanEdaBase = validEda.average()
        stdEdaBase = stddev(validEda) + 1e-8
        acc1gBaseline = rawAccMag.average()

        val edaCalib = DoubleArray(rawEda.size) { i -> (rawEda[i] - meanEdaBase) / stdEdaBase }
        val ppgCalib = DoubleArray(rawPpg.size) { i -> (rawPpg[i] - meanPpgBase) / stdPpgBase }

        val fastWin = 10 * 25; val slowWin = 60 * 25
        val edaMacd = subtract(DspPrimitives.ema(edaCalib, fastWin), DspPrimitives.ema(edaCalib, slowWin))
        val absPpg = DoubleArray(ppgCalib.size) { i -> kotlin.math.abs(ppgCalib[i]) }
        val bvpMacd = subtract(DspPrimitives.ema(absPpg, fastWin), DspPrimitives.ema(absPpg, slowWin))

        val trailWin = 300 * 25
        val edaStat = DspPrimitives.causalRollingStats(edaMacd, trailWin)
        val bvpStat = DspPrimitives.causalRollingStats(bvpMacd, trailWin)
        val logStdEda = DoubleArray(edaStat.std.size) { i -> ln1p(edaStat.std[i]) }
        val logStdBvp = DoubleArray(bvpStat.std.size) { i -> ln1p(bvpStat.std[i]) }

        meanLogStdEdaBase = logStdEda.average()
        stdLogStdEdaBase = stddev(logStdEda) + 1e-8
        meanLogStdBvpBase = logStdBvp.average()
        stdLogStdBvpBase = stddev(logStdBvp) + 1e-8

        isCalibrated = true
    }

    private companion object {
        const val TARGET_HZ = 25
        const val CHUNK_STEPS = 60 * TARGET_HZ   // 1500
        const val BUFFER_STEPS = 300 * TARGET_HZ // 7500
    }

    fun processBuffer(
        bufferPpg: DoubleArray,
        bufferEda: DoubleArray,
        bufferAccMag: DoubleArray,
        currentTimeSec: Int,
    ): Pair<Boolean, Double> {
        if (!isCalibrated) return false to 0.0
        require(bufferPpg.size == BUFFER_STEPS && bufferEda.size == BUFFER_STEPS && bufferAccMag.size == BUFFER_STEPS) {
            "buffer must be exactly $BUFFER_STEPS samples"
        }

        val edaCalib = DoubleArray(BUFFER_STEPS) { i -> clip((bufferEda[i] - meanEdaBase) / stdEdaBase, -35.0, 35.0) }
        val ppgCalib = DoubleArray(BUFFER_STEPS) { i -> clip((bufferPpg[i] - meanPpgBase) / stdPpgBase, -35.0, 35.0) }
        val accGlobal = DoubleArray(BUFFER_STEPS) { i -> clip((bufferAccMag[i] - acc1gBaseline) / acc1gBaseline, -3.0, 3.0) }

        val fast = 10 * TARGET_HZ; val slow = 60 * TARGET_HZ; val ctx = 300 * TARGET_HZ
        val emaEdaFast = DspPrimitives.ema(edaCalib, fast)
        val emaEdaSlow = DspPrimitives.ema(edaCalib, slow)
        val absPpg = DoubleArray(BUFFER_STEPS) { i -> kotlin.math.abs(ppgCalib[i]) }
        val emaBvpFast = DspPrimitives.ema(absPpg, fast)
        val emaBvpSlow = DspPrimitives.ema(absPpg, slow)
        val edaEmaCtx = DspPrimitives.ema(edaCalib, ctx)
        val bvpEmaCtx = DspPrimitives.ema(absPpg, ctx)

        val edaMacd = DoubleArray(BUFFER_STEPS) { i -> emaEdaFast[i] - emaEdaSlow[i] }
        val bvpMacd = DoubleArray(BUFFER_STEPS) { i -> emaBvpFast[i] - emaBvpSlow[i] }
        val edaStat = DspPrimitives.causalRollingStats(edaMacd, ctx)
        val bvpStat = DspPrimitives.causalRollingStats(bvpMacd, ctx)
        val normStdEda = DoubleArray(BUFFER_STEPS) { i -> (kotlin.math.ln1p(edaStat.std[i]) - meanLogStdEdaBase) / stdLogStdEdaBase }
        val normStdBvp = DoubleArray(BUFFER_STEPS) { i -> (kotlin.math.ln1p(bvpStat.std[i]) - meanLogStdBvpBase) / stdLogStdBvpBase }

        // Take last CHUNK_STEPS of each channel, transpose to (9, 1500), float32.
        val start = BUFFER_STEPS - CHUNK_STEPS
        val channels = Array(9) { FloatArray(CHUNK_STEPS) }
        for (i in 0 until CHUNK_STEPS) {
            val j = start + i
            channels[0][i] = ppgCalib[j].toFloat()
            channels[1][i] = edaCalib[j].toFloat()
            channels[2][i] = accGlobal[j].toFloat()
            channels[3][i] = edaEmaCtx[j].toFloat()
            channels[4][i] = bvpEmaCtx[j].toFloat()
            channels[5][i] = edaMacd[j].toFloat()
            channels[6][i] = bvpMacd[j].toFloat()
            channels[7][i] = normStdEda[j].toFloat()
            channels[8][i] = normStdBvp[j].toFloat()
        }

        val probStress = engine.runChunkProbStress(channels)
        var chunkMeanAcc = 0.0
        for (i in start until BUFFER_STEPS) chunkMeanAcc += accGlobal[i]
        chunkMeanAcc /= CHUNK_STEPS

        var isActive = probStress >= confThresh
        if (chunkMeanAcc > marThresh) isActive = false

        var shouldNotify = false
        if (isActive) {
            isInStressEvent = true
            silentChunksSinceStress = 0
            if ((currentTimeSec - lastNotificationSec) >= cooldownSec) {
                shouldNotify = true
                lastNotificationSec = currentTimeSec
            }
        } else if (isInStressEvent) {
            silentChunksSinceStress += 1
            if (silentChunksSinceStress > maxGapChunks) {
                isInStressEvent = false
                silentChunksSinceStress = 0
            }
        }
        return shouldNotify to probStress
    }

    private fun clip(v: Double, lo: Double, hi: Double): Double =
        if (v < lo) lo else if (v > hi) hi else v

    private fun stddev(a: DoubleArray): Double {
        val mean = a.average()
        var sq = 0.0
        for (v in a) { val d = v - mean; sq += d * d }
        return kotlin.math.sqrt(sq / a.size)
    }

    private fun subtract(a: DoubleArray, b: DoubleArray): DoubleArray =
        DoubleArray(a.size) { i -> a[i] - b[i] }
}
