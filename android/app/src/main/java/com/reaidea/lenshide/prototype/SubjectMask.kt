package com.reaidea.lenshide.prototype

import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sqrt

/**
 * Pure geometry shared by the GPU video shader, the CPU photo renderer and JVM unit tests.
 * Display coordinates are top-left origin and normalized to the displayed frame.
 * Analysis coordinates are top-left origin over the square letterboxed analysis image.
 * Keep the GLSL in FacePixelEffect in sync with these formulas.
 */
object SubjectMask {
    /** iOS default pixel style: CIPixellate scale 24 at a 720p render size. */
    const val CELL_AT_720 = 24f
    const val MIN_CELL = 8

    /** Person mask feather window, matching the shader smoothstep. */
    const val PERSON_LOW = 0.35f
    const val PERSON_HIGH = 0.65f

    /** iOS radial gradient: fully inside at radius 0.43, transparent at 0.5 of the expanded rect. */
    const val FACE_INNER = 0.86f
    const val FACE_OUTER = 1.0f

    /** Dilation in analysis texels (about 4-5 display px at 720p), analogous to iOS safety radius. */
    const val PERSON_SAFETY_TEXELS = 2

    fun smoothstep(edge0: Float, edge1: Float, x: Float): Float {
        val t = ((x - edge0) / (edge1 - edge0)).coerceIn(0f, 1f)
        return t * t * (3 - 2 * t)
    }

    /** Scale from display to analysis square: (w / max, h / max). Letterbox is centred. */
    fun letterboxFit(width: Int, height: Int): FloatArray {
        val maxDimension = max(width, height).toFloat()
        return floatArrayOf(width / maxDimension, height / maxDimension)
    }

    fun cellSize(width: Int, height: Int): Int =
        max(MIN_CELL, (CELL_AT_720 * min(width, height) / 720f).roundToInt())

    /**
     * Combined coverage in [0, 1] at a display-normalized point.
     * [person] is optional so faces still get their ellipse when segmentation is empty.
     */
    fun alpha(u: Float, v: Float, person: PersonMask?, faces: List<FaceBox>, fit: FloatArray): Float {
        var coverage = 0f
        if (person != null) {
            val lu = (u - 0.5f) * fit[0] + 0.5f
            val lv = (v - 0.5f) * fit[1] + 0.5f
            coverage = smoothstep(PERSON_LOW, PERSON_HIGH, person.sample(lu, lv))
        }
        for (face in faces) {
            val dx = (u - face.cx) / face.rx
            val dy = (v - face.cy) / face.ry
            val ellipse = 1f - smoothstep(FACE_INNER, FACE_OUTER, sqrt(dx * dx + dy * dy))
            coverage = max(coverage, ellipse)
        }
        return coverage
    }
}

/**
 * Face coverage ellipse in display-normalized coordinates, unclamped.
 * Built from the detector box with the same expansion as iOS expandedForFaceCoverage.
 */
data class FaceBox(val cx: Float, val cy: Float, val rx: Float, val ry: Float)

/**
 * Person silhouette on the square letterboxed analysis image, top-first, 0..255.
 * Already dilated; [size] is the texel count per side.
 */
class PersonMask(val size: Int, val alpha: ByteArray) {
    init { require(alpha.size == size * size) { "Mask size mismatch" } }

    /** Bilinear sample with clamp-to-edge, same as GL_LINEAR + GL_CLAMP_TO_EDGE. Returns 0..1. */
    fun sample(u: Float, v: Float): Float {
        val x = (u * size - 0.5f).coerceIn(0f, size - 1f)
        val y = (v * size - 0.5f).coerceIn(0f, size - 1f)
        val x0 = x.toInt()
        val y0 = y.toInt()
        val x1 = min(x0 + 1, size - 1)
        val y1 = min(y0 + 1, size - 1)
        val fx = x - x0
        val fy = y - y0
        val top = at(x0, y0) + (at(x1, y0) - at(x0, y0)) * fx
        val bottom = at(x0, y1) + (at(x1, y1) - at(x0, y1)) * fx
        return (top + (bottom - top) * fy) / 255f
    }

    private fun at(x: Int, y: Int): Float = (alpha[y * size + x].toInt() and 0xFF).toFloat()

    companion object {
        /** Binary person mask dilated by [radius] texels using separable max filters. */
        fun dilated(size: Int, binary: ByteArray, radius: Int = SubjectMask.PERSON_SAFETY_TEXELS): PersonMask {
            require(binary.size == size * size)
            val horizontal = ByteArray(binary.size)
            for (y in 0 until size) for (x in 0 until size) {
                var best = 0
                for (dx in -radius..radius) {
                    val sx = x + dx
                    if (sx in 0 until size) best = max(best, binary[y * size + sx].toInt() and 0xFF)
                }
                horizontal[y * size + x] = best.toByte()
            }
            val output = ByteArray(binary.size)
            for (y in 0 until size) for (x in 0 until size) {
                var best = 0
                for (dy in -radius..radius) {
                    val sy = y + dy
                    if (sy in 0 until size) best = max(best, horizontal[sy * size + x].toInt() and 0xFF)
                }
                output[y * size + x] = best.toByte()
            }
            return PersonMask(size, output)
        }
    }
}
