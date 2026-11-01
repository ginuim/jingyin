package com.reaidea.lenshide.prototype

import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.media3.common.MediaItem
import androidx.media3.common.Metadata
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.Presentation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.DefaultMuxer
import androidx.media3.muxer.Muxer
import com.google.common.collect.ImmutableList
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import java.io.File
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

data class VideoExport(val file: File, val report: String)

/** AutoCloseable was added after Android 9; release() works on both old and current devices. */
internal inline fun <T> MediaMetadataRetriever.useRetriever(block: (MediaMetadataRetriever) -> T): T =
    try { block(this) } finally { release() }

/** Lab has no purchase entitlement. Processor itself enforces the free 30s / 720p boundary. */
@UnstableApi
class VideoExporter(private val context: Context) {
    suspend fun export(uri: Uri, mute: Boolean, progress: (Int) -> Unit): VideoExport {
        withContext(Dispatchers.IO) {
            MediaMetadataRetriever().useRetriever { retriever ->
                retriever.setDataSource(context, uri)
                val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
                require(duration != null && duration in 1..300_000) { "INPUT_DURATION_LIMIT_5_MINUTES" }
                val transfer = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_COLOR_TRANSFER)?.toIntOrNull()
                require(transfer != 6 && transfer != 7) { context.getString(R.string.sdr_only) }
            }
        }
        return withContext(Dispatchers.Main) {
            val metrics = FrameMetrics()
            val output = File.createTempFile("lenshide-", ".mp4", context.cacheDir)
            output.delete() // Transformer creates its own output.
            val start = SystemClock.elapsedRealtime()
            val parentScope = kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.currentCoroutineContext())
            suspendCancellableCoroutine { continuation ->
                val item = MediaItem.Builder().setUri(uri)
                    .setClippingConfiguration(MediaItem.ClippingConfiguration.Builder().setEndPositionMs(30_000).build())
                    .build()
                val edited = EditedMediaItem.Builder(item)
                    .setRemoveAudio(mute)
                    .setFrameRate(30)
                    .setEffects(Effects(emptyList(), listOf(
                        Presentation.createForHeight(720), FacePixelEffect(metrics))))
                    .build()
                var poll: kotlinx.coroutines.Job? = null
                val transformer = Transformer.Builder(context)
                    .setMuxerFactory(PrivacyMuxerFactory())
                    .setVideoMimeType(MimeTypes.VIDEO_H264)
                    .setAudioMimeType(MimeTypes.AUDIO_AAC)
                    .addListener(object : Transformer.Listener {
                        override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                            poll?.cancel()
                            val seconds = (SystemClock.elapsedRealtime() - start) / 1000.0
                            val report = "wallSeconds=%.2f, durationMs=${exportResult.durationMs}, size=${exportResult.fileSizeBytes}\nvideoEncoder=${exportResult.videoEncoderName}\naudioEncoder=${exportResult.audioEncoderName}\n${metrics.snapshot()}".format(seconds)
                            if (continuation.isActive) continuation.resume(VideoExport(output, report))
                            else output.delete()
                        }
                        override fun onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) {
                            poll?.cancel(); output.delete()
                            if (continuation.isActive) continuation.resumeWithException(exportException)
                        }
                    }).build()
                continuation.invokeOnCancellation {
                    Handler(Looper.getMainLooper()).post {
                        poll?.cancel(); transformer.cancel(); output.delete()
                    }
                }
                try {
                    transformer.start(edited, output.path)
                    poll = parentScope.launch {
                        val holder = ProgressHolder()
                        while (true) {
                            if (transformer.getProgress(holder) == Transformer.PROGRESS_STATE_AVAILABLE) progress(holder.progress)
                            delay(250)
                        }
                    }
                } catch (error: Exception) {
                    poll?.cancel(); transformer.cancel(); output.delete()
                    if (continuation.isActive) continuation.resumeWithException(error)
                }
            }
        }
    }
}

/** Never copy source GPS, capture dates, device tags or other source metadata to a new file. */
@UnstableApi
private class PrivacyMuxerFactory : Muxer.Factory {
    private val factory = DefaultMuxer.Factory()
    override fun create(path: String): Muxer {
        val underlying = factory.create(path)
        return object : Muxer by underlying {
            override fun addMetadataEntry(metadataEntry: Metadata.Entry) { /* intentionally dropped */ }
            override fun addTrack(format: Format): Muxer.TrackToken =
                underlying.addTrack(format.buildUpon().setMetadata(null).build())
        }
    }
    override fun getSupportedSampleMimeTypes(trackType: Int): ImmutableList<String> =
        factory.getSupportedSampleMimeTypes(trackType)
}
