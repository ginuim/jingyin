package com.reaidea.lenshide.prototype

import org.junit.Assert.*
import org.junit.Test

class EditorMasksTest {
    private val face = PhotoFace(7, FaceBox(0.2f, 0.2f, 0.1f, 0.1f))
    private val faces = listOf(face)

    @Test fun automaticMaskStaysVisibleWhenSelectedAndUsesAdjustedGeometry() {
        val edits = MaskEdits()
        val selected = checkNotNull(edits.hitTest(0.2f, 0.2f, faces))
        assertEquals(MaskSelection.Automatic(face.id), selected)
        assertEquals(listOf(face.box), edits.masks(faces))

        val bigger = face.box.copy(rx = 0.2f, ry = 0.2f)
        val resized = edits.transform(selected, bigger)
        assertEquals(listOf(bigger), resized.masks(faces))
        assertEquals(selected, resized.hitTest(0.35f, 0.2f, faces))
        val removed = resized.remove(selected)
        assertTrue(removed.masks(faces).isEmpty())
        assertNull(removed.hitTest(0.2f, 0.2f, faces))
    }

    @Test fun manualMaskAboveAutomaticMaskCanBeResizedAndRemovedIndependently() {
        val manual = face.box.copy(rx = 0.05f, ry = 0.05f)
        val edits = MaskEdits(manual = listOf(manual))
        val selected = checkNotNull(edits.hitTest(0.2f, 0.2f, faces))
        assertEquals(MaskSelection.Manual(0), selected)
        val bigger = manual.copy(rx = 0.15f, ry = 0.15f)
        val resized = edits.transform(selected, bigger)
        assertEquals(listOf(face.box, bigger), resized.masks(faces))
        assertEquals(listOf(face.box), resized.remove(selected).masks(faces))
    }
    @Test fun movedMaskIsSelectableAtItsNewLocation() {
        val selection = MaskSelection.Automatic(face.id)
        val moved = face.box.copy(cx = 0.6f, cy = 0.7f)
        val edits = MaskEdits().transform(selection, moved)
        assertNull(edits.hitTest(face.box.cx, face.box.cy, faces))
        assertEquals(selection, edits.hitTest(moved.cx, moved.cy, faces))
        assertEquals(listOf(moved), edits.masks(faces))
    }
}
