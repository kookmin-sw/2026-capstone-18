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

    private fun stddev(a: DoubleArray): Double {
        val mean = a.average()
        var sq = 0.0
        for (v in a) { val d = v - mean; sq += d * d }
        return kotlin.math.sqrt(sq / a.size)
    }

    private fun subtract(a: DoubleArray, b: DoubleArray): DoubleArray =
        DoubleArray(a.size) { i -> a[i] - b[i] }
}
