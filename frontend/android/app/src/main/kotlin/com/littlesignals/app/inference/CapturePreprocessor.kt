package com.littlesignals.app.inference

import java.io.ByteArrayInputStream
import java.util.zip.ZipInputStream
import kotlin.math.sqrt

object CapturePreprocessor {
    private const val TARGET_HZ = 25
    private val REQUIRED = listOf("ppg_green.csv", "eda.csv", "accel.csv")

    fun preprocessZip(blob: ByteArray): SyncedSignals {
        val entries = try { readZip(blob) } catch (e: Exception) {
            throw InferenceError.Preprocess("upload is not a valid zip: ${e.message}", e)
        }
        for (req in REQUIRED) if (req !in entries) {
            throw InferenceError.Preprocess("missing $req in upload")
        }

        val ppg = parseScalarCsv(entries["ppg_green.csv"]!!, "ppg_green", "ppg_green.csv")
        val eda = parseScalarCsv(entries["eda.csv"]!!, "skin_conductance", "eda.csv")
        val accel = parseAccelCsv(entries["accel.csv"]!!)

        val t0 = maxOf(ppg.times.first(), eda.times.first(), accel.times.first())
        val tEnd = minOf(ppg.times.last(), eda.times.last(), accel.times.last())
        if (tEnd <= t0) throw InferenceError.Preprocess("captures do not overlap in time")

        val durationSec = (tEnd - t0) / 1000.0
        val nSamples = (durationSec * TARGET_HZ).toInt()
        val targetTimes = DoubleArray(nSamples) { i -> i.toDouble() / TARGET_HZ }

        fun rebase(times: LongArray): DoubleArray =
            DoubleArray(times.size) { i -> (times[i] - t0) / 1000.0 }

        val ppgRaw = DspPrimitives.linearInterp(rebase(ppg.times), ppg.values, targetTimes)
        val edaRaw = DspPrimitives.previousInterp(rebase(eda.times), eda.values, targetTimes)
        val accX = DspPrimitives.linearInterp(rebase(accel.times), accel.x, targetTimes)
        val accY = DspPrimitives.linearInterp(rebase(accel.times), accel.y, targetTimes)
        val accZ = DspPrimitives.linearInterp(rebase(accel.times), accel.z, targetTimes)

        val ppgSmooth = DspPrimitives.savgolWindow5Poly2(
            DspPrimitives.butterworthBandpassFiltFilt(ppgRaw)
        )
        val accMag = DoubleArray(nSamples) { i -> sqrt(accX[i] * accX[i] + accY[i] * accY[i] + accZ[i] * accZ[i]) }

        return SyncedSignals(ppgSmooth, edaRaw, accMag, durationSec)
    }

    private data class ScalarSeries(val times: LongArray, val values: DoubleArray)
    private data class AccelSeries(val times: LongArray, val x: DoubleArray, val y: DoubleArray, val z: DoubleArray)

    private fun readZip(blob: ByteArray): Map<String, String> {
        val out = mutableMapOf<String, String>()
        ZipInputStream(ByteArrayInputStream(blob)).use { zi ->
            while (true) {
                val e = zi.nextEntry ?: break
                if (!e.isDirectory) out[e.name] = zi.readBytes().toString(Charsets.UTF_8)
                zi.closeEntry()
            }
        }
        return out
    }

    private fun parseScalarCsv(csv: String, valueColumn: String, filename: String): ScalarSeries {
        val lines = csv.lineSequence().filter { it.isNotBlank() }.toList()
        require(lines.size >= 2) { "$filename: empty" }
        val header = lines[0].split(",").map { it.trim() }
        val tsIdx = header.indexOf("timestamp_ms")
        val vIdx = header.indexOf(valueColumn)
        if (tsIdx < 0 || vIdx < 0) {
            throw InferenceError.Preprocess("$filename missing columns (need timestamp_ms,$valueColumn)")
        }
        val times = LongArray(lines.size - 1)
        val values = DoubleArray(lines.size - 1)
        for (i in 1 until lines.size) {
            val cols = lines[i].split(",")
            times[i - 1] = cols[tsIdx].trim().toLong()
            values[i - 1] = cols[vIdx].trim().toDouble()
        }
        return ScalarSeries(times, values)
    }

    private fun parseAccelCsv(csv: String): AccelSeries {
        val lines = csv.lineSequence().filter { it.isNotBlank() }.toList()
        require(lines.size >= 2) { "accel.csv: empty" }
        val header = lines[0].split(",").map { it.trim() }
        val ti = header.indexOf("timestamp_ms")
        val xi = header.indexOf("x"); val yi = header.indexOf("y"); val zi = header.indexOf("z")
        if (ti < 0 || xi < 0 || yi < 0 || zi < 0) {
            throw InferenceError.Preprocess("accel.csv missing columns (need timestamp_ms,x,y,z)")
        }
        val n = lines.size - 1
        val t = LongArray(n); val x = DoubleArray(n); val y = DoubleArray(n); val z = DoubleArray(n)
        for (i in 1 until lines.size) {
            val cols = lines[i].split(",")
            t[i - 1] = cols[ti].trim().toLong()
            x[i - 1] = cols[xi].trim().toDouble()
            y[i - 1] = cols[yi].trim().toDouble()
            z[i - 1] = cols[zi].trim().toDouble()
        }
        return AccelSeries(t, x, y, z)
    }
}
