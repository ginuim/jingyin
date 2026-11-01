package com.reaidea.lenshide.prototype

import android.content.ContentValues
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Bundle
import android.provider.MediaStore
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.lifecycleScope
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.Presentation
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import kotlinx.coroutines.*
import java.io.File
import kotlin.math.ceil

@UnstableApi
class MainActivity : ComponentActivity() {
    private var running: Job? = null
    private var outputFile: File? = null
    private var outputBitmap: Bitmap? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        cacheDir.listFiles()?.filter { it.name.startsWith("lenshide-") }?.forEach(File::delete)
        setContent { MaterialTheme { Lab() } }
    }

    @Composable private fun Lab() {
        var uri by remember { mutableStateOf<Uri?>(null) }
        var isVideo by remember { mutableStateOf(false) }
        var busy by remember { mutableStateOf(false) }
        var mute by remember { mutableStateOf(false) }
        var photo by remember { mutableStateOf<Bitmap?>(null) }
        var play by remember { mutableStateOf<Pair<Uri, Boolean>?>(null) }
        var progress by remember { mutableIntStateOf(0) }
        var report by remember { mutableStateOf("") }
        val device = remember { DeviceCapabilities.describe(this) }
        val pick = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { selected ->
            if (selected != null) {
                isVideo = contentResolver.getType(selected)?.startsWith("video/") == true
                play = null; photo = null
                outputFile?.delete(); outputFile = null
                outputBitmap?.recycle(); outputBitmap = null
                uri = selected
                report = ""
            }
        }
        fun launchJob(block: suspend () -> Unit) {
            busy = true; progress = 0; play = null; report = ""
            running = lifecycleScope.launch {
                try { block() }
                catch (_: CancellationException) { report = getString(R.string.cancelled) }
                catch (error: Exception) { report = getString(R.string.failed) + "\n" + (error.message ?: error.javaClass.simpleName) }
                finally { busy = false }
            }
        }
        Surface(Modifier.fillMaxSize()) {
            Column(Modifier.safeDrawingPadding().verticalScroll(rememberScrollState()).padding(20.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(stringResource(R.string.app_name), style = MaterialTheme.typography.headlineMedium)
                Text(stringResource(R.string.lab_notice))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(enabled = !busy, onClick = { pick.launch("image/*") }) { Text(stringResource(R.string.pick_photo)) }
                    Button(enabled = !busy, onClick = { pick.launch("video/*") }) { Text(stringResource(R.string.pick_video)) }
                }
                if (uri != null && isVideo) {
                    Row { Checkbox(mute, { mute = it }, enabled = !busy); Text(stringResource(R.string.mute)) }
                    Button(enabled = !busy, onClick = { play = uri!! to true }) { Text(stringResource(R.string.preview)) }
                    Button(enabled = !busy, onClick = {
                        launchJob {
                            outputFile?.delete(); outputFile = null
                            val result = VideoExporter(this@MainActivity).export(uri!!, mute) { progress = it }
                            outputFile = result.file
                            report = result.report
                            play = Uri.fromFile(result.file) to false
                        }
                    }) { Text(stringResource(R.string.export_video)) }
                } else if (uri != null) {
                    Button(enabled = !busy, onClick = {
                        launchJob {
                            val selected = uri!!
                            val result = withContext(Dispatchers.Default) {
                                val source = decodePhoto(selected)
                                try {
                                    FaceDetector(this@MainActivity).use { detector ->
                                        repeat(3) { ensureActive(); detector.detect(source) }
                                        val samples = mutableListOf<Double>()
                                        var latest = Detection(emptyList(), 0.0)
                                        repeat(20) { ensureActive(); latest = detector.detect(source); samples += latest.millis }
                                        ensureActive()
                                        val masked = FaceDetector.pixelate(source, latest.faces)
                                        val sorted = samples.sorted()
                                        masked to "faces=${latest.faces.size}, samples=20, input=320, threads=2\ninferenceMedianMs=%.2f, p95Ms=%.2f, maxMs=%.2f".format(sorted[10], sorted[18], sorted.last())
                                    }
                                } finally { source.recycle() }
                            }
                            photo = null
                            outputBitmap?.recycle(); outputBitmap = result.first
                            photo = result.first; report = result.second
                        }
                    }) { Text(stringResource(R.string.benchmark_photo)) }
                }
                if (busy) {
                    LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                    Text("$progress%")
                    Button(onClick = { running?.cancel() }) { Text(stringResource(R.string.cancel)) }
                }
                photo?.let { Image(it.asImageBitmap(), stringResource(R.string.result), Modifier.fillMaxWidth().heightIn(max = 420.dp)) }
                play?.let { (source, applyEffect) -> VideoPreview(source, applyEffect, mute) }
                if (!busy && (outputFile != null || photo != null)) {
                    Button(onClick = {
                        launchJob {
                            withContext(Dispatchers.IO) { saveOutput() }
                            report = getString(R.string.saved)
                        }
                    }) { Text(stringResource(R.string.save)) }
                }
                if (report.isNotEmpty()) Text(report, style = MaterialTheme.typography.bodySmall)
                HorizontalDivider()
                Text(stringResource(R.string.device), style = MaterialTheme.typography.titleMedium)
                Text(device, style = MaterialTheme.typography.bodySmall)
            }
        }
    }

    @Composable private fun VideoPreview(uri: Uri, applyEffect: Boolean, mute: Boolean) {
        val player = remember(uri, applyEffect) {
            ExoPlayer.Builder(this).build().apply {
                if (applyEffect) setVideoEffects(listOf(Presentation.createForHeight(720), FacePixelEffect(FrameMetrics())))
                setMediaItem(MediaItem.fromUri(uri))
                repeatMode = ExoPlayer.REPEAT_MODE_ONE
                prepare()
            }
        }
        LaunchedEffect(mute) { player.volume = if (mute) 0f else 1f }
        DisposableEffect(player) { onDispose { player.release() } }
        AndroidView(factory = { PlayerView(it).apply { this.player = player } },
            update = { it.player = player }, modifier = Modifier.fillMaxWidth().height(260.dp))
    }

    private fun decodePhoto(uri: Uri): Bitmap = ImageDecoder.decodeBitmap(ImageDecoder.createSource(contentResolver, uri)) { decoder, info, _ ->
        decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
        decoder.setTargetSampleSize(ceil(maxOf(info.size.width, info.size.height) / 2048.0).toInt().coerceAtLeast(1))
    }

    private fun saveOutput() {
        val video = outputFile
        val isVideo = video != null
        val collection = if (isVideo) MediaStore.Video.Media.EXTERNAL_CONTENT_URI else MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, "LensHide-${System.currentTimeMillis()}.${if (isVideo) "mp4" else "jpg"}")
            put(MediaStore.MediaColumns.MIME_TYPE, if (isVideo) "video/mp4" else "image/jpeg")
            put(MediaStore.MediaColumns.RELATIVE_PATH, if (isVideo) "Movies/LensHide" else "Pictures/LensHide")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val destination = checkNotNull(contentResolver.insert(collection, values))
        try {
            checkNotNull(contentResolver.openOutputStream(destination)).use { stream ->
                if (video != null) video.inputStream().use { it.copyTo(stream) }
                else check(checkNotNull(outputBitmap).compress(Bitmap.CompressFormat.JPEG, 95, stream))
            }
            contentResolver.update(destination, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
        } catch (error: Exception) { contentResolver.delete(destination, null, null); throw error }
    }

    override fun onStop() {
        // No background-processing promise in this lab. Cancel when leaving the screen.
        running?.cancel()
        super.onStop()
    }

    override fun onDestroy() {
        running?.cancel()
        outputFile?.delete()
        outputBitmap?.recycle()
        super.onDestroy()
    }
}
