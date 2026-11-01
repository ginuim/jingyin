package com.reaidea.lenshide.prototype

import android.media.MediaMetadataRetriever
import android.net.Uri
import android.util.Log
import androidx.media3.common.util.UnstableApi
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

@UnstableApi
@RunWith(AndroidJUnit4::class)
class MatrixTest {
    @Test fun inputDurationOrientationAudioAndPrivacyMatrix() = runBlocking<Unit> {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val report = File(context.filesDir, "matrix-results.txt")
        report.writeText("All exports use the free processor path: first 30 seconds, <=720p. No full 1m/3m export or voice pitch claim.\n")
        for (duration in listOf(30, 60, 180)) {
            val source = File(context.cacheDir, "matrix-source-$duration.mp4")
            instrumentation.context.assets.open("matrix-$duration.mp4").use { input -> source.outputStream().use(input::copyTo) }
            try {
                // FFmpeg stores these coordinates in a binary 'loci' atom, which this Android
                // retriever does not expose. Parse atom headers instead of relying on null.
                assertTrue("Fixture must contain a location atom", hasLocationAtom(source))
                var captureDate: String? = null
                MediaMetadataRetriever().useRetriever { original ->
                    original.setDataSource(source.path)
                    assertNotNull(original.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO))
                    captureDate = original.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DATE)
                }
                for (mute in listOf(false, true)) {
                    val result = withTimeout(180_000) { VideoExporter(context).export(Uri.fromFile(source), mute) {} }
                    try {
                        MediaMetadataRetriever().useRetriever { output ->
                            output.setDataSource(result.file.path)
                            val ms = output.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)!!.toLong()
                            assertTrue("Free clip duration $ms", ms in 29_500..30_100)
                            val encodedWidth = output.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)!!.toInt()
                            val encodedHeight = output.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)!!.toInt()
                            val rotation = output.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toInt() ?: 0
                            val width = if (rotation % 180 == 0) encodedWidth else encodedHeight
                            val height = if (rotation % 180 == 0) encodedHeight else encodedWidth
                            assertTrue(maxOf(width, height) <= 1280 && minOf(width, height) <= 720)
                            if (duration == 60) assertTrue("Portrait orientation lost", height > width)
                            else assertTrue("Landscape orientation lost", width > height)
                            assertNull(output.extractMetadata(MediaMetadataRetriever.METADATA_KEY_LOCATION))
                            assertFalse("Source location atom retained", hasLocationAtom(result.file))
                            captureDate?.let { assertNotEquals("Source capture date retained", it, output.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DATE)) }
                            val audio = output.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO)
                            if (mute) assertNull(audio) else assertNotNull(audio)
                            val line = "sourceSeconds=$duration, mute=$mute, displayed=${width}x$height, encoded=${encodedWidth}x$encodedHeight, rotation=$rotation, durationMs=$ms\n${result.report}\n"
                            report.appendText(line)
                            Log.i("LensHideBenchmark", line)
                            if (duration == 60 && !mute) {
                                result.file.copyTo(File(context.filesDir, "masked-portrait.mp4"), overwrite = true)
                            }
                        }
                    } finally { result.file.delete() }
                }
            } finally { source.delete() }
        }
    }

    private fun hasLocationAtom(file: File): Boolean {
        val bytes = file.readBytes()
        val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.BIG_ENDIAN)
        fun scan(start: Int, end: Int): Boolean {
            var offset = start
            while (offset + 8 <= end) {
                val basicSize = buffer.getInt(offset).toLong() and 0xffffffffL
                val type = String(bytes, offset + 4, 4, Charsets.ISO_8859_1)
                val header = if (basicSize == 1L) 16 else 8
                if (offset + header > end) return false
                val size = when (basicSize) {
                    0L -> (end - offset).toLong()
                    1L -> buffer.getLong(offset + 8)
                    else -> basicSize
                }
                if (size < header || size > end - offset) return false
                if (type == "loci" || type == "\u00a9xyz") return true
                if ((type == "moov" || type == "udta") && scan(offset + header, offset + size.toInt())) return true
                offset += size.toInt()
            }
            return false
        }
        return scan(0, bytes.size)
    }
}
