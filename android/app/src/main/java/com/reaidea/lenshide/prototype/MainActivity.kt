package com.reaidea.lenshide.prototype

import android.content.ClipData
import android.content.ContentValues
import android.content.Context
import android.content.res.Configuration
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Bundle
import android.provider.DocumentsContract
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
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.FileProvider
import androidx.core.view.WindowCompat
import androidx.lifecycle.lifecycleScope
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import kotlinx.coroutines.*
import java.io.File
import java.util.Locale
import kotlin.math.ceil

// Palette aligned with the design reference (apricot / cocoa tokens).
internal val coral = Color(0xFFEF7E68)
internal val coralDeep = Color(0xFFDC644D)
internal val apricotDark = Color(0xFFB84B37)
internal val apricot300 = Color(0xFFF6BDB0)
internal val paper = Color(0xFFFFF9F6)
internal val pink = Color(0xFFFDECE7)
internal val line = Color(0xFFFAD9D0)
internal val ink = Color(0xFF2B211E)
internal val brown = Color(0xFF5A4944)
internal val mutedInk = Color(0xFF75665F)
internal val emerald = Color(0xFF10B981)
internal val emeraldSoft = Color(0xFFECFDF5)
internal val emeraldDeep = Color(0xFF047857)
internal val roseSoft = Color(0xFFFFF1F2)
internal val roseLine = Color(0xFFFECDD3)
internal val roseDeep = Color(0xFFBE123C)
internal val pill = RoundedCornerShape(50)
internal const val batchLimit = 20

private data class PhotoDraft(
    val uri: Uri,
    val faces: List<PhotoFace>? = null,
    val edits: MaskEdits = MaskEdits(),
    val faceStickers: Map<Int, String> = emptyMap(),
)

private data class PhotoExport(val saved: List<Uri>, val failed: Set<Uri>)

private data class VideoDraft(val uri: Uri, val edits: MaskEdits = MaskEdits())

@UnstableApi
class MainActivity : ComponentActivity() {
    private var running: Job? = null
    private var activityStarted by mutableStateOf(false)
    private var visiblePlayer: ExoPlayer? = null
    private val shareDirectory get() = File(cacheDir, "editor-share")

    override fun attachBaseContext(newBase: Context) {
        val tag = newBase.getSharedPreferences("editor_settings", MODE_PRIVATE).getString("language", null)
        val localized = if (tag == null) newBase else newBase.createConfigurationContext(
            Configuration(newBase.resources.configuration).apply { setLocale(Locale.forLanguageTag(tag)) },
        )
        super.attachBaseContext(localized)
    }

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
        var videoOutput by remember { mutableStateOf<File?>(null) }
        var player by remember { mutableStateOf<ExoPlayer?>(null) }
        var videoRetry by remember { mutableIntStateOf(0) }
        val sourceUri = video?.uri
        var checkedVideo by remember(sourceUri, videoRetry) { mutableStateOf(false) }
        var previewFailed by remember(sourceUri, videoRetry) { mutableStateOf(false) }
        var videoBuffering by remember { mutableStateOf(false) }
        var firstFrameRendered by remember { mutableStateOf(false) }
        var videoSize by remember { mutableStateOf(VideoSize.UNKNOWN) }
        val videoReady = player != null && firstFrameRendered && !previewFailed
        var playing by remember { mutableStateOf(true) }
        var position by remember { mutableLongStateOf(0L) }
        var duration by remember { mutableLongStateOf(0L) }
        var busy by remember { mutableStateOf(false) }
        var progress by remember { mutableIntStateOf(0) }
        var renderRevision by remember { mutableIntStateOf(0) }
        var saving by remember { mutableStateOf(false) }
        var settingsOpen by remember { mutableStateOf(false) }
        var lifetimeOpen by remember { mutableStateOf(false) }
        var saveOpen by remember { mutableStateOf(false) }
        var saveError by remember { mutableStateOf(false) }
        var saveBatchRequest by remember { mutableStateOf(false) }
        var savedExport by remember { mutableStateOf<SavedExport?>(null) }
        var batchItems by remember { mutableStateOf(emptyList<Uri>()) }
        var selectedFace by remember { mutableStateOf<Int?>(null) }
        var failed by remember { mutableStateOf(false) }
        var feedback by remember { mutableStateOf("") }
        var feedbackRevision by remember { mutableIntStateOf(0) }
        var rippleAt by remember { mutableStateOf<Offset?>(null) }
        var reveal by remember { mutableStateOf<FaceBox?>(null) }
        var rippleRevision by remember { mutableIntStateOf(0) }
        val ripple = remember { Animatable(1f) }
        val draft = photos.getOrNull(photoIndex)
        var seekPosition by remember { mutableStateOf<Float?>(null) }
        var infoOpen by remember { mutableStateOf(false) }
        val scope = rememberCoroutineScope()
        val slide = remember { Animatable(0f) }
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
            photo = null
            videoOutput = null
            seekPosition = null
            failedExports = emptySet()
            batchResult = null
            batchItems = emptyList()
            selectedFace = null
            savedExport = null
            saveOpen = false
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
        fun updateVideoPreview() {
            position = player?.currentPosition ?: position
            videoOutput = null
        }
        fun startWork(block: suspend () -> Unit) {
            if (busy) return
            busy = true
            progress = 0
            running = lifecycleScope.launch {
                try { block() }
                catch (_: CancellationException) {
                    if (saving) saveOpen = false
                    notify(getString(R.string.cancelled))
                }
                catch (error: Exception) {
                    android.util.Log.e("TapHide", "Media operation failed", error)
                    if (saving) saveError = true
                    notify(getString(R.string.failed))
                }
                finally { busy = false; saving = false }
            }
        }

        // One entry point for photos and videos. The system Photo Picker cannot disable individual items,
        // so the rules are enforced on the returned selection: photos and videos never mix, one video only.
        val pickMedia = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(batchLimit)) { selected ->
            val uris = selected.distinct()
            if (uris.isEmpty()) return@rememberLauncherForActivityResult
            val videos = uris.filter { isVideoUri(it) }
            val images = uris - videos.toSet()
            when {
                videos.isNotEmpty() && images.isNotEmpty() -> notify(getString(R.string.editor_mixed_rejected))
                videos.size > 1 -> notify(getString(R.string.editor_video_single))
                videos.size == 1 -> {
                    closeProject()
                    video = VideoDraft(videos.single())
                    position = 0
                    duration = 0
                    audio = EditorAudio.Original
                    playing = false
                }
                else -> {
                    closeProject()
                    photos = images.take(batchLimit).map { PhotoDraft(uri = it) }
                    analyzeBatch = true
                    rerender()
                }
            }
        }

        var copySource by remember { mutableStateOf<Uri?>(null) }
        fun finishCopy(destination: Uri?) {
            val source = copySource
            copySource = null
            if (source != null && destination != null) {
                startWork {
                    withContext(Dispatchers.IO) {
                        try {
                            checkNotNull(contentResolver.openInputStream(source)).use { input ->
                                checkNotNull(contentResolver.openOutputStream(destination, "wt")).use { output ->
                                    copyStream(input, output)
                                }
                            }
                        } catch (error: Exception) {
                            runCatching { DocumentsContract.deleteDocument(contentResolver, destination) }
                            throw error
                        }
                    }
                    notify(getString(R.string.editor_copy_saved))
                }
            }
        }
        val copyPhoto = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("image/jpeg"), ::finishCopy)
        val copyMovie = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("video/mp4"), ::finishCopy)

        LaunchedEffect(feedbackRevision) {
            if (feedback.isNotEmpty()) {
                delay(2100)
                feedback = ""
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
        LaunchedEffect(sourceUri, videoRetry) {
            if (sourceUri == null) return@LaunchedEffect
            try {
                inspectVideo(this@MainActivity, sourceUri)
                checkedVideo = true
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                android.util.Log.w("TapHide", "Video could not be opened", error)
                previewFailed = true
            }
        }
        val videoOptions = video?.let { VideoMaskOptions(style, emoji, it.edits.manual) }
        val output = videoOutput
        DisposableEffect(sourceUri, checkedVideo, videoOptions, output) {
            val active = if (sourceUri != null && checkedVideo) {
                firstFrameRendered = false
                videoSize = VideoSize.UNKNOWN
                previewFailed = false
                ExoPlayer.Builder(this@MainActivity).build().apply {
                    addListener(object : Player.Listener {
                        override fun onRenderedFirstFrame() {
                            firstFrameRendered = true
                        }

                        override fun onVideoSizeChanged(size: VideoSize) {
                            videoSize = size
                        }

                        override fun onPlaybackStateChanged(state: Int) {
                            videoBuffering = state == Player.STATE_BUFFERING
                        }

                        override fun onPlayerError(error: PlaybackException) {
                            android.util.Log.w("TapHide", "Video preview failed", error)
                            previewFailed = true
                        }
                    })
                    if (output == null) {
                        setVideoEffects(listOf(FacePixelEffect(FrameMetrics(), videoOptions)))
                    }
                    setMediaItem(MediaItem.fromUri(output?.let(Uri::fromFile) ?: sourceUri), position)
                    repeatMode = Player.REPEAT_MODE_ONE
                    player = this
                    visiblePlayer = this
                    prepare()
                }
            } else null
            onDispose {
                if (active != null) {
                    player = null
                    visiblePlayer = null
                    active.release()
                }
            }
        }
        LaunchedEffect(player, playing, busy, activityStarted) {
            player?.playWhenReady = playing && !busy && activityStarted
        }
        LaunchedEffect(player, audio, output) {
            player?.apply {
                volume = if (output == null && audio == EditorAudio.Mute) 0f else 1f
                playbackParameters = PlaybackParameters(1f, if (output == null && audio == EditorAudio.Voice) 1.32f else 1f)
            }
        }
        LaunchedEffect(player) {
            val active = player ?: return@LaunchedEffect
            while (true) {
                position = active.currentPosition
                duration = active.duration.coerceAtLeast(0)
                delay(100)
            }
        }
        LaunchedEffect(renderRevision) {
            val currentPhoto = draft ?: return@LaunchedEffect
            photo = null
            startWork {
                try {
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
                } finally {
                    failed = photo == null
                }
            }
        }
        photo?.let { bitmap ->
            DisposableEffect(bitmap) { onDispose { bitmap.recycle() } }
        }
        videoOutput?.let { file ->
            DisposableEffect(file) { onDispose { file.delete() } }
        }

        fun export(share: Boolean, batch: List<PhotoDraft>? = null) {
            val currentVideo = video
            if (busy || (currentVideo == null && draft == null)) return
            saving = !share
            if (!share) {
                saveOpen = true
                saveError = false
                savedExport = null
                saveBatchRequest = batch != null
            }
            startWork {
                when {
                    currentVideo != null -> {
                        val file = videoOutput ?: VideoExporter(this@MainActivity).exportEditor(currentVideo.uri, audio,
                            VideoMaskOptions(style, emoji, currentVideo.edits.manual),
                            VideoPurpose.FullExport) { progress = it }.file.also {
                            position = player?.currentPosition ?: position
                            videoOutput = it
                        }
                        if (share) shareFile(stageShare("mp4") { stream -> copyVideo(file, stream) }, "video/mp4")
                        else savedExport = SavedExport(listOf(saveVideo(file)), video = true)
                    }
                    share -> {
                        val current = checkNotNull(photo)
                        val file = stageShare("jpg") { check(current.compress(Bitmap.CompressFormat.JPEG, 95, it)) }
                        shareFile(file, "image/jpeg")
                    }
                    batch != null -> {
                        val retrying = batch.size < photos.size
                        val result = savePhotos(batch, style, emoji) { progress = it }
                        batchItems = (if (retrying) batchItems else emptyList()) + result.saved
                        failedExports = result.failed
                        batchResult = batchItems.size to result.failed.size
                        savedExport = SavedExport(batchItems, video = false, failures = result.failed.size)
                    }
                    else -> {
                        val result = savePhotos(listOf(checkNotNull(draft)), style, emoji) { progress = it }
                        check(result.failed.isEmpty())
                        savedExport = SavedExport(result.saved, video = false)
                    }
                }
            }
        }

        val mediaRequest = PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageAndVideo)
        val mediaReady = !busy && (!isVideo || videoReady)
        val swipeEnabled = hasProject && !isVideo && photos.size > 1 && !busy
        val canExport = !busy && (if (isVideo) videoReady else photo != null)
        val pickLabel = when {
            !hasProject -> stringResource(R.string.editor_pick_media)
            isVideo -> stringResource(R.string.editor_reselect_video)
            else -> stringResource(R.string.editor_reselect_photos, photos.size, batchLimit)
        }
        fun switchPhoto(target: Int, widthPx: Float) {
            val current = photoIndex
            if (target == current || target !in photos.indices) {
                if (target != current) {
                    notify(getString(if (target < current) R.string.editor_first_photo else R.string.editor_last_photo))
                }
                scope.launch { slide.animateTo(0f, tween(180)) }
                return
            }
            val direction = if (target > current) -1f else 1f
            scope.launch {
                slide.animateTo(direction * widthPx, tween(150))
                selectedFace = null
                photoIndex = target
                rerender()
                slide.snapTo(-direction * widthPx)
                slide.animateTo(0f, tween(230, easing = CubicBezierEasing(0.16f, 1f, 0.3f, 1f)))
            }
        }

        Surface(Modifier.fillMaxSize(), color = Color(0xFFF4E6E0)) {
            BoxWithConstraints(Modifier.fillMaxSize().safeDrawingPadding(), contentAlignment = Alignment.TopCenter) {
                val framed = maxWidth >= 640.dp
                Surface(
                    Modifier.widthIn(max = 400.dp).fillMaxWidth()
                        .then(if (framed) Modifier.padding(vertical = 20.dp) else Modifier.fillMaxHeight()),
                    shape = if (framed) RoundedCornerShape(38.dp) else RoundedCornerShape(0.dp),
                    border = if (framed) BorderStroke(6.dp, Color.White) else null,
                    shadowElevation = if (framed) 16.dp else 0.dp,
                    color = paper,
                ) {
                    Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 20.dp),
                        verticalArrangement = Arrangement.spacedBy(14.dp)) {
                        // Header: title and privacy hint on the left; plan entry and settings on the right.
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                Text(stringResource(R.string.app_name), fontSize = 24.sp, fontWeight = FontWeight.ExtraBold,
                                    color = ink, letterSpacing = (-0.5).sp)
                                Box(Modifier.size(40.dp).clip(CircleShape).clickable { infoOpen = !infoOpen },
                                    contentAlignment = Alignment.Center) {
                                    Box(Modifier.size(24.dp).background(pink, CircleShape), contentAlignment = Alignment.Center) {
                                        Text("!", fontSize = 12.sp, fontWeight = FontWeight.ExtraBold, color = apricotDark)
                                    }
                                }
                            }
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                Surface(onClick = { lifetimeOpen = true }, enabled = !busy, shape = pill, color = pink,
                                    border = BorderStroke(1.dp, line), contentColor = coralDeep) {
                                    Text(stringResource(R.string.editor_lifetime), Modifier.padding(horizontal = 10.dp, vertical = 5.dp),
                                        fontSize = 12.sp, fontWeight = FontWeight.Bold)
                                }
                                Box(Modifier.size(40.dp).clip(CircleShape).clickable(enabled = !busy) { settingsOpen = true },
                                    contentAlignment = Alignment.Center) {
                                    Box(Modifier.size(32.dp).background(Color.White, CircleShape).border(1.dp, line, CircleShape),
                                        contentAlignment = Alignment.Center) {
                                        TapIcon(R.drawable.tap_settings, stringResource(R.string.editor_settings), Modifier.size(16.dp))
                                    }
                                }
                            }
                        }
                        if (infoOpen) PrivacyPopover { infoOpen = false }

                        // Single entry for photos and videos, plus a clear action once a project is open.
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalAlignment = Alignment.CenterVertically) {
                            Button(onClick = { pickMedia.launch(mediaRequest) }, enabled = !busy, shape = pill,
                                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 9.dp)) {
                                IconLabel(R.drawable.tap_add, pickLabel)
                            }
                            if (hasProject) {
                                OutlinedButton(onClick = { closeProject() }, enabled = !busy, shape = pill,
                                    colors = ButtonDefaults.outlinedButtonColors(containerColor = paper, contentColor = brown),
                                    border = BorderStroke(1.dp, line),
                                    contentPadding = PaddingValues(horizontal = 14.dp, vertical = 9.dp)) {
                                    IconLabel(R.drawable.tap_close, stringResource(R.string.editor_clear))
                                }
                            }
                        }
                        Text(
                            when {
                                !hasProject -> stringResource(R.string.editor_limit_hint)
                                isVideo -> stringResource(R.string.editor_video_hint)
                                else -> stringResource(R.string.editor_batch_hint)
                            },
                            color = mutedInk, fontSize = 11.sp, lineHeight = 16.sp,
                        )
                        if (hasProject && !busy && !failed && draft?.faces?.isEmpty() == true) {
                            Text(stringResource(R.string.editor_no_faces), color = brown, fontSize = 12.sp, lineHeight = 17.sp)
                        }

                        // Photo batch chips: jump to any photo; swiping the canvas moves to neighbours.
                        if (hasProject && !isVideo) {
                            Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                                horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                photos.forEachIndexed { index, item ->
                                    val selected = index == photoIndex
                                    val count = item.faces?.size
                                    val status = when (count) {
                                        null -> stringResource(R.string.editor_status_pending)
                                        0 -> stringResource(R.string.editor_status_no_face)
                                        else -> pluralStringResource(R.plurals.editor_status_faces, count, count)
                                    }
                                    Surface(onClick = {
                                        if (!selected) {
                                            selectedFace = null
                                            photoIndex = index
                                            rerender()
                                        }
                                    }, enabled = !busy, shape = pill,
                                        color = if (selected) coral else Color.White,
                                        border = BorderStroke(1.dp, if (selected) coral else line),
                                        contentColor = if (selected) Color.White else brown) {
                                        Text(stringResource(R.string.editor_photo_chip, index + 1, status),
                                            Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                                            fontSize = 12.sp, fontWeight = FontWeight.Bold, maxLines = 1)
                                    }
                                }
                            }
                        }

                        Surface(Modifier.fillMaxWidth().aspectRatio(4f / 5f), shape = RoundedCornerShape(16.dp),
                            color = Color(0xFFEFE2DC), border = BorderStroke(1.dp, line)) {
                            if (!hasProject) {
                                EmptyCanvas(enabled = !busy) { pickMedia.launch(mediaRequest) }
                            } else BoxWithConstraints(
                                Modifier.fillMaxSize().then(if (swipeEnabled) Modifier.pointerInput(Unit) {
                                    // Static gesture container: the media layer moves, so drag coordinates stay stable.
                                    var total = 0f
                                    detectHorizontalDragGestures(
                                        onDragStart = { total = 0f },
                                        onHorizontalDrag = { change, dragAmount ->
                                            change.consume()
                                            total += dragAmount
                                            val limit = size.width * 0.5f
                                            scope.launch { slide.snapTo(total.coerceIn(-limit, limit)) }
                                        },
                                        onDragEnd = {
                                            val threshold = size.width * 0.18f
                                            val current = photoIndex
                                            val target = when {
                                                total <= -threshold -> current + 1
                                                total >= threshold -> current - 1
                                                else -> current
                                            }
                                            switchPhoto(target, size.width.toFloat())
                                        },
                                        onDragCancel = { scope.launch { slide.animateTo(0f, tween(180)) } },
                                    )
                                } else Modifier),
                                contentAlignment = Alignment.Center,
                            ) {
                                val density = LocalDensity.current
                                val viewWidth = with(density) { maxWidth.toPx() }
                                val viewHeight = with(density) { maxHeight.toPx() }
                                val mediaWidth = if (isVideo) videoSize.width * videoSize.pixelWidthHeightRatio else (photo?.width ?: 0).toFloat()
                                val mediaHeight = if (isVideo) videoSize.height else photo?.height ?: 0
                                val aspectScale = if (mediaWidth > 0 && mediaHeight > 0) {
                                    minOf(viewWidth / mediaWidth, viewHeight / mediaHeight)
                                } else 1f
                                val imageWidth = mediaWidth * aspectScale
                                val imageHeight = mediaHeight * aspectScale
                                val left = (viewWidth - imageWidth) / 2
                                val top = (viewHeight - imageHeight) / 2

                                Box(Modifier.fillMaxSize().graphicsLayer { translationX = slide.value }) {
                                    if (isVideo) {
                                        player?.takeUnless { previewFailed }?.let { active ->
                                            AndroidView(factory = {
                                                (LayoutInflater.from(it).inflate(R.layout.editor_video, null) as PlayerView)
                                                    .apply { player = active }
                                            }, update = { it.player = active }, onRelease = { it.player = null },
                                                modifier = Modifier.fillMaxSize())
                                        }
                                    } else {
                                        photo?.let { Image(it.asImageBitmap(), stringResource(R.string.result),
                                            Modifier.fillMaxSize(), contentScale = ContentScale.Fit) }
                                    }

                                    if (imageWidth > 0 && imageHeight > 0 && mediaReady) {
                                        val tapAction by rememberUpdatedState<(Offset) -> Unit> { point ->
                                            val x = (point.x - left) / imageWidth
                                            val y = (point.y - top) / imageHeight
                                            if (x !in 0f..1f || y !in 0f..1f) return@rememberUpdatedState
                                            val faces = draft?.faces.orEmpty()
                                            if (style == MaskStyle.Sticker && !isVideo) {
                                                selectedFace = faces.lastOrNull { it.box.contains(x, y) }?.id
                                                if (selectedFace != null) return@rememberUpdatedState
                                            }
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
                                            rippleAt = point
                                            rippleRevision++
                                            if (next != old) {
                                                if (isVideo) {
                                                    updateVideoPreview()
                                                    video = video?.copy(edits = next)
                                                } else {
                                                    updatePhoto(checkNotNull(draft).copy(edits = next))
                                                    rerender()
                                                }
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
                                        val selectedBox = draft?.faces?.firstOrNull { it.id == selectedFace }?.box
                                        (selectedBox ?: reveal)?.let { box ->
                                            drawRect(coral, Offset(left + (box.cx - box.rx) * imageWidth, top + (box.cy - box.ry) * imageHeight),
                                                Size(box.rx * 2 * imageWidth, box.ry * 2 * imageHeight),
                                                style = Stroke(2.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(6f, 5f))))
                                        }
                                    }
                                }
                                if (!isVideo) {
                                    OverlayPill(stringResource(if (style == MaskStyle.Sticker) R.string.editor_sticker_hint
                                        else R.string.editor_canvas_hint), Modifier.align(Alignment.TopCenter).padding(12.dp))
                                }
                                if (busy) {
                                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                        CircularProgressIndicator()
                                        if (isVideo || progress > 0) OverlayPill("$progress%")
                                        OverlayPill(stringResource(R.string.cancel), Modifier.padding(top = 8.dp), dark = false) {
                                            running?.cancel()
                                        }
                                    }
                                } else if (failed || (isVideo && previewFailed)) {
                                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                        Text(stringResource(R.string.failed), Modifier.padding(horizontal = 12.dp))
                                        EditorButton(stringResource(R.string.editor_retry), true, true) {
                                            if (isVideo) {
                                                videoOutput = null
                                                videoRetry++
                                            } else rerender()
                                        }
                                    }
                                } else if (isVideo && (!videoReady || videoBuffering)) {
                                    Surface(shape = RoundedCornerShape(12.dp), color = paper) {
                                        Column(Modifier.padding(12.dp), horizontalAlignment = Alignment.CenterHorizontally,
                                            verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                            Text(stringResource(R.string.editor_preparing_preview), fontSize = 13.sp)
                                            LinearProgressIndicator(Modifier.width(144.dp))
                                        }
                                    }
                                }
                                if (swipeEnabled) {
                                    if (photoIndex > 0) {
                                        SwipeArrow(Modifier.align(Alignment.CenterStart).padding(start = 8.dp),
                                            R.drawable.tap_left, stringResource(R.string.editor_previous)) {
                                            switchPhoto(photoIndex - 1, viewWidth)
                                        }
                                    }
                                    if (photoIndex < photos.lastIndex) {
                                        SwipeArrow(Modifier.align(Alignment.CenterEnd).padding(end = 8.dp),
                                            R.drawable.tap_right, stringResource(R.string.editor_next)) {
                                            switchPhoto(photoIndex + 1, viewWidth)
                                        }
                                    }
                                }
                                Row(Modifier.align(Alignment.BottomCenter).fillMaxWidth().padding(12.dp),
                                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                                    verticalAlignment = Alignment.CenterVertically) {
                                    if (isVideo) {
                                        OverlayPill("${timeLabel(position)} / ${timeLabel(duration)}",
                                            icon = if (playing) R.drawable.tap_pause else R.drawable.tap_play,
                                            monospace = true, enabled = mediaReady) { playing = !playing }
                                        val audioLabel = when (audio) {
                                            EditorAudio.Original -> stringResource(R.string.editor_original_audio)
                                            EditorAudio.Mute -> stringResource(R.string.mute)
                                            EditorAudio.Voice -> stringResource(R.string.editor_voice)
                                        }
                                        val audioIcon = when (audio) {
                                            EditorAudio.Original -> R.drawable.tap_audio
                                            EditorAudio.Mute -> R.drawable.tap_mute
                                            EditorAudio.Voice -> R.drawable.tap_voice
                                        }
                                        OverlayPill(audioLabel, dark = false, canvasControl = true, icon = audioIcon, enabled = mediaReady) {
                                            updateVideoPreview()
                                            audio = EditorAudio.entries[(audio.ordinal + 1) % EditorAudio.entries.size]
                                        }
                                    } else if (swipeEnabled) {
                                        OverlayPill(stringResource(R.string.editor_swipe_hint, photoIndex + 1, photos.size), dark = true)
                                    }
                                    Spacer(Modifier.weight(1f))
                                    OverlayPill(stringResource(R.string.editor_reset), dark = false, canvasControl = true,
                                        icon = R.drawable.tap_refresh, enabled = mediaReady) {
                                        if (isVideo) {
                                            updateVideoPreview()
                                            video = video?.copy(edits = MaskEdits())
                                        } else {
                                            updatePhoto(checkNotNull(draft).copy(edits = MaskEdits(), faceStickers = emptyMap()))
                                            rerender()
                                        }
                                        notify(getString(R.string.editor_reset_done))
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
                                }, enabled = mediaReady, valueRange = 0f..duration.toFloat())
                        }
                        if (hasProject && style == MaskStyle.Sticker) {
                            val face = selectedFace
                            val current = draft
                            fun applySticker(sticker: String) {
                                if (face != null && current != null) {
                                    updatePhoto(current.copy(
                                        faceStickers = current.faceStickers + (face to sticker),
                                        edits = current.edits.copy(revealed = current.edits.revealed - face),
                                    ))
                                } else {
                                    emojiIndex = stickers.indexOf(sticker)
                                    if (current != null) updatePhoto(current.copy(faceStickers = emptyMap()))
                                }
                                if (isVideo) updateVideoPreview() else rerender()
                            }
                            StickerPanel(current?.faceStickers?.get(face) ?: emoji, face,
                                current?.edits?.revealed?.contains(face) == true, mediaReady,
                                onSelect = ::applySticker,
                                onShuffle = {
                                    if (face == null && current != null && !current.faces.isNullOrEmpty()) {
                                        updatePhoto(current.copy(
                                            faceStickers = current.faces.associate { it.id to stickers.random() },
                                            edits = current.edits.copy(revealed = emptySet()),
                                        ))
                                        rerender()
                                    } else applySticker(stickers.filter { it != (current?.faceStickers?.get(face) ?: emoji) }.random())
                                },
                                onReveal = {
                                    if (face != null && current != null) {
                                        val revealed = current.edits.revealed
                                        updatePhoto(current.copy(edits = current.edits.copy(
                                            revealed = if (face in revealed) revealed - face else revealed + face,
                                        )))
                                        rerender()
                                    }
                                },
                                onClear = { selectedFace = null },
                            )
                        }
                        if (hasProject) {
                            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                for (option in MaskStyle.entries) {
                                    val active = style == option
                                    val label = when (option) {
                                        MaskStyle.Mosaic -> stringResource(R.string.editor_pixelate)
                                        MaskStyle.Blur -> stringResource(R.string.editor_blur)
                                        MaskStyle.Sticker -> stringResource(R.string.editor_sticker)
                                    }
                                    val sub = when (option) {
                                        MaskStyle.Mosaic -> stringResource(R.string.editor_style_mosaic_sub)
                                        MaskStyle.Blur -> stringResource(R.string.editor_style_blur_sub)
                                        MaskStyle.Sticker -> stringResource(R.string.editor_style_sticker_sub, stickers.size)
                                    }
                                    val icon = when (option) {
                                        MaskStyle.Mosaic -> R.drawable.tap_grid
                                        MaskStyle.Blur -> R.drawable.tap_blur
                                        MaskStyle.Sticker -> R.drawable.tap_sticker
                                    }
                                    Surface(onClick = {
                                        if (style != option) {
                                            selectedFace = null
                                            style = option
                                            if (isVideo) updateVideoPreview() else rerender()
                                        }
                                    }, enabled = mediaReady, modifier = Modifier.weight(1f), shape = RoundedCornerShape(16.dp),
                                        color = if (active) paper else Color.White,
                                        border = BorderStroke(if (active) 2.dp else 1.dp, if (active) coral else pink),
                                        contentColor = if (active) apricotDark else brown) {
                                        Column(Modifier.padding(vertical = 8.dp, horizontal = 4.dp),
                                            horizontalAlignment = Alignment.CenterHorizontally,
                                            verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                            TapIcon(icon, modifier = Modifier.size(18.dp))
                                            Text(label, fontSize = 12.sp, fontWeight = FontWeight.Bold, maxLines = 1,
                                                overflow = TextOverflow.Ellipsis)
                                            Text(sub, fontSize = 10.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                        }
                                    }
                                }
                            }
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                            Button(onClick = { export(false) }, enabled = canExport, shape = pill,
                                modifier = Modifier.weight(1f).heightIn(min = 50.dp)) {
                                IconLabel(R.drawable.tap_download, stringResource(R.string.save))
                            }
                            Button(onClick = { export(true) }, enabled = canExport, colors = secondary, shape = pill,
                                modifier = Modifier.heightIn(min = 50.dp)) {
                                IconLabel(R.drawable.tap_share, stringResource(R.string.editor_share))
                            }
                        }
                        if (hasProject && !isVideo && photos.size > 1) {
                            Button(onClick = { export(false, photos) }, enabled = !busy, shape = pill, colors = secondary,
                                modifier = Modifier.fillMaxWidth()) {
                                Text(stringResource(R.string.editor_save_batch, photos.size))
                            }
                            batchResult?.let { (saved, failures) ->
                                Text(stringResource(R.string.editor_batch_result, saved, failures), color = brown, fontSize = 12.sp)
                            }
                            if (failedExports.isNotEmpty()) {
                                TextButton(onClick = { export(false, photos.filter { it.uri in failedExports }) }, enabled = !busy) {
                                    Text(stringResource(R.string.editor_retry_failed, failedExports.size))
                                }
                            }
                        }
                    }
                }
                if (feedback.isNotEmpty()) {
                    OverlayPill(feedback, Modifier.align(Alignment.TopCenter).widthIn(max = 320.dp).padding(top = 8.dp), toast = true)
                }
            }
        }
        if (settingsOpen) {
            val locale = resources.configuration.locales[0]
            val language = when (locale.language) {
                "zh" -> if (locale.country in listOf("TW", "HK", "MO") || locale.script == "Hant") "zh-TW" else "zh-CN"
                "ja" -> "ja"
                else -> "en"
            }
            SettingsPanel(language, !hasProject, onLanguage = { tag ->
                if (tag != language) {
                    getSharedPreferences("editor_settings", MODE_PRIVATE).edit().putString("language", tag).apply()
                    recreate()
                }
            }, onClose = { settingsOpen = false })
        }
        if (lifetimeOpen) LifetimePanel { lifetimeOpen = false }
        if (saveOpen) SavePanel(progress, savedExport, saveError, onClose = {
            if (saving) running?.cancel()
            saveOpen = false
        }, onRetry = {
            if (saveBatchRequest) {
                val retry = if (savedExport != null) photos.filter { it.uri in failedExports } else photos
                if (retry.isNotEmpty()) export(false, retry)
            } else export(false)
        }, onShare = { uri, isVideoResult ->
            shareUri(uri, if (isVideoResult) "video/mp4" else "image/jpeg")
        }, onCopy = { uri, isVideoResult ->
            copySource = uri
            val name = "TapHide-${System.currentTimeMillis()}"
            if (isVideoResult) copyMovie.launch("$name.mp4") else copyPhoto.launch("$name.jpg")
        }, enabled = !busy)

    }

    private fun isVideoUri(uri: Uri): Boolean = contentResolver.getType(uri)?.startsWith("video/") == true

    @Composable
    private fun SwipeArrow(modifier: Modifier, icon: Int, description: String, onClick: () -> Unit) {
        Surface(onClick = onClick, modifier = modifier.size(32.dp), shape = CircleShape,
            color = Color.Black.copy(alpha = 0.4f), contentColor = Color.White) {
            Box(contentAlignment = Alignment.Center) { TapIcon(icon, description, Modifier.size(14.dp)) }
        }
    }

    @Composable
    private fun EditorButton(label: String, active: Boolean, enabled: Boolean, modifier: Modifier = Modifier,
        compact: Boolean = false, icon: Int? = null, onClick: () -> Unit) {
        Button(onClick, modifier, enabled, colors = ButtonDefaults.buttonColors(
            containerColor = if (active) coral else pink, contentColor = if (active) Color.White else brown,
        ), contentPadding = PaddingValues(horizontal = if (compact) 3.dp else 5.dp, vertical = 8.dp)) {
            if (compact && icon != null) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    TapIcon(icon)
                    Text(label, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                }
            } else if (icon != null) IconLabel(icon, label)
            else Text(label, fontSize = 13.sp, fontWeight = FontWeight.Bold)
        }
    }

    @Composable
    private fun OverlayPill(label: String, modifier: Modifier = Modifier, dark: Boolean = true,
        enabled: Boolean = true, transparent: Boolean = false, monospace: Boolean = false,
        canvasControl: Boolean = false, toast: Boolean = false, icon: Int? = null, iconDescription: String? = null, onClick: (() -> Unit)? = null) {
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
            Row(Modifier.padding(horizontal = if (toast) 16.dp else 8.dp, vertical = if (toast) 8.dp else 6.dp),
                horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                if (icon != null) TapIcon(icon, iconDescription, Modifier.size(13.dp))
                if (label.isNotEmpty()) Text(label, fontSize = if (toast) 12.sp else 11.sp,
                    fontFamily = if (monospace) FontFamily.Monospace else FontFamily.Default,
                    fontWeight = FontWeight.SemiBold)
            }
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
                    val overrides = if (style == MaskStyle.Sticker) {
                        faces.mapNotNull { face -> draft.faceStickers[face.id]?.let { face.box to it } }.toMap()
                    } else emptyMap()
                    val rendered = renderEditorPhoto(source, draft.edits.masks(faces), style, emoji, overrides)
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
        progress: (Int) -> Unit): PhotoExport {
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
        return PhotoExport(saved, failures)
    }

    private suspend fun saveVideo(file: File): Uri {
        var saved: Uri? = null
        try {
            withContext(Dispatchers.IO) {
                saved = saveMedia(true) { copyVideo(file, it) }
            }
            return checkNotNull(saved)
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
        file.inputStream().use { input -> copyStream(input, destination) }
    }

    private suspend fun copyStream(input: java.io.InputStream, destination: java.io.OutputStream) {
        val context = currentCoroutineContext()
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        while (true) {
            context.ensureActive()
            val read = input.read(buffer)
            if (read == -1) break
            destination.write(buffer, 0, read)
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
        shareUri(FileProvider.getUriForFile(this, "$packageName.editor-share", file), mime)
    }

    private fun shareUri(uri: Uri, mime: String) {
        startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
            type = mime
            putExtra(Intent.EXTRA_STREAM, uri)
            clipData = ClipData.newRawUri("TapHide", uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }, null))
    }

    override fun onStop() {
        running?.cancel()
        activityStarted = false
        visiblePlayer?.pause()
        super.onStop()
    }

    override fun onStart() {
        super.onStart()
        activityStarted = true
    }

    override fun onDestroy() {
        running?.cancel()
        super.onDestroy()
    }
}
