package com.littlesignals.app.inference

import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

object DspPrimitives {

    fun linearInterp(xs: DoubleArray, ys: DoubleArray, queries: DoubleArray): DoubleArray {
        require(xs.size == ys.size && xs.size >= 2) { "need at least 2 sample points" }
        val out = DoubleArray(queries.size)
        for (i in queries.indices) {
            val q = queries[i]
            val idx = upperBound(xs, q)
            val hi = idx.coerceIn(1, xs.lastIndex)
            val lo = hi - 1
            val x0 = xs[lo]; val x1 = xs[hi]
            val y0 = ys[lo]; val y1 = ys[hi]
            val span = x1 - x0
            out[i] = if (span == 0.0) y0 else y0 + (y1 - y0) * ((q - x0) / span)
        }
        return out
    }

    fun previousInterp(xs: DoubleArray, ys: DoubleArray, queries: DoubleArray): DoubleArray {
        require(xs.size == ys.size && xs.isNotEmpty()) { "need at least 1 sample point" }
        val out = DoubleArray(queries.size)
        for (i in queries.indices) {
            val q = queries[i]
            val idx = upperBound(xs, q) - 1
            out[i] = ys[idx.coerceIn(0, xs.lastIndex)]
        }
        return out
    }

    private fun upperBound(xs: DoubleArray, q: Double): Int {
        var lo = 0; var hi = xs.size
        while (lo < hi) {
            val mid = (lo + hi) ushr 1
            if (xs[mid] <= q) lo = mid + 1 else hi = mid
        }
        return lo
    }
}
