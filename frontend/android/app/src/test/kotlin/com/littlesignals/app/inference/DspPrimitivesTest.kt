package com.littlesignals.app.inference

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

class DspPrimitivesTest {

    @Test fun `linearInterp midpoint`() {
        val xs = doubleArrayOf(0.0, 1.0, 2.0)
        val ys = doubleArrayOf(0.0, 10.0, 20.0)
        val out = DspPrimitives.linearInterp(xs, ys, doubleArrayOf(0.5, 1.5))
        assertArrayEquals(doubleArrayOf(5.0, 15.0), out, 1e-12)
    }

    @Test fun `linearInterp extrapolates outside range`() {
        val xs = doubleArrayOf(1.0, 2.0)
        val ys = doubleArrayOf(10.0, 20.0)
        val out = DspPrimitives.linearInterp(xs, ys, doubleArrayOf(0.0, 3.0))
        assertArrayEquals(doubleArrayOf(0.0, 30.0), out, 1e-12)
    }

    @Test fun `previousInterp returns step value at and below sample`() {
        val xs = doubleArrayOf(0.0, 1.0, 2.0)
        val ys = doubleArrayOf(7.0, 8.0, 9.0)
        val out = DspPrimitives.previousInterp(xs, ys, doubleArrayOf(0.0, 0.5, 1.0, 1.999, 2.0))
        assertArrayEquals(doubleArrayOf(7.0, 7.0, 8.0, 8.0, 9.0), out, 1e-12)
    }

    @Test fun `previousInterp extrapolates before first using first value`() {
        val xs = doubleArrayOf(1.0, 2.0)
        val ys = doubleArrayOf(10.0, 20.0)
        val out = DspPrimitives.previousInterp(xs, ys, doubleArrayOf(0.0, 5.0))
        assertEquals(10.0, out[0], 1e-12)
        assertEquals(20.0, out[1], 1e-12)
    }
}
