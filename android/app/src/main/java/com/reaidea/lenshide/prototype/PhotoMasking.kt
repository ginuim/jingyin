package com.reaidea.lenshide.prototype

import android.graphics.Bitmap
import kotlin.math.min

/**
 * CPU counterpart of the video shader for single photos: whole-frame mosaic blended by the same
 * person silhouette and face ellipses. Runs on a worker thread; never on the main thread.
 */
object PhotoMasking {
    fun render(source: Bitmap, detection: Detection): Bitmap {
        if (detection.faces.isEmpty() && detection.person == null) {
            return source.copy(Bitmap.Config.ARGB_8888, false)
        }
        val width = source.width
        val height = source.height
        val src = IntArray(width * height)
        val copy = if (source.config == Bitmap.Config.HARDWARE) source.copy(Bitmap.Config.ARGB_8888, false) else source
        try {
            copy.getPixels(src, 0, width, 0, 0, width, height)
        } finally { if (copy !== source) copy.recycle() }
        val out = src.copyOf()
        val cell = SubjectMask.cellSize(width, height)
        val fit = SubjectMask.letterboxFit(width, height)
        for (y in 0 until height) {
            val v = (y + 0.5f) / height
            val centreY = min(height - 1, (y / cell) * cell + cell / 2)
            for (x in 0 until width) {
                val index = y * width + x
                val u = (x + 0.5f) / width
                val a = SubjectMask.alpha(u, v, detection.person, detection.faces, fit)
                if (a <= 0f) continue
                val centreX = min(width - 1, (x / cell) * cell + cell / 2)
                val mosaic = src[centreY * width + centreX]
                out[index] = blend(src[index], mosaic, a)
            }
        }
        return Bitmap.createBitmap(out, width, height, Bitmap.Config.ARGB_8888)
    }

    private fun blend(source: Int, mosaic: Int, a: Float): Int {
        var result = 0
        for (shift in 0..16 step 8) {
            val s = (source shr shift) and 0xFF
            val m = (mosaic shr shift) and 0xFF
            result = result or ((s + (m - s) * a).toInt().coerceIn(0, 255) shl shift)
        }
        return (source and -0x1000000) or result
    }
}
