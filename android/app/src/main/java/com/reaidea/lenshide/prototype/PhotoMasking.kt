package com.reaidea.lenshide.prototype

import android.graphics.Bitmap
import kotlin.math.min

/**
 * CPU counterpart of the video shader for single photos: whole-frame mosaic blended by the same
 * person silhouette and face ellipses. Runs on a worker thread; never on the main thread.
 */
object PhotoMasking {
    fun render(source: Bitmap, detection: Detection): Bitmap {
        val coverage = coverageField(source.width, source.height, detection)
        val width = source.width
        val height = source.height
        val src = IntArray(width * height)
        val copy = source.copy(Bitmap.Config.ARGB_8888, false)
        try {
            copy.getPixels(src, 0, width, 0, 0, width, height)
        } finally { copy.recycle() }
        val out = src.copyOf()
        val cell = SubjectMask.cellSize(width, height)
        for (y in 0 until height) {
            val centreY = min(height - 1, (y / cell) * cell + cell / 2)
            for (x in 0 until width) {
                val index = y * width + x
                val a = coverage[index]
                if (a <= 0f) continue
                val centreX = min(width - 1, (x / cell) * cell + cell / 2)
                val mosaic = src[centreY * width + centreX]
                out[index] = blend(src[index], mosaic, a)
            }
        }
        return Bitmap.createBitmap(out, width, height, Bitmap.Config.ARGB_8888)
    }

    /** Coverage per pixel in [0, 1]; exposed for JVM tests of the mask geometry. */
    fun coverageField(width: Int, height: Int, detection: Detection): FloatArray {
        val fit = SubjectMask.letterboxFit(width, height)
        val field = FloatArray(width * height)
        for (y in 0 until height) {
            val v = (y + 0.5f) / height
            for (x in 0 until width) {
                val u = (x + 0.5f) / width
                field[y * width + x] = SubjectMask.alpha(u, v, detection.person, detection.faces, fit)
            }
        }
        return field
    }

    private fun blend(source: Int, mosaic: Int, a: Float): Int {
        var result = 0
        for (shift in intArrayOf(0, 8, 16)) {
            val s = (source shr shift) and 0xFF
            val m = (mosaic shr shift) and 0xFF
            result = result or ((s + (m - s) * a).toInt().coerceIn(0, 255) shl shift)
        }
        return (source and -0x1000000) or result
    }
}
