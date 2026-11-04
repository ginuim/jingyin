package com.reaidea.lenshide.prototype

import android.graphics.Bitmap
import kotlin.math.min

/**
 * CPU counterpart of the video shader for single photos: whole-frame mosaic blended by the same
 * person silhouette and face ellipses. Runs on a worker thread; never on the main thread.
 */
object PhotoMasking {
    fun render(source: Bitmap, detection: Detection, inverted: Boolean = false, blurred: Bitmap? = null,
        mosaicStrength: Float = 1f): Bitmap {
        if (!inverted && detection.faces.isEmpty() && detection.person == null) {
            return source.copy(Bitmap.Config.ARGB_8888, false)
        }
        val width = source.width
        val height = source.height
        val src = IntArray(width * height)
        val copy = if (source.config == Bitmap.Config.HARDWARE) source.copy(Bitmap.Config.ARGB_8888, false) else source
        try {
            copy.getPixels(src, 0, width, 0, 0, width, height)
        } finally { if (copy !== source) copy.recycle() }
        val blurPixels = blurred?.let { bitmap ->
            IntArray(bitmap.width * bitmap.height).also {
                bitmap.getPixels(it, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
            }
        }
        // softBlur is computed at a reduced size; sample it bilinearly back to full resolution.
        val blurWidth = blurred?.width ?: 0
        val blurHeight = blurred?.height ?: 0
        val blurLeft = IntArray(if (blurPixels == null) 0 else width)
        val blurRight = IntArray(blurLeft.size)
        val blurX = FloatArray(blurLeft.size)
        if (blurPixels != null) for (x in 0 until width) {
            val position = ((x + 0.5f) * blurWidth / width - 0.5f).coerceIn(0f, (blurWidth - 1).toFloat())
            val left = position.toInt()
            blurLeft[x] = left
            blurRight[x] = (left + 1).coerceAtMost(blurWidth - 1)
            blurX[x] = position - left
        }
        val out = src.copyOf()
        val cell = SubjectMask.cellSize(width, height, mosaicStrength)
        val fit = SubjectMask.letterboxFit(width, height)
        for (y in 0 until height) {
            val v = (y + 0.5f) / height
            val centreY = min(height - 1, (y / cell) * cell + cell / 2)
            val blurPosition = if (blurPixels == null) 0f else
                ((y + 0.5f) * blurHeight / height - 0.5f).coerceIn(0f, (blurHeight - 1).toFloat())
            val blurTop = blurPosition.toInt()
            val blurBottom = (blurTop + 1).coerceAtMost(blurHeight - 1)
            val blurY = blurPosition - blurTop
            for (x in 0 until width) {
                val index = y * width + x
                val u = (x + 0.5f) / width
                val coverage = SubjectMask.alpha(u, v, detection.person, detection.faces, fit)
                val a = if (inverted) 1f - coverage else coverage
                if (a <= 0f) continue
                val replacement = if (blurPixels == null) {
                    val centreX = min(width - 1, (x / cell) * cell + cell / 2)
                    src[centreY * width + centreX]
                } else {
                    val topRow = blurTop * blurWidth
                    val bottomRow = blurBottom * blurWidth
                    bilinear(blurPixels[topRow + blurLeft[x]], blurPixels[topRow + blurRight[x]],
                        blurPixels[bottomRow + blurLeft[x]], blurPixels[bottomRow + blurRight[x]], blurX[x], blurY)
                }
                out[index] = blend(src[index], replacement, a)
            }
        }
        return Bitmap.createBitmap(out, width, height, Bitmap.Config.ARGB_8888)
    }

    private fun bilinear(topLeft: Int, topRight: Int, bottomLeft: Int, bottomRight: Int, wx: Float, wy: Float): Int {
        var result = 0
        for (shift in 0..16 step 8) {
            val top = ((topLeft shr shift) and 0xFF) + (((topRight shr shift) and 0xFF) - ((topLeft shr shift) and 0xFF)) * wx
            val bottom = ((bottomLeft shr shift) and 0xFF) + (((bottomRight shr shift) and 0xFF) - ((bottomLeft shr shift) and 0xFF)) * wx
            val value = (top + (bottom - top) * wy).toInt().coerceIn(0, 255)
            result = result or (value shl shift)
        }
        return result
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
