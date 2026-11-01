package com.reaidea.lenshide.prototype

import android.graphics.BitmapFactory
import android.graphics.Color
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.util.Log
import androidx.media3.common.util.UnstableApi
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@UnstableApi
@RunWith(AndroidJUnit4::class)
class PipelineTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private fun fixture(name: String): File = File(context.cacheDir, "fixture-$name").also { file ->
        instrumentation.context.assets.open(name).use { source -> file.outputStream().use(source::copyTo) }
    }
    private fun report(name: String, value: String) {
        Log.i("LensHideBenchmark", "$name\n$value")
        File(context.filesDir, "lab-results.txt").appendText("$name\n$value\n\n")
    }

    @Test fun photoDetectionAndMasking() {
        val file = fixture("face.jpg")
        val bitmap = BitmapFactory.decodeFile(file.path)
        try {
            report("device", DeviceCapabilities.describe(context))
            for (size in listOf(320, 640)) {
                FaceDetector(context, size).use { detector ->
                    repeat(3) { detector.detect(bitmap) }
                    val detections = (1..20).map { detector.detect(bitmap) }
                    val times = detections.map { it.millis }.sorted()
                    val faces = detections.last().faces
                    assertTrue("No faces detected at $size", faces.isNotEmpty())
                    assertTrue(faces.all { it.x >= 0 && it.y >= 0 && it.x + it.width <= 1.0001 && it.y + it.height <= 1.0001 })
                    val masked = FaceDetector.pixelate(bitmap, faces)
                    try {
                        // Actual pixels must change inside each detected region.
                        faces.forEach { face ->
                            var changed = 0
                            for (i in 1..9) for (j in 1..9) {
                                val x = ((face.x + face.width * i / 10) * bitmap.width).toInt().coerceIn(0, bitmap.width - 1)
                                val y = ((face.y + face.height * j / 10) * bitmap.height).toInt().coerceIn(0, bitmap.height - 1)
                                if (bitmap.getPixel(x, y) != masked.getPixel(x, y)) changed++
                            }
                            assertTrue("Mask did not modify face pixels", changed > 0)
                        }
                        report("photo-$size", "visibleFaces=8, detected=${faces.size}, samples=20, medianMs=${times[10]}, p95Ms=${times[18]}, maxMs=${times.last()}")
                        if (size == 320) File(context.filesDir, "masked-photo.jpg").outputStream().use { masked.compress(android.graphics.Bitmap.CompressFormat.JPEG, 95, it) }
                    } finally { masked.recycle() }
                }
            }
        } finally { bitmap.recycle(); file.delete() }
    }

    @Test fun shortVideoExportAndPixelAlignment() = runBlocking<Unit> {
        val input = fixture("short.mp4")
        try {
            val exported = withTimeout(120_000) { VideoExporter(context).export(Uri.fromFile(input), true) {} }
            try {
                report("video-short", exported.report)
                assertTrue(exported.file.length() > 0)
                MediaMetadataRetriever().useRetriever { output ->
                    output.setDataSource(exported.file.path)
                    val duration = output.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)!!.toLong()
                    assertTrue(duration in 1500..2200)
                    assertEquals("720", output.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT))
                    assertNull(output.extractMetadata(MediaMetadataRetriever.METADATA_KEY_LOCATION))
                    assertNull(output.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO))
                    val frame = checkNotNull(output.getFrameAtTime(500_000))
                    try {
                        File(context.filesDir, "masked-video-frame.jpg").outputStream().use { frame.compress(android.graphics.Bitmap.CompressFormat.JPEG, 95, it) }
                        // Readback must not result in a completely black/empty frame.
                        assertTrue(Color.red(frame.getPixel(frame.width / 2, frame.height / 2)) > 5)
                    } finally { frame.recycle() }
                }
                File(context.filesDir, "masked-short.mp4").outputStream().use { stream -> exported.file.inputStream().use { it.copyTo(stream) } }
            } finally { exported.file.delete() }
        } finally { input.delete() }
    }

    @Test fun cancelFailureAndRetry() = runBlocking<Unit> {
        val source = fixture("short.mp4")
        val before = context.cacheDir.listFiles()!!.filter { it.name.startsWith("lenshide-") }.map { it.name }.toSet()
        try {
            val task = launch { VideoExporter(context).export(Uri.fromFile(source), false) {}.file.delete() }
            delay(300)
            val start = android.os.SystemClock.elapsedRealtime()
            task.cancelAndJoin()
            // Cancellation is posted to Media3's application looper. Drain it before checking cleanup.
            withContext(Dispatchers.Main) { }
            val remaining = context.cacheDir.listFiles()!!.filter { it.name.startsWith("lenshide-") }.map { it.name }.toSet()
            assertEquals(before, remaining)
            report("cancel", "cancelWaitMs=${android.os.SystemClock.elapsedRealtime() - start}, leftoverFiles=${remaining.size - before.size}")
            val invalid = File(context.cacheDir, "invalid.mp4").apply { writeText("invalid") }
            try {
                var failed = false
                try { VideoExporter(context).export(Uri.fromFile(invalid), false) {} }
                catch (_: Exception) { failed = true }
                assertTrue("Invalid input unexpectedly succeeded", failed)
            } finally { invalid.delete() }
            val retried = withTimeout(120_000) { VideoExporter(context).export(Uri.fromFile(source), false) {} }
            report("retry", retried.report)
            assertTrue(retried.file.length() > 0)
            retried.file.delete()
        } finally { source.delete() }
    }

    @Test fun rotatedSourceRetainsDisplayAndMasks() = runBlocking<Unit> {
        val source = fixture("rotated.mp4")
        try {
            MediaMetadataRetriever().useRetriever { input ->
                input.setDataSource(source.path)
                val rotation = input.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toInt()
                assertTrue("Fixture must have a 90 degree display matrix", rotation == 90 || rotation == 270)
            }
            val result = withTimeout(120_000) { VideoExporter(context).export(Uri.fromFile(source), true) {} }
            try {
                report("rotated-source", result.report)
                val faceCount = Regex("faces=(\\d+)").find(result.report)!!.groupValues[1].toInt()
                assertTrue("Rotated source detected no faces", faceCount > 0)
                MediaMetadataRetriever().useRetriever { output ->
                    output.setDataSource(result.file.path)
                    val rotation = output.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toInt() ?: 0
                    val encodedW = output.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)!!.toInt()
                    val encodedH = output.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)!!.toInt()
                    val w = if (rotation % 180 == 0) encodedW else encodedH
                    val h = if (rotation % 180 == 0) encodedH else encodedW
                    assertTrue("Display orientation changed", w > h)
                    result.file.copyTo(File(context.filesDir, "masked-rotated.mp4"), overwrite = true)
                }
            } finally { result.file.delete() }
        } finally { source.delete() }
    }
}
