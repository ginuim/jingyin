package com.reaidea.lenshide.prototype

import android.content.ClipData
import android.content.ContentValues
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Bundle
import android.provider.MediaStore
import android.view.LayoutInflater
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.FileProvider
import androidx.core.view.WindowCompat
import androidx.lifecycle.lifecycleScope
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import kotlinx.coroutines.*
import java.io.File
import kotlin.math.ceil

private val coral = Color(0xFFE87A64)
private val paper = Color(0xFFFFFBF9)
private val pink = Color(0xFFF7E8E3)
private val ink = Color(0xFF2D221E)
private val brown = Color(0xFF6E473B)
private val mutedInk = Color(0xFF7A655E)
private val pill = RoundedCornerShape(50)
private const val batchLimit = 20

private data class PhotoDraft(
    val uri: Uri,
    val faces: List<PhotoFace>? = null,
    val edits: MaskEdits = MaskEdits(),
)

private data class VideoDraft(val uri: Uri, val edits: MaskEdits = MaskEdits())

@UnstableApi
class MainActivity : ComponentActivity() {
    private var running: Job? = null
    private var resumePlayback = false
    private var visiblePlayer: ExoPlayer? = null
    private val shareDirectory get() = File(cacheDir, "editor-share")

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.getInsetsController(window, window.decorView).apply {
            isAppearanceLightStatusBars = true
            isAppearanceLightNavigationBars = true
        }
        cacheDir.listFiles()?.filter { it.name.startsWith("lenshide-") }?.forEach(File::delete)
        shareDirectory.listFiles()?.filter { System.currentTimeMillis() - it.lastModified() > 86_400_000 }?.forEach(File::delete)
        setContent {
            MaterialTheme(colorScheme = lightColorScheme(primary = coral, onPrimary = Color.White,
                surface = paper, onSurface = ink, secondaryContainer = pink, onSecondaryContainer = brown)) {
                Editor()
            }
        }
    }

    @Composable
    private fun Editor() {
        var photos by remember { mutableStateOf(emptyList<PhotoDraft>()) }
        var photoIndex by remember { mutableIntStateOf(0) }
        var video by remember { mutableStateOf<VideoDraft?>(null) }
        val isVideo = video != null
        val hasProject = isVideo || photos.isNotEmpty()
        var style by remember { mutableStateOf(MaskStyle.Mosaic) }
        var emojiIndex by remember { mutableIntStateOf(0) }
        var audio by remember { mutableStateOf(EditorAudio.Original) }
        var failedExports by remember { mutableStateOf(emptySet<Uri>()) }
        var batchResult by remember { mutableStateOf<Pair<Int, Int>?>(null) }
        var analyzeBatch by remember { mutableStateOf(false) }
        var photo by remember { mutableStateOf<Bitmap?>(null) }
        var videoPreview by remember { mutableStateOf<File?>(null) }
        var videoOutput by remember { mutableStateOf<File?>(null) }
        var frameMasks by remember { mutableStateOf(emptyList<MaskFrame>()) }
        var player by remember { mutableStateOf<ExoPlayer?>(null) }
        var playing by remember { mutableStateOf(true) }
        var position by remember { mutableLongStateOf(0L) }
        var duration by remember { mutableLongStateOf(0L) }
        var busy by remember { mutableStateOf(false) }
        var progress by remember { mutableIntStateOf(0) }
        var renderRevision by remember { mutableIntStateOf(0) }
        var saving by remember { mutableStateOf(false) }
        var savedFeedback by remember { mutableStateOf(false) }
        var failed by remember { mutableStateOf(false) }
        var feedback by remember { mutableStateOf("") }
        var feedbackRevision by remember { mutableIntStateOf(0) }
        var rippleAt by remember { mutableStateOf<Offset?>(null) }
        var reveal by remember { mutableStateOf<FaceBox?>(null) }
        var rippleRevision by remember { mutableIntStateOf(0) }
        val ripple = remember { Animatable(1f) }
        val draft = photos.getOrNull(photoIndex)
        var seekPosition by remember { mutableStateOf<Float?>(null) }
        val emoji = stickers[emojiIndex]
        val secondary = ButtonDefaults.buttonColors(containerColor = pink, contentColor = brown)
        fun notify(message: String) {
            feedback = message
            feedbackRevision++
        }
        fun updatePhoto(replacement: PhotoDraft) {
            photos = photos.map { if (it.uri == replacement.uri) replacement else it }
        }
        fun closeProject() {
            photos = emptyList()
            photoIndex = 0
            video = null
            frameMasks = emptyList()
            photo = null
            videoPreview = null
            videoOutput = null
            seekPosition = null
            failedExports = emptySet()
            batchResult = null
            analyzeBatch = false
            feedback = ""
            reveal = null
            rippleAt = null
            failed = false
        }
        BackHandler(hasProject) {
            if (busy) running?.cancel() else closeProject()
        }
        fun rerender() {
            failed = false
            renderRevision++
        }
        fun startWork(block: suspend () -> Unit) {
            if (busy) return
            busy = true
            progress = 0
            running = lifecycleScope.launch {
                try { block() }
                catch (_: CancellationException) { notify(getString(R.string.cancelled)) }
                catch (error: Exception) {
                    android.util.Log.e("TapHide", "Media operation failed", error)
                    notify(getString(R.string.failed))
                }
                finally { busy = false; saving = false }
            }
        }

        val pickPhotos = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(batchLimit)) { selected ->
            if (selected.isNotEmpty()) {
                closeProject()
                photos = selected.distinct().take(batchLimit).map { PhotoDraft(uri = it) }
                analyzeBatch = true
                rerender()
            }
        }
        val pickVideo = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { selected ->
            if (selected != null) {
                closeProject()
                video = VideoDraft(selected)
                position = 0
                duration = 0
                audio = EditorAudio.Original
                playing = false
                rerender()
            }
        }

        LaunchedEffect(feedbackRevision) {
            if (feedback.isNotEmpty()) {
                delay(2100)
                feedback = ""
                savedFeedback = false
            }
        }
        LaunchedEffect(rippleRevision) {
            if (rippleAt != null) {
                ripple.snapTo(0f)
                ripple.animateTo(1f, tween(480, easing = CubicBezierEasing(0.16f, 1f, 0.3f, 1f)))
                rippleAt = null
                delay(350)
                reveal = null
            }
        }
        LaunchedEffect(player, playing) {
            val active = player ?: return@LaunchedEffect
            active.playWhenReady = playing
            while (true) {
                position = active.currentPosition
                duration = active.duration.coerceAtLeast(0)
                delay(100)
            }
        }
        LaunchedEffect(renderRevision) {
            val currentVideo = video
            val currentPhoto = draft
            if (currentPhoto == null && currentVideo == null) return@LaunchedEffect
            photo = null
            videoPreview = null
            videoOutput = null
            startWork {
                try {
                    if (currentVideo != null) {
                        val frames = ArrayList<MaskFrame>()
                        val timeline = frameMasks.takeIf { it.isNotEmpty() }
                        val options = VideoMaskOptions(style, emoji, currentVideo.edits.manual, timeline) { frames.add(it) }
                        val result = VideoExporter(this@MainActivity).exportEditor(
                            currentVideo.uri, audio, options, VideoPurpose.Preview,
                        ) { progress = it }
                        if (timeline == null) frameMasks = frames.toList()
                        videoPreview = result.file
                    } else if (currentPhoto != null) {
                        val batch = if (analyzeBatch) photos else listOf(currentPhoto)
                        analyzeBatch = false
                        for ((index, item) in batch.withIndex()) {
                            try {
                                if (item.uri == currentPhoto.uri) {
                                    val (bitmap, faces) = renderPhoto(item, style, emoji)
                                    updatePhoto(item.copy(faces = faces))
                                    photo = bitmap
                                } else {
                                    updatePhoto(item.copy(faces = detectPhoto(item.uri)))
                                }
                            } catch (cancelled: CancellationException) {
                                throw cancelled
                            } catch (error: Exception) {
                                android.util.Log.w("TapHide", "Photo could not be analyzed", error)
                            }
                            progress = (index + 1) * 100 / batch.size
                        }
                    }
                } finally {
                    failed = if (currentVideo != null) videoPreview == null else photo == null
                }
            }
        }
        photo?.let { bitmap ->
            DisposableEffect(bitmap) { onDispose { bitmap.recycle() } }
        }
        videoPreview?.let { file ->
            DisposableEffect(file) { onDispose { file.delete() } }
        }

        videoOutput?.let { file ->
            DisposableEffect(file) { onDispose { file.delete() } }
        }

        fun export(share: Boolean, batch: List<PhotoDraft>? = null) {
            val currentVideo = video
            if (busy || (currentVideo == null && draft == null)) return
            saving = !share
            startWork {
                when {
                    currentVideo != null -> {
                        val file = videoOutput ?: VideoExporter(this@MainActivity).exportEditor(currentVideo.uri, audio,
                            VideoMaskOptions(style, emoji, currentVideo.edits.manual, frameMasks.takeIf { it.isNotEmpty() }),
                            VideoPurpose.FullExport) { progress = it }.file.also {
                            position = player?.currentPosition ?: position
                            videoOutput = it
                            videoPreview = null
                        }
                        if (share) shareFile(stageShare("mp4") { stream -> copyVideo(file, stream) }, "video/mp4")
                        else saveVideo(file)
                    }
                    share -> {
                        val current = checkNotNull(photo)
                        val file = stageShare("jpg") { check(current.compress(Bitmap.CompressFormat.JPEG, 95, it)) }
                        shareFile(file, "image/jpeg")
                    }
                    batch != null -> {
                        val previousSaved = if (batch.size < photos.size) batchResult?.first ?: 0 else 0
                        val failures = savePhotos(batch, style, emoji) { progress = it }
                        failedExports = failures
                        batchResult = (previousSaved + batch.size - failures.size) to failures.size
                    }
                    else -> {
                        val failures = savePhotos(listOf(checkNotNull(draft)), style, emoji) { progress = it }
                        check(failures.isEmpty())
                    }
                }
                if (!share && batch == null) {
                    savedFeedback = true
                    notify(getString(R.string.saved))
                }
            }
        }

        Surface(Modifier.fillMaxSize(), color = Color(0xFFF6EDE9)) {
            BoxWithConstraints(Modifier.fillMaxSize().safeDrawingPadding(), contentAlignment = Alignment.TopCenter) {
                val framed = maxWidth >= 640.dp
                Surface(
                    Modifier.widthIn(max = 400.dp).fillMaxWidth()
                        .then(if (framed) Modifier.padding(vertical = 20.dp) else Modifier.fillMaxHeight()),
                    shape = if (framed) RoundedCornerShape(38.dp) else RoundedCornerShape(0.dp),
                    border = if (framed) androidx.compose.foundation.BorderStroke(6.dp, Color.White) else null,
                    shadowElevation = if (framed) 16.dp else 0.dp,
                ) {
                    Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 24.dp),
                        verticalArrangement = Arrangement.spacedBy(14.dp)) {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically) {
                            Text(stringResource(R.string.app_name), fontSize = 28.sp, fontWeight = FontWeight.ExtraBold)
                            if (hasProject) {
                                OverlayPill(stringResource(R.string.editor_close), dark = false, enabled = !busy) {
                                    closeProject()
                                }
                            }
                        }
                        if (!hasProject) {
                            Text(stringResource(R.string.editor_home_intro), color = mutedInk, fontSize = 14.sp, lineHeight = 22.sp)
                            EditorButton(stringResource(R.string.editor_process_photos), true, !busy, Modifier.fillMaxWidth()) {
                                pickPhotos.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                            }
                            EditorButton(stringResource(R.string.editor_process_video), false, !busy, Modifier.fillMaxWidth()) {
                                pickVideo.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.VideoOnly))
                            }
                        } else {
                            Text(stringResource(if (isVideo) R.string.editor_video_hint else R.string.editor_batch_hint),
                                color = mutedInk, fontSize = 14.sp, lineHeight = 22.sp)
                            val noFaces = if (isVideo) {
                                frameMasks.isNotEmpty() && frameMasks.none { it.faces.isNotEmpty() }
                            } else draft?.faces?.isEmpty() == true
                            if (!busy && !failed && noFaces) {
                                Text(stringResource(R.string.editor_no_faces), color = brown, fontSize = 13.sp)
                            }

                            Surface(Modifier.fillMaxWidth().aspectRatio(4f / 5f),
                                shape = RoundedCornerShape(16.dp), color = Color(0xFFEFE2DC)) {
                                BoxWithConstraints(contentAlignment = Alignment.Center) {
                                    val density = LocalDensity.current
                                    val viewWidth = with(density) { maxWidth.toPx() }
                                    val viewHeight = with(density) { maxHeight.toPx() }
                                    val videoSize = player?.videoSize
                                    val mediaWidth = if (isVideo) videoSize?.width ?: 0 else photo?.width ?: 0
                                    val mediaHeight = if (isVideo) videoSize?.height ?: 0 else photo?.height ?: 0
                                    val aspectScale = if (mediaWidth > 0 && mediaHeight > 0) {
                                        minOf(viewWidth / mediaWidth, viewHeight / mediaHeight)
                                    } else 1f
                                    val imageWidth = mediaWidth * aspectScale
                                    val imageHeight = mediaHeight * aspectScale
                                    val left = (viewWidth - imageWidth) / 2
                                    val top = (viewHeight - imageHeight) / 2

                                    if (isVideo) {
                                        (videoOutput ?: videoPreview)?.let { file ->
                                            val active = remember(file) {
                                                ExoPlayer.Builder(this@MainActivity).build().apply {
                                                    setMediaItem(MediaItem.fromUri(Uri.fromFile(file)))
                                                    repeatMode = ExoPlayer.REPEAT_MODE_ONE
                                                    seekTo(position)
                                                    prepare()
                                                }
                                            }
                                            DisposableEffect(active) {
                                                player = active
                                                visiblePlayer = active
                                                onDispose {
                                                    if (player === active) player = null
                                                    if (visiblePlayer === active) visiblePlayer = null
                                                    active.release()
                                                }
                                            }
                                            AndroidView(factory = {
                                                (LayoutInflater.from(it).inflate(R.layout.editor_video, null) as PlayerView)
                                                    .apply { player = active }
                                            }, update = { it.player = active }, modifier = Modifier.fillMaxSize())
                                        }
                                    } else {
                                        photo?.let { Image(it.asImageBitmap(), stringResource(R.string.result),
                                            Modifier.fillMaxSize(), contentScale = ContentScale.Fit) }
                                    }

                                    if (imageWidth > 0 && imageHeight > 0 && !busy) {
                                        val tapAction by rememberUpdatedState<(Offset) -> Unit> { point ->
                                            val x = (point.x - left) / imageWidth
                                            val y = (point.y - top) / imageHeight
                                            if (x !in 0f..1f || y !in 0f..1f) return@rememberUpdatedState
                                            val faces = draft?.faces.orEmpty()
                                            val old = video?.edits ?: checkNotNull(draft).edits
                                            val next = old.tap(x, y, faces, 0.13f, 0.1f)
                                            reveal = faces.firstOrNull { it.id in next.revealed && it.id !in old.revealed }?.box
                                            val message = when {
                                                next.revealed.size > old.revealed.size -> R.string.editor_revealed
                                                next.revealed.size < old.revealed.size -> R.string.editor_covered
                                                next.manual.size < old.manual.size -> R.string.editor_removed
                                                next == old -> R.string.editor_mask_limit
                                                else -> R.string.editor_added
                                            }
                                            notify(getString(message))
                                            if (isVideo) position = player?.currentPosition ?: position
                                            rippleAt = point
                                            rippleRevision++
                                            if (next != old) {
                                                if (isVideo) video = video?.copy(edits = next)
                                                else updatePhoto(checkNotNull(draft).copy(edits = next))
                                                rerender()
                                            }
                                        }
                                        Box(Modifier.fillMaxSize().pointerInput(Unit) { detectTapGestures { tapAction(it) } })
                                    }
                                    Canvas(Modifier.fillMaxSize()) {
                                        rippleAt?.let { point ->
                                            val radius = (24 * (0.3f + ripple.value * 1.6f)).dp.toPx()
                                            drawCircle(coral.copy(alpha = (1 - ripple.value) * 0.22f), radius, point)
                                            drawCircle(coral.copy(alpha = (1 - ripple.value) * 0.9f),
                                                radius, point, style = Stroke(3.dp.toPx()))
                                        }
                                        reveal?.let { box ->
                                            drawRect(coral, Offset(left + (box.cx - box.rx) * imageWidth, top + (box.cy - box.ry) * imageHeight),
                                                Size(box.rx * 2 * imageWidth, box.ry * 2 * imageHeight),
                                                style = Stroke(2.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(6f, 5f))))
                                        }
                                    }
                                    if (!isVideo) {
                                        OverlayPill(stringResource(R.string.editor_canvas_hint),
                                            Modifier.align(Alignment.TopCenter).padding(12.dp))
                                    }
                                    if (busy) {
                                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                            CircularProgressIndicator()
                                            if (isVideo || progress > 0) OverlayPill("$progress%")
                                            OverlayPill(stringResource(R.string.cancel), Modifier.padding(top = 8.dp), dark = false) {
                                                running?.cancel()
                                            }
                                        }
                                    } else if (failed) {
                                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                            Text(stringResource(R.string.failed), Modifier.padding(horizontal = 12.dp))
                                            EditorButton(stringResource(R.string.editor_retry), true, true) { rerender() }
                                        }
                                    }
                                    Row(Modifier.align(Alignment.BottomCenter).fillMaxWidth().padding(12.dp),
                                        horizontalArrangement = Arrangement.spacedBy(4.dp),
                                        verticalAlignment = Alignment.CenterVertically) {
                                        if (isVideo) {
                                            OverlayPill("${if (playing) "⏸" else "▶"} ${timeLabel(position)} / ${timeLabel(duration)}",
                                                monospace = true, enabled = !busy && player != null) { playing = !playing }
                                            val audioLabel = when (audio) {
                                                EditorAudio.Original -> "🔊 " + stringResource(R.string.editor_original_audio)
                                                EditorAudio.Mute -> "🔇 " + stringResource(R.string.mute)
                                                EditorAudio.Voice -> stringResource(R.string.editor_voice)
                                            }
                                            OverlayPill(audioLabel, dark = false, canvasControl = true, enabled = !busy) {
                                                audio = EditorAudio.entries[(audio.ordinal + 1) % EditorAudio.entries.size]
                                                rerender()
                                            }
                                        } else {
                                            Surface(shape = pill, color = Color.Black.copy(alpha = 0.5f), contentColor = Color.White) {
                                                Row(verticalAlignment = Alignment.CenterVertically) {
                                                    OverlayPill("‹", dark = true, transparent = true, enabled = !busy) {
                                                        photoIndex = (photoIndex + photos.size - 1) % photos.size
                                                        rerender()
                                                    }
                                                    Text(stringResource(R.string.editor_photo_count, photoIndex + 1, photos.size), fontSize = 11.sp)
                                                    OverlayPill("›", dark = true, transparent = true, enabled = !busy) {
                                                        photoIndex = (photoIndex + 1) % photos.size
                                                        rerender()
                                                    }
                                                }
                                            }
                                        }
                                        Spacer(Modifier.weight(1f))
                                        OverlayPill(stringResource(R.string.editor_reset), dark = false, canvasControl = true, enabled = !busy) {
                                            if (isVideo) video = video?.copy(edits = MaskEdits())
                                            else updatePhoto(checkNotNull(draft).copy(edits = MaskEdits()))
                                            notify(getString(R.string.editor_reset_done))
                                            rerender()
                                        }
                                    }
                                }
                            }
                            if (isVideo && duration > 0) {
                                Slider(value = (seekPosition ?: position.toFloat()).coerceIn(0f, duration.toFloat()),
                                    onValueChange = { seekPosition = it },
                                    onValueChangeFinished = {
                                        seekPosition?.let { player?.seekTo(it.toLong()) }
                                        seekPosition = null
                                    }, enabled = !busy && player != null, valueRange = 0f..duration.toFloat())
                            }
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                for (option in MaskStyle.entries) {
                                    val label = when (option) {
                                        MaskStyle.Mosaic -> stringResource(R.string.editor_pixelate)
                                        MaskStyle.Blur -> stringResource(R.string.editor_blur)
                                        MaskStyle.Sticker -> "$emoji " + stringResource(
                                            if (style == option) R.string.editor_change_sticker else R.string.editor_sticker)
                                    }
                                    EditorButton(label, style == option, !busy, Modifier.weight(1f), compact = true) {
                                        if (style != option || option == MaskStyle.Sticker) {
                                            if (style == option) emojiIndex = (emojiIndex + 1) % stickers.size
                                            style = option
                                            rerender()
                                        }
                                    }
                                }
                            }
                            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                val enabled = !busy && if (isVideo) videoOutput != null || videoPreview != null else photo != null
                                Button(onClick = { export(false) }, enabled = enabled,
                                    modifier = Modifier.weight(1f).heightIn(min = 50.dp)) {
                                    Text(stringResource(when {
                                        saving -> R.string.editor_saving
                                        savedFeedback -> R.string.saved
                                        else -> R.string.save
                                    }), fontWeight = FontWeight.Bold)
                                }
                                Button(onClick = { export(true) }, enabled = enabled, colors = secondary,
                                    modifier = Modifier.heightIn(min = 50.dp)) {
                                    Text(stringResource(R.string.editor_share), fontWeight = FontWeight.Bold)
                                }
                            }
                            if (!isVideo && photos.size > 1) {
                                Button(onClick = { export(false, photos) }, enabled = !busy, modifier = Modifier.fillMaxWidth()) {
                                    Text(stringResource(R.string.editor_save_batch, photos.size))
                                }
                                batchResult?.let { (saved, failures) ->
                                    Text(stringResource(R.string.editor_batch_result, saved, failures))
                                }
                                if (failedExports.isNotEmpty()) {
                                    TextButton(onClick = { export(false, photos.filter { it.uri in failedExports }) }, enabled = !busy) {
                                        Text(stringResource(R.string.editor_retry_failed, failedExports.size))
                                    }
                                }
                            }
                        }
                    }
                }
                if (feedback.isNotEmpty()) {
                    OverlayPill(feedback, Modifier.align(Alignment.TopCenter).padding(top = 8.dp, start = 12.dp, end = 12.dp), toast = true)
                }
            }
        }
    }

    @Composable
    private fun EditorButton(label: String, active: Boolean, enabled: Boolean, modifier: Modifier = Modifier,
        compact: Boolean = false, onClick: () -> Unit) {
        Button(onClick, modifier, enabled, colors = ButtonDefaults.buttonColors(
            containerColor = if (active) coral else pink, contentColor = if (active) Color.White else brown,
        ), contentPadding = PaddingValues(horizontal = if (compact) 3.dp else 5.dp, vertical = 8.dp)) {
            Text(label, fontSize = if (compact) 12.sp else 13.sp, fontWeight = FontWeight.Bold)
        }
    }

    @Composable
    private fun OverlayPill(label: String, modifier: Modifier = Modifier, dark: Boolean = true,
        enabled: Boolean = true, transparent: Boolean = false, monospace: Boolean = false,
        canvasControl: Boolean = false, toast: Boolean = false, onClick: (() -> Unit)? = null) {
        Surface(
            modifier = if (onClick == null) modifier else modifier.clickable(enabled = enabled, onClick = onClick),
            shape = pill,
            color = when {
                transparent -> Color.Transparent
                toast -> ink.copy(alpha = 0.9f)
                canvasControl -> Color.White.copy(alpha = 0.88f)
                dark -> Color.Black.copy(alpha = 0.5f)
                else -> pink.copy(alpha = 0.94f)
            },
            contentColor = (if (dark) Color.White else brown).copy(alpha = if (enabled) 1f else 0.6f),
        ) {
            Text(label, Modifier.padding(horizontal = if (toast) 16.dp else 8.dp, vertical = if (toast) 8.dp else 6.dp),
                fontSize = if (toast) 12.sp else 11.sp,
                fontFamily = if (monospace) FontFamily.Monospace else FontFamily.Default,
                fontWeight = FontWeight.SemiBold)
        }
    }

    private fun timeLabel(milliseconds: Long): String {
        val seconds = milliseconds / 1000
        return "%d:%02d".format(seconds / 60, seconds % 60)
    }

    private fun decodePhoto(uri: Uri): Bitmap =
        ImageDecoder.decodeBitmap(ImageDecoder.createSource(contentResolver, uri)) { decoder, info, _ ->
            decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            decoder.setTargetSampleSize(ceil(maxOf(info.size.width, info.size.height) / 2048.0).toInt().coerceAtLeast(1))
        }

    private fun detectPhoto(bitmap: Bitmap): List<PhotoFace> =
        FaceDetector(this, detectPerson = false).use { it.detect(bitmap).faces.mapIndexed(::PhotoFace) }

    private suspend fun detectPhoto(uri: Uri): List<PhotoFace> = withContext(Dispatchers.Default) {
        val source = decodePhoto(uri)
        try { detectPhoto(source) } finally { source.recycle() }
    }

    private suspend fun renderPhoto(draft: PhotoDraft, style: MaskStyle, emoji: String): Pair<Bitmap, List<PhotoFace>> {
        var output: Bitmap? = null
        try {
            return withContext(Dispatchers.Default) {
                val source = decodePhoto(draft.uri)
                try {
                    val faces = draft.faces ?: detectPhoto(source)
                    ensureActive()
                    val rendered = renderEditorPhoto(source, draft.edits.masks(faces), style, emoji)
                    output = rendered
                    rendered to faces
                } finally { source.recycle() }
            }
        } catch (error: Exception) {
            output?.recycle()
            throw error
        }
    }

    private suspend fun savePhotos(drafts: List<PhotoDraft>, style: MaskStyle, emoji: String,
        progress: (Int) -> Unit): Set<Uri> {
        require(drafts.size in 1..batchLimit)
        val saved = mutableListOf<Uri>()
        val failures = mutableSetOf<Uri>()
        try {
            for ((index, draft) in drafts.withIndex()) {
                currentCoroutineContext().ensureActive()
                try {
                    val (bitmap) = renderPhoto(draft, style, emoji)
                    try {
                        withContext(Dispatchers.IO) {
                            saved += saveMedia(false) { check(bitmap.compress(Bitmap.CompressFormat.JPEG, 95, it)) }
                        }
                    } finally { bitmap.recycle() }
                } catch (cancelled: CancellationException) {
                    throw cancelled
                } catch (error: Exception) {
                    android.util.Log.w("TapHide", "Photo could not be saved", error)
                    failures += draft.uri
                }
                progress((index + 1) * 100 / drafts.size)
            }
        } catch (cancelled: CancellationException) {
            withContext(NonCancellable + Dispatchers.IO) {
                saved.forEach { runCatching { contentResolver.delete(it, null, null) } }
            }
            throw cancelled
        }
        return failures
    }

    private suspend fun saveVideo(file: File) {
        var saved: Uri? = null
        try {
            withContext(Dispatchers.IO) {
                saved = saveMedia(true) { copyVideo(file, it) }
            }
        } catch (error: Exception) {
            withContext(NonCancellable + Dispatchers.IO) {
                saved?.let { runCatching { contentResolver.delete(it, null, null) } }
            }
            throw error
        }
    }

    private suspend fun stageShare(extension: String, write: suspend (java.io.OutputStream) -> Unit): File {
        var staged: File? = null
        try {
            return withContext(Dispatchers.IO) {
                shareDirectory.mkdirs()
                File.createTempFile("TapHide-", ".$extension", shareDirectory).also { file ->
                    staged = file
                    file.outputStream().use { write(it) }
                    ensureActive()
                }
            }
        } catch (error: Exception) {
            withContext(NonCancellable + Dispatchers.IO) { staged?.delete() }
            throw error
        }
    }

    private suspend fun copyVideo(file: File, destination: java.io.OutputStream) {
        val context = currentCoroutineContext()
        file.inputStream().use { input ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                context.ensureActive()
                val read = input.read(buffer)
                if (read == -1) break
                destination.write(buffer, 0, read)
            }
        }
    }

    private suspend fun saveMedia(video: Boolean, write: suspend (java.io.OutputStream) -> Unit): Uri {
        val collection = if (video) MediaStore.Video.Media.EXTERNAL_CONTENT_URI else MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, "TapHide-${System.currentTimeMillis()}.${if (video) "mp4" else "jpg"}")
            put(MediaStore.MediaColumns.MIME_TYPE, if (video) "video/mp4" else "image/jpeg")
            put(MediaStore.MediaColumns.RELATIVE_PATH, if (video) "Movies/TapHide" else "Pictures/TapHide")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val destination = checkNotNull(contentResolver.insert(collection, values))
        try {
            checkNotNull(contentResolver.openOutputStream(destination)).use { write(it) }
            currentCoroutineContext().ensureActive()
            check(contentResolver.update(destination, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null) == 1)
            return destination
        } catch (error: Exception) {
            contentResolver.delete(destination, null, null)
            throw error
        }
    }

    private fun shareFile(file: File, mime: String) {
        val uri = FileProvider.getUriForFile(this, "$packageName.editor-share", file)
        startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
            type = mime
            putExtra(Intent.EXTRA_STREAM, uri)
            clipData = ClipData.newRawUri("TapHide", uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }, null))
    }

    override fun onStop() {
        running?.cancel()
        resumePlayback = visiblePlayer?.playWhenReady == true
        visiblePlayer?.pause()
        super.onStop()
    }

    override fun onStart() {
        super.onStart()
        if (resumePlayback) visiblePlayer?.play()
        resumePlayback = false
    }

    override fun onDestroy() {
        running?.cancel()
        super.onDestroy()
    }
}
