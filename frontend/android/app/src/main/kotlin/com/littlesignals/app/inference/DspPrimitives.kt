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

    // 4th-order Butterworth bandpass [0.1, 10] Hz at fs=25 Hz.
    // Regenerate with: scipy.signal.butter(4, [0.1/12.5, 10.0/12.5], btype="bandpass")
    private val BUTTER_B = doubleArrayOf(
        0.4179817818322393, 0.0, -1.671927127328957, 0.0, 2.5078906909934355, 0.0, -1.671927127328957, 0.0, 0.4179817818322393
    )
    private val BUTTER_A = doubleArrayOf(
        1.0, -1.5686466113228241, -1.1934177022092531, 1.8942008149538059, 1.38153803540271, -1.205355922503398, -0.7567091503542607, 0.2736540992611558, 0.17473914968663504
    )

    fun butterworthBandpassFiltFilt(x: DoubleArray): DoubleArray = filtFilt(BUTTER_B, BUTTER_A, x)

    // Mirrors scipy.signal.filtfilt with default padding (3 * max(len(a), len(b))) and odd-extension.
    fun filtFilt(b: DoubleArray, a: DoubleArray, x: DoubleArray): DoubleArray {
        val nfilt = max(b.size, a.size)
        val padLen = 3 * nfilt
        require(x.size > padLen) { "input too short for filtfilt (need > $padLen)" }
        val ext = oddExtend(x, padLen)
        val zi = lfilterZi(b, a)
        val fwd = lfilter(b, a, ext, scaleZi(zi, ext[0]))
        val rev = lfilter(b, a, fwd.reversedArray(), scaleZi(zi, fwd.last()))
        val ffOut = rev.reversedArray()
        return ffOut.copyOfRange(padLen, ffOut.size - padLen)
    }

    private fun oddExtend(x: DoubleArray, n: Int): DoubleArray {
        val out = DoubleArray(x.size + 2 * n)
        for (i in 0 until n) out[i] = 2 * x[0] - x[n - i]
        for (i in x.indices) out[n + i] = x[i]
        for (i in 0 until n) out[n + x.size + i] = 2 * x.last() - x[x.size - 2 - i]
        return out
    }

    internal fun lfilter(b: DoubleArray, a: DoubleArray, x: DoubleArray, zi: DoubleArray): DoubleArray {
        val n = max(b.size, a.size)
        val z = zi.copyOf(n - 1)
        val y = DoubleArray(x.size)
        val a0 = a[0]
        for (i in x.indices) {
            val xi = x[i]
            val yi = (b[0] * xi + z[0]) / a0
            y[i] = yi
            for (k in 1 until n - 1) {
                val bk = if (k < b.size) b[k] else 0.0
                val ak = if (k < a.size) a[k] else 0.0
                z[k - 1] = bk * xi + z[k] - ak * yi
            }
            val kLast = n - 1
            val bk = if (kLast < b.size) b[kLast] else 0.0
            val ak = if (kLast < a.size) a[kLast] else 0.0
            z[n - 2] = bk * xi - ak * yi
        }
        return y
    }

    // scipy.signal.lfilter_zi: solves (I - A_companion^T) zi = B - a[1:]*b[0] for filter steady-state initial conditions.
    // Builds the companion matrix transposed and solves the linear system via Gaussian elimination with partial pivoting.
    internal fun lfilterZi(b: DoubleArray, a: DoubleArray): DoubleArray {
        val n = max(b.size, a.size)
        val bb = b.copyOf(n); val aa = a.copyOf(n)
        val a0 = aa[0]
        for (i in bb.indices) bb[i] /= a0
        for (i in aa.indices) aa[i] /= a0
        val size = n - 1
        // Build M = I - companion(a).T. companion(a) has top row = [-a1, -a2, ..., -a_{n-1}],
        // and sub-diagonal 1s. Its transpose has first column = [-a1, ..., -a_{n-1}] and
        // super-diagonal 1s. So I - companion(a).T has:
        //   diagonal: 1 + a[1] (row 0), 1 elsewhere
        //   first column (rows 1..size-1): a[i+1]
        //   super-diagonal: -1
        val m = Array(size) { DoubleArray(size) }
        for (i in 0 until size) {
            m[i][i] = 1.0
        }
        // first column comes from companion top row's first entry shifted into column 0 of transpose
        // Actually companion(a)[0,j] = -a[j+1]; transposed -> companion(a).T[j,0] = -a[j+1]
        // So I - companion.T at [j,0] = (j==0 ? 1 : 0) - (-a[j+1]) = (j==0 ? 1+a[1] : a[j+1])
        m[0][0] = 1.0 + aa[1]
        for (j in 1 until size) m[j][0] = aa[j + 1]
        // companion(a)[k,k-1] = 1 for k=1..size-1; transposed -> companion.T[k-1,k] = 1
        // So I - companion.T at [k-1,k] = -1
        for (k in 1 until size) m[k - 1][k] = -1.0

        val rhs = DoubleArray(size)
        for (i in 0 until size) rhs[i] = bb[i + 1] - aa[i + 1] * bb[0]

        return solveLinear(m, rhs)
    }

    // Gaussian elimination with partial pivoting for small dense systems.
    private fun solveLinear(matIn: Array<DoubleArray>, rhsIn: DoubleArray): DoubleArray {
        val n = rhsIn.size
        val m = Array(n) { matIn[it].copyOf() }
        val r = rhsIn.copyOf()
        for (col in 0 until n) {
            // partial pivot
            var piv = col
            var pivVal = kotlin.math.abs(m[col][col])
            for (row in col + 1 until n) {
                val v = kotlin.math.abs(m[row][col])
                if (v > pivVal) { pivVal = v; piv = row }
            }
            if (piv != col) {
                val tmp = m[col]; m[col] = m[piv]; m[piv] = tmp
                val tr = r[col]; r[col] = r[piv]; r[piv] = tr
            }
            val diag = m[col][col]
            for (row in col + 1 until n) {
                val factor = m[row][col] / diag
                if (factor == 0.0) continue
                for (k in col until n) m[row][k] -= factor * m[col][k]
                r[row] -= factor * r[col]
            }
        }
        val x = DoubleArray(n)
        for (i in n - 1 downTo 0) {
            var s = r[i]
            for (j in i + 1 until n) s -= m[i][j] * x[j]
            x[i] = s / m[i][i]
        }
        return x
    }

    private fun scaleZi(zi: DoubleArray, x0: Double): DoubleArray {
        val out = DoubleArray(zi.size)
        for (i in zi.indices) out[i] = zi[i] * x0
        return out
    }
}
