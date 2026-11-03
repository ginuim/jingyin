package com.reaidea.lenshide.prototype

import org.junit.Assert.*
import org.junit.Test

class EditorMasksTest {
    @Test fun tapTogglesFaceAndRemovesManualMask() {
        val face = PhotoFace(7, FaceBox(0.2f, 0.2f, 0.1f, 0.1f))
        val faces = listOf(face)
        val revealed = MaskEdits().tap(0.2f, 0.2f, faces, 0.1f, 0.1f)
        assertTrue(revealed.masks(faces).isEmpty())
        val covered = revealed.tap(0.2f, 0.2f, faces, 0.1f, 0.1f)
        assertEquals(listOf(face.box), covered.masks(faces))
        val manual = covered.tap(0.7f, 0.6f, faces, 0.1f, 0.1f)
        assertEquals(2, manual.masks(faces).size)
        assertEquals(covered, manual.tap(0.7f, 0.6f, faces, 0.1f, 0.1f))
    }

    @Test fun lookupUsesLatestRenderedFrame() {
        val face = FaceBox(0.4f, 0.5f, 0.1f, 0.1f)
        val timeline = listOf(MaskFrame(0, emptyList()), MaskFrame(50_000, listOf(face)), MaskFrame(90_000, emptyList()))
        assertTrue(timeline.facesAt(49_999).isEmpty())
        assertEquals(listOf(face), timeline.facesAt(75_000))
        assertTrue(timeline.facesAt(90_000).isEmpty())
    }
}
