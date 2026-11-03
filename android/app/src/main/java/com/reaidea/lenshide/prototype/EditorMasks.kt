package com.reaidea.lenshide.prototype

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Rect
import android.graphics.RectF
import kotlin.math.min

internal enum class MaskStyle { Mosaic, Blur, Sticker }
enum class EditorAudio { Original, Mute, Voice }

internal data class MaskEdits(
    val revealed: Set<Int> = emptySet(),
    val manual: List<FaceBox> = emptyList(),
) {
    fun tap(x: Float, y: Float, faces: List<PhotoFace>, radiusX: Float, radiusY: Float): MaskEdits {
        val manualIndex = manual.indexOfLast { it.contains(x, y) }
        if (manualIndex >= 0) return copy(manual = manual.filterIndexed { index, _ -> index != manualIndex })
        val face = faces.lastOrNull { it.box.contains(x, y) }
        if (face != null) {
            return copy(revealed = if (face.id in revealed) revealed - face.id else revealed + face.id)
        }
        if (manual.size >= 32) return this
        return copy(manual = manual + FaceBox(x, y, radiusX, radiusY))
    }

    fun masks(faces: List<PhotoFace>) = faces.filter { it.id !in revealed }.map { it.box } + manual
}

internal fun FaceBox.contains(x: Float, y: Float) =
    kotlin.math.abs(x - cx) <= rx && kotlin.math.abs(y - cy) <= ry

internal data class PhotoFace(val id: Int, val box: FaceBox)
internal val stickers = listOf(
    "😎", "🥸", "🤡", "👽", "👻", "🤖", "🙈", "😺",
    "😍", "🤩", "🤠", "🥳", "😈", "🎃", "🐼", "🐸",
    "😊", "😉", "😂", "🤔", "🤫", "🤐", "🤯", "😱",
    "😡", "💀", "💩", "🐶", "🦊", "🐯", "🦁", "🐻",
)

internal fun stickerBitmap(emoji: String): Bitmap {
    val bitmap = Bitmap.createBitmap(256, 256, Bitmap.Config.ARGB_8888)
    val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { textSize = 218f; textAlign = Paint.Align.CENTER }
    Canvas(bitmap).drawText(emoji, 128f, 128f - (paint.ascent() + paint.descent()) / 2, paint)
    return bitmap
}

internal fun renderEditorPhoto(
    source: Bitmap, masks: List<FaceBox>, style: MaskStyle, emoji: String,
    overrides: Map<FaceBox, String> = emptyMap(),
): Bitmap {
    if (style == MaskStyle.Mosaic) {
        return PhotoMasking.render(source, Detection(masks, null, 0.0))
    }
    val output = source.copy(Bitmap.Config.ARGB_8888, true)
    val canvas = Canvas(output)
    val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
    val w = source.width
    val h = source.height
    val effect = if (style == MaskStyle.Blur) softBlur(source) else null
    val renderedStickers = mutableMapOf<String, Bitmap>()
    try {
        for (mask in masks) {
            val rect = RectF((mask.cx - mask.rx) * w, (mask.cy - mask.ry) * h, (mask.cx + mask.rx) * w, (mask.cy + mask.ry) * h)
            when (style) {
                MaskStyle.Mosaic -> error("Mosaic is rendered by PhotoMasking")
                MaskStyle.Blur -> {
                    canvas.save()
                    canvas.clipPath(Path().apply { addOval(rect, Path.Direction.CW) })
                    canvas.drawBitmap(checkNotNull(effect), null, Rect(0, 0, w, h), paint)
                    canvas.restore()
                }
                MaskStyle.Sticker -> {
                    val radius = min(rect.width(), rect.height()) / 2
                    val symbol = overrides[mask] ?: emoji
                    val sticker = renderedStickers.getOrPut(symbol) { stickerBitmap(symbol) }
                    canvas.drawBitmap(sticker, null,
                        RectF(rect.centerX() - radius, rect.centerY() - radius, rect.centerX() + radius, rect.centerY() + radius), paint)
                }
            }
        }
        return output
    } finally {
        if (effect !== source) effect?.recycle()
        renderedStickers.values.forEach(Bitmap::recycle)
    }
}

private fun softBlur(source: Bitmap): Bitmap {
    val scale = (120f / min(source.width, source.height)).coerceAtMost(1f)
    val w = (source.width * scale).toInt().coerceAtLeast(1)
    val h = (source.height * scale).toInt().coerceAtLeast(1)
    val reduced = Bitmap.createScaledBitmap(source, w, h, true)
    val pixels = IntArray(w * h)
    try { reduced.getPixels(pixels, 0, w, 0, 0, w, h) }
    finally { if (reduced !== source) reduced.recycle() }
    val horizontal = IntArray(pixels.size)
    val result = IntArray(pixels.size)
    val radius = (min(w, h) / 40).coerceAtLeast(1)
    for (y in 0 until h) for (x in 0 until w) {
        horizontal[y * w + x] = average(radius) { pixels[y * w + (x + it).coerceIn(0, w - 1)] }
    }
    for (y in 0 until h) for (x in 0 until w) {
        result[y * w + x] = average(radius) { horizontal[(y + it).coerceIn(0, h - 1) * w + x] }
    }
    return Bitmap.createBitmap(result, w, h, Bitmap.Config.ARGB_8888)
}

private inline fun average(radius: Int, pixel: (Int) -> Int): Int {
    var r = 0
    var g = 0
    var b = 0
    for (offset in -radius..radius) {
        val color = pixel(offset)
        r += color ushr 16 and 255
        g += color ushr 8 and 255
        b += color and 255
    }
    val count = radius * 2 + 1
    return (255 shl 24) or ((r / count) shl 16) or ((g / count) shl 8) or (b / count)
}

internal data class VideoMaskOptions(
    val style: MaskStyle,
    val sticker: String,
    val manual: List<FaceBox>,
)
