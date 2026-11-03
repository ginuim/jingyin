package com.reaidea.lenshide.prototype

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Geometry-only checks; no Android, OpenCV or MediaPipe runtime is needed. */
class SubjectMaskTest {
    private val face = FaceBox(cx = 0.5f, cy = 0.5f, rx = 0.1f, ry = 0.15f)

    @Test fun faceEllipseIsCentredAndRoundedNotRectangular() {
        val fit = SubjectMask.letterboxFit(1280, 720)
        assertEquals(1f, SubjectMask.alpha(0.5f, 0.5f, null, listOf(face), fit), 1e-6f)
        // Bounding-box corner lies outside the ellipse, so the old rectangle is no longer covered.
        assertEquals(0f, SubjectMask.alpha(0.5f + 0.1f * 0.95f, 0.5f + 0.15f * 0.95f, null, listOf(face), fit), 1e-6f)
        // Just inside the rim is still covered; the feather ends at the iOS 0.5 radius.
        assertTrue(SubjectMask.alpha(0.5f + 0.1f * 0.8f, 0.5f, null, listOf(face), fit) > 0.99f)
    }

    @Test fun personMaskUsesLetterboxCoordinates() {
        // 1280×720 letterbox: display y in [0.21875, 0.78125] maps to the analysis band.
        val size = 320
        val alpha = ByteArray(size * size) { index -> if (index / size < size / 2) 0xFF.toByte() else 0 }
        val person = PersonMask(size, alpha)
        val fit = SubjectMask.letterboxFit(1280, 720)
        assertEquals(1f, SubjectMask.alpha(0.5f, 0.1f, person, emptyList(), fit), 1e-6f)
        assertEquals(0f, SubjectMask.alpha(0.5f, 0.9f, person, emptyList(), fit), 1e-6f)
    }

    @Test fun dilationGrowsBinaryMaskByRadius() {
        val size = 16
        val binary = ByteArray(size * size)
        binary[8 * size + 8] = 0xFF.toByte()
        val grown = PersonMask.dilated(size, binary, radius = 2).alpha
        var count = 0
        for (y in 0 until size) for (x in 0 until size) if (grown[y * size + x].toInt() != 0) count++
        assertEquals(25, count)
    }

    @Test fun sampleIsBilinearAndClamped() {
        val size = 2
        val alpha = byteArrayOf(0, 0xFF.toByte(), 0, 0xFF.toByte())
        val mask = PersonMask(size, alpha)
        assertEquals(0.5f, mask.sample(0.5f, 0.25f), 1e-6f)
        assertEquals(1f, mask.sample(1.2f, 0.5f), 1e-6f)
    }

    @Test fun cellSizeFollowsIosDefaultAt720p() {
        assertEquals(24, SubjectMask.cellSize(1280, 720))
        assertEquals(24, SubjectMask.cellSize(720, 1280))
        assertEquals(8, SubjectMask.cellSize(320, 240))
        assertEquals(51, SubjectMask.cellSize(2048, 1536))
    }

    @Test fun smoothstepHitsEndpoints() {
        assertEquals(0f, SubjectMask.smoothstep(0.35f, 0.65f, 0.2f), 1e-6f)
        assertEquals(0.5f, SubjectMask.smoothstep(0.35f, 0.65f, 0.5f), 1e-6f)
        assertEquals(1f, SubjectMask.smoothstep(0.35f, 0.65f, 0.9f), 1e-6f)
    }
}
