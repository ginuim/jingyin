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
import android.util.LruCache
import android.view.LayoutInflater
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
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
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.calculateCentroid
import androidx.compose.foundation.gestures.calculatePan
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.gestures.detectDragGestures
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
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
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
import kotlin.math.roundToInt

@Composable
private fun PhotoPagePicker(
    photos: List<Uri>,
    current: Int,
    reviewed: Set<Uri>,
    failedExports: Set<Uri>,
    enabled: Boolean,
    onSelect: (Int) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    val resolver = LocalContext.current.contentResolver

    Box {
        OutlinedButton(
            onClick = { expanded = true },
            enabled = enabled,
            shape = pill,
            contentPadding = PaddingValues(horizontal = 12.dp),
            border = BorderStroke(1.dp, if (expanded) coralDeep else line),
            colors = ButtonDefaults.outlinedButtonColors(
                containerColor = if (expanded) pink else paper,
                contentColor = coralDeep,
            ),
        ) {
            IconLabel(R.drawable.tap_photos, stringResource(R.string.editor_photo_page, current + 1, photos.size))
        }
        DropdownMenu(expanded = expanded && enabled, onDismissRequest = { expanded = false },
            modifier = Modifier.width(if (photos.size == 2) 192.dp else 284.dp).heightIn(max = 360.dp),
            shape = RoundedCornerShape(18.dp),
            containerColor = paper,
            border = BorderStroke(1.dp, line),
        ) {
            photos.withIndex().chunked(3).forEach { row ->
                Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp),
                    horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    row.forEach { (index, uri) ->
                        key(uri) {
                            val thumbnail by produceState<Bitmap?>(null, uri) {
                                value = withContext(Dispatchers.IO) {
                                    try {
                                        ImageDecoder.decodeBitmap(ImageDecoder.createSource(resolver, uri)) { decoder, info, _ ->
                                            val sample = ceil(maxOf(info.size.width, info.size.height) / 240.0).toInt()
                                            decoder.setTargetSampleSize(sample.coerceAtLeast(1))
                                            decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                                        }
                                    } catch (_: java.io.IOException) {
                                        null
                                    } catch (_: SecurityException) {
                                        null
                                    }
                                }
                            }
                            val status = when (uri) {
                                in failedExports -> R.string.editor_photo_export_failed
                                in reviewed -> R.string.editor_photo_reviewed
                                else -> R.string.editor_photo_needs_review
                            }
                            Surface(
                                onClick = { expanded = false; onSelect(index) },
                                modifier = Modifier.width(86.dp).semantics { selected = index == current },
                                shape = RoundedCornerShape(8.dp),
                                color = if (index == current) pink else paper,
                                border = BorderStroke(1.dp, if (index == current) coralDeep else line),
                            ) {
                                Column(Modifier.padding(4.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                                    Box(Modifier.fillMaxWidth().height(56.dp).clip(RoundedCornerShape(5.dp))
                                        .background(Color(0xFFEFE2DC)), contentAlignment = Alignment.Center) {
                                        thumbnail?.let {
                                            Image(it.asImageBitmap(), contentDescription = null,
                                                modifier = Modifier.fillMaxSize(), contentScale = ContentScale.Fit)
                                        } ?: TapIcon(R.drawable.tap_photos)
                                    }
                                    Text(stringResource(R.string.editor_photo_tile, index + 1, stringResource(status)),
                                        color = ink, fontSize = 10.sp, lineHeight = 13.sp,
                                        textAlign = TextAlign.Center)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun BoxScope.MaskSelectionControls(
    selection: MaskSelection,
    box: FaceBox,
    left: Float,
    top: Float,
    imageWidth: Float,
    imageHeight: Float,
    viewWidth: Float,
    viewHeight: Float,
    onDelete: () -> Unit,
    onTransform: (FaceBox) -> Unit,
) {
    var scale by remember(selection, box) { mutableFloatStateOf(1f) }
    val commitTransform by rememberUpdatedState(onTransform)
    var movement by remember(selection, box) { mutableStateOf(Offset.Zero) }
    fun displayedBox() = box.copy(
        cx = (box.cx + movement.x / imageWidth).coerceIn(0f, 1f),
        cy = (box.cy + movement.y / imageHeight).coerceIn(0f, 1f),
        rx = box.rx * scale, ry = box.ry * scale,
    )
    val displayed = displayedBox()
    val right = left + (displayed.cx + displayed.rx) * imageWidth
    val upper = top + (displayed.cy - displayed.ry) * imageHeight
    val bottom = top + (displayed.cy + displayed.ry) * imageHeight
    val density = LocalDensity.current
    val halfTarget = with(density) { 24.dp.toPx() }
    fun handleOffset(y: Float) = IntOffset(
        (right - halfTarget).coerceIn(0f, (viewWidth - 2 * halfTarget).coerceAtLeast(0f)).roundToInt(),
        (y - halfTarget).coerceIn(0f, (viewHeight - 2 * halfTarget).coerceAtLeast(0f)).roundToInt(),
    )

    Canvas(Modifier.matchParentSize()) {
        drawRect(coral, Offset(left + (displayed.cx - displayed.rx) * imageWidth, upper),
            Size(displayed.rx * 2 * imageWidth, displayed.ry * 2 * imageHeight),
            style = Stroke(2.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(6f, 5f))))
    }
    val hitLeft = (left + (displayed.cx - displayed.rx) * imageWidth).coerceIn(0f, viewWidth)
    val hitTop = upper.coerceIn(0f, viewHeight)
    val hitWidth = (right.coerceIn(0f, viewWidth) - hitLeft).coerceAtLeast(0f)
    val hitHeight = (bottom.coerceIn(0f, viewHeight) - hitTop).coerceAtLeast(0f)
    Box(Modifier.offset { IntOffset(hitLeft.roundToInt(), hitTop.roundToInt()) }
        .size(with(density) { hitWidth.toDp() }, with(density) { hitHeight.toDp() })
        .pointerInput(selection, box, imageWidth, imageHeight) {
            detectDragGestures(
                onDragCancel = { movement = Offset.Zero },
                onDragEnd = {
                    if (movement != Offset.Zero) commitTransform(displayedBox())
                    movement = Offset.Zero
                },
                onDrag = { change, amount ->
                    change.consume()
                    movement += amount
                },
            )
        })
    Box(
        Modifier.offset { handleOffset(maxOf(bottom, upper + 2 * halfTarget)) }.size(48.dp)
            .pointerInput(selection, box, imageWidth, imageHeight) {
                val radius = Offset(box.rx * imageWidth, box.ry * imageHeight)
                val minScale = (12.dp.toPx() / minOf(radius.x, radius.y)).coerceAtMost(1f)
                val maxScale = 1f / maxOf(box.rx, box.ry)
                var drag = Offset.Zero
                detectDragGestures(
                    onDragStart = { drag = Offset.Zero },
                    onDragCancel = { scale = 1f },
                    onDragEnd = {
                        if (scale != 1f) commitTransform(box.copy(rx = box.rx * scale, ry = box.ry * scale))
                        scale = 1f
                    },
                    onDrag = { change, amount ->
                        change.consume()
                        drag += amount
                        val projection = (drag.x * radius.x + drag.y * radius.y) / radius.getDistanceSquared()
                        scale = (1f + projection).coerceIn(minScale, maxScale)
                    },
                )
            },
        contentAlignment = Alignment.Center,
    ) {
        Box(Modifier.size(16.dp).background(coral, CircleShape).border(2.dp, Color.White, CircleShape))
    }
    IconButton(onClick = onDelete, modifier = Modifier.offset { handleOffset(upper) }.size(48.dp)) {
        Box(Modifier.size(28.dp).background(roseDeep, CircleShape), contentAlignment = Alignment.Center) {
            Icon(androidx.compose.ui.res.painterResource(R.drawable.tap_close),
                stringResource(R.string.editor_delete_mask), tint = Color.White, modifier = Modifier.size(16.dp))
        }
    }
}

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
    val analysis: Detection? = null,
    val edits: MaskEdits = MaskEdits(),
    val faceStickers: Map<Int, String> = emptyMap(),
)

private val PhotoDraft.faces get() = analysis?.faces?.mapIndexed(::PhotoFace)

private data class PhotoPreviewKey(
    val edits: MaskEdits,
    val faceStickers: Map<Int, String>,
    val style: MaskStyle,
    val emoji: String,
    val targets: Set<SubjectTarget>,
    val strengths: EffectStrengths,
)

private data class CachedPhotoPreview(val key: PhotoPreviewKey, val bitmap: Bitmap)

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
        // Draw behind the system bars so the status-bar strip matches the app
        // background instead of showing an empty theme-colored band.
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.light(android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.light(android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT),
        )
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
        var targets by remember { mutableStateOf(setOf(SubjectTarget.Face)) }
        var pendingTargets by remember { mutableStateOf<Set<SubjectTarget>?>(null) }
        var confirmRemove by remember { mutableStateOf(false) }
        val silhouettesAvailable = applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0
        var photos by remember { mutableStateOf(emptyList<PhotoDraft>()) }
        var photoIndex by remember { mutableIntStateOf(0) }
        var pendingPhoto by remember { mutableStateOf<Int?>(null) }
        var video by remember { mutableStateOf<VideoDraft?>(null) }
        val isVideo = video != null
        val hasProject = isVideo || photos.isNotEmpty()
        val editorSettings = remember { getSharedPreferences("editor_settings", MODE_PRIVATE) }
        var strengths by remember {
            mutableStateOf(EffectStrengths(
                mosaic = editorSettings.getFloat("mosaic_strength", 1f).coerceIn(effectStrengthRange),
                blur = editorSettings.getFloat("blur_strength", 1f).coerceIn(effectStrengthRange),
            ))
        }
        var strengthOpen by remember { mutableStateOf(false) }
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
        var selection by remember { mutableStateOf<MaskSelection?>(null) }
        val selectedFace = (selection as? MaskSelection.Automatic)?.id
        var failed by remember { mutableStateOf(false) }
        var feedback by remember { mutableStateOf("") }
        var feedbackRevision by remember { mutableIntStateOf(0) }
        var rippleAt by remember { mutableStateOf<Offset?>(null) }
        var rippleRevision by remember { mutableIntStateOf(0) }
        val ripple = remember { Animatable(1f) }
        val draft = photos.getOrNull(photoIndex)
        var seekPosition by remember { mutableStateOf<Float?>(null) }
        var infoOpen by remember { mutableStateOf(false) }
        val emoji = stickers[emojiIndex]
        val photoPreviews = remember {
            val maxBytes = minOf(32L * 1024 * 1024, Runtime.getRuntime().maxMemory() / 6).toInt()
            // Let the bitmap live while either the cache or a Compose frame still references it.
            object : LruCache<Uri, CachedPhotoPreview>(maxBytes) {
                override fun sizeOf(key: Uri, value: CachedPhotoPreview) = value.bitmap.allocationByteCount
            }
        }
        fun previewKey(item: PhotoDraft) = PhotoPreviewKey(item.edits, item.faceStickers, style, emoji, targets, strengths)
        fun cachedPreview(item: PhotoDraft) =
            photoPreviews.get(item.uri)?.takeIf { it.key == previewKey(item) }?.bitmap
        val secondary = ButtonDefaults.buttonColors(containerColor = pink, contentColor = brown)
        fun notify(message: String) {
            feedback = message
            feedbackRevision++
        }
        fun updatePhoto(replacement: PhotoDraft) {
            photos = photos.map { if (it.uri == replacement.uri) replacement else it }
        }
        fun closeProject() {
            strengthOpen = false
            photoPreviews.evictAll()
            photos = emptyList()
            pendingPhoto = null
            photoIndex = 0
            video = null
            photo = null
            videoOutput = null
            seekPosition = null
            failedExports = emptySet()
            batchResult = null
            batchItems = emptyList()
            selection = null
            savedExport = null
            saveOpen = false
            analyzeBatch = false
            feedback = ""
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
        val videoOptions = video?.let { VideoMaskOptions(style, emoji, it.edits.manual, it.edits.inverted, targets, strengths) }
        val previewEffect = remember(sourceUri, videoRetry) {
            FacePixelEffect(FrameMetrics(), videoOptions)
        }
        DisposableEffect(sourceUri, checkedVideo) {
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

                        override fun onPlayerError(error: PlaybackException) {
                            android.util.Log.w("TapHide", "Video preview failed", error)
                            previewFailed = true
                        }
                    })
                    previewEffect.updateOptions(videoOptions)
                    setVideoEffects(listOf(previewEffect))
                    setMediaItem(MediaItem.fromUri(sourceUri), position)
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
        LaunchedEffect(player, videoOptions) {
            val active = player ?: return@LaunchedEffect
            if (previewEffect.updateOptions(videoOptions) && !active.isPlaying) {
                active.seekTo(active.currentPosition)
            }
        }
        LaunchedEffect(player, playing, busy, activityStarted) {
            player?.playWhenReady = playing && !busy && activityStarted
        }
        LaunchedEffect(player, audio) {
            player?.apply {
                volume = if (audio == EditorAudio.Mute) 0f else 1f
                playbackParameters = PlaybackParameters(1f, if (audio == EditorAudio.Voice) 1.32f else 1f)
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
            startWork {
                var renderedCurrent = false
                try {
                    val batch = if (analyzeBatch) photos else listOf(currentPhoto)
                    analyzeBatch = false
                    for ((index, item) in batch.withIndex()) {
                        try {
                            if (item.uri == currentPhoto.uri) {
                                val key = previewKey(item)
                                val cached = cachedPreview(item)
                                photo = if (cached != null) cached else {
                                    val (bitmap, analysis) = renderPhoto(item, style, emoji, targets, strengths, preview = true)
                                    updatePhoto(item.copy(analysis = analysis))
                                    photoPreviews.put(item.uri, CachedPhotoPreview(key, bitmap))
                                    bitmap
                                }
                                renderedCurrent = true
                            } else {
                                updatePhoto(item.copy(analysis = detectPhoto(item.uri, targets)))
                            }
                        } catch (cancelled: CancellationException) {
                            throw cancelled
                        } catch (error: Exception) {
                            android.util.Log.w("TapHide", "Photo could not be analyzed", error)
                        }
                        progress = (index + 1) * 100 / batch.size
                    }
                } finally {
                    failed = !renderedCurrent
                }
            }
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
                            VideoMaskOptions(style, emoji, currentVideo.edits.manual, currentVideo.edits.inverted, targets, strengths),
                            VideoPurpose.FullExport) { progress = it }.file.also {
                            position = player?.currentPosition ?: position
                            videoOutput = it
                        }
                        if (share) shareFile(stageShare("mp4") { stream -> copyVideo(file, stream) }, "video/mp4")
                        else savedExport = SavedExport(listOf(saveVideo(file)), video = true)
                    }
                    share -> {
                        val (rendered, _) = renderPhoto(checkNotNull(draft), style, emoji, targets, strengths)
                        try {
                            val file = stageShare("jpg") { stream ->
                                check(rendered.compress(Bitmap.CompressFormat.JPEG, 95, stream))
                            }
                            shareFile(file, "image/jpeg")
                        } finally { rendered.recycle() }
                    }
                    batch != null -> {
                        val retrying = batch.size < photos.size
                        val result = savePhotos(batch, style, emoji, targets, strengths) { progress = it }
                        batchItems = (if (retrying) batchItems else emptyList()) + result.saved
                        failedExports = result.failed
                        batchResult = batchItems.size to result.failed.size
                        savedExport = SavedExport(batchItems, video = false, failures = result.failed.size)
                    }
                    else -> {
                        val result = savePhotos(listOf(checkNotNull(draft)), style, emoji, targets, strengths) { progress = it }
                        check(result.failed.isEmpty())
                        savedExport = SavedExport(result.saved, video = false)
                    }
                }
            }
        }

        val mediaRequest = PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageAndVideo)
        val mediaReady = !busy && (!isVideo || videoReady)
        val swipeEnabled = hasProject && !isVideo && photos.size > 1 && !busy
        val canExport = !busy && !failed && (if (isVideo) videoReady else photo != null)
        fun applyTargets(next: Set<SubjectTarget>) {
            pendingPhoto = null
            selection = null
            targets = next
            if (SubjectTarget.Face !in next && style == MaskStyle.Sticker) style = MaskStyle.Mosaic
            photoPreviews.evictAll()
            failedExports = emptySet()
            batchResult = null
            batchItems = emptyList()
            photos = photos.map { PhotoDraft(it.uri) }
            video = video?.copy(edits = MaskEdits())
            if (isVideo) updateVideoPreview() else if (hasProject) rerender()
        }
        fun removeCurrent() {
            if (isVideo || photos.size <= 1) {
                closeProject()
                return
            }
            pendingPhoto = null
            selection = null
            val uri = checkNotNull(draft).uri
            photoPreviews.remove(uri)
            failedExports = failedExports - uri
            batchResult = null
            batchItems = emptyList()
            photos = photos.filterIndexed { index, _ -> index != photoIndex }
            photoIndex = photoIndex.coerceAtMost(photos.lastIndex)
            photo = null
            rerender()
        }

        fun showPhoto(target: Int, bitmap: Bitmap) {
            pendingPhoto = null
            selection = null
            failed = false
            photoIndex = target
            photo = bitmap
        }

        fun switchPhoto(target: Int) {
            if (target !in photos.indices) {
                notify(getString(if (target < 0) R.string.editor_first_photo else R.string.editor_last_photo))
                return
            }
            if (target == photoIndex) {
                pendingPhoto = null
                return
            }
            val cached = cachedPreview(photos[target])
            if (cached != null && !busy) showPhoto(target, cached)
            else pendingPhoto = target
        }

        val photoUris = photos.map { it.uri }
        var reviewedPhotos by remember(photoUris, targets, style, emoji, strengths) {
            mutableStateOf(emptySet<Uri>())
        }
        LaunchedEffect(draft?.uri, photo, busy, failed, targets, style, emoji, strengths) {
            if (photo != null && !busy && !failed) {
                draft?.uri?.let { reviewedPhotos = reviewedPhotos + it }
            }
        }
        var addingMask by remember(sourceUri, draft?.uri) { mutableStateOf(false) }
        var photoZoom by remember(draft?.uri) { mutableFloatStateOf(1f) }
        var photoPan by remember(draft?.uri) { mutableStateOf(Offset.Zero) }
        val canSwipe by rememberUpdatedState(!strengthOpen && !addingMask && photoZoom == 1f)
        val swipeIndex by rememberUpdatedState(pendingPhoto ?: photoIndex)
        val switchPhotoOnSwipe by rememberUpdatedState(::switchPhoto)
        LaunchedEffect(pendingPhoto, renderRevision, style, emoji, targets, strengths, busy) {
            val target = pendingPhoto ?: return@LaunchedEffect
            if (busy) return@LaunchedEffect
            val item = photos.getOrNull(target) ?: return@LaunchedEffect
            val key = previewKey(item)
            val cached = cachedPreview(item)
            if (cached != null) {
                showPhoto(target, cached)
                return@LaunchedEffect
            }
            val revision = renderRevision
            try {
                val (bitmap, analysis) = renderPhoto(item, style, emoji, targets, strengths, preview = true)
                if (pendingPhoto != target || renderRevision != revision || busy) {
                    bitmap.recycle()
                    return@LaunchedEffect
                }
                updatePhoto(item.copy(analysis = analysis))
                photoPreviews.put(item.uri, CachedPhotoPreview(key, bitmap))
                showPhoto(target, bitmap)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                android.util.Log.w("TapHide", "Photo could not be opened", error)
                notify(getString(R.string.failed))
            }
            pendingPhoto = null
        }

        Surface(Modifier.fillMaxSize(), color = Color(0xFFF4E6E0)) {
            // Keep the horizontal and navigation-bar insets, but drop the top
            // inset: the app surface then reaches up under the status bar and
            // the content clears the clock via statusBarsPadding() below.
            BoxWithConstraints(
                Modifier.fillMaxSize()
                    .windowInsetsPadding(WindowInsets(0, 0, 0, 0).only(WindowInsetsSides.Horizontal + WindowInsetsSides.Bottom)),
                contentAlignment = Alignment.TopCenter,
            ) {
                val framed = maxWidth >= 640.dp
                Surface(
                    Modifier.widthIn(max = 400.dp).fillMaxWidth()
                        .then(if (framed) Modifier.padding(vertical = 20.dp) else Modifier.fillMaxHeight()),
                    shape = if (framed) RoundedCornerShape(38.dp) else RoundedCornerShape(0.dp),
                    border = if (framed) BorderStroke(6.dp, Color.White) else null,
                    shadowElevation = if (framed) 16.dp else 0.dp,
                    color = paper,
                ) {
                    Column(Modifier.verticalScroll(rememberScrollState()).statusBarsPadding()
                        .padding(horizontal = 20.dp, vertical = 20.dp),
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

                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalAlignment = Alignment.CenterVertically) {
                            Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(8.dp),
                                verticalAlignment = Alignment.CenterVertically) {
                                SubjectPicker(targets, silhouettesAvailable, enabled = !busy, modifier = Modifier.weight(1f, fill = false)) { next ->
                                    val customized = photos.any { it.edits != MaskEdits() || it.faceStickers.isNotEmpty() } ||
                                        video?.edits?.let { it != MaskEdits() } == true
                                    if (customized) pendingTargets = next else applyTargets(next)
                                }
                                if (hasProject) {
                                    Surface(onClick = ::closeProject, enabled = !busy, shape = pill,
                                        border = BorderStroke(1.dp, line), color = paper, contentColor = brown) {
                                        Box(Modifier.heightIn(min = editorToolbarButtonHeight).padding(horizontal = 12.dp),
                                            contentAlignment = Alignment.Center) {
                                            Text(stringResource(R.string.editor_clear), fontSize = 13.sp, fontWeight = FontWeight.Bold)
                                        }
                                    }
                                }
                            }
                            if (photoUris.size > 1) {
                                PhotoPagePicker(photoUris, photoIndex, reviewedPhotos, failedExports, !busy, ::switchPhoto)
                            }
                        }
                        if (!hasProject) {
                            Text(stringResource(R.string.editor_limit_hint),
                                color = mutedInk, fontSize = 11.sp, lineHeight = 16.sp)
                        }

                        Surface(Modifier.fillMaxWidth().aspectRatio(4f / 5f), shape = RoundedCornerShape(16.dp),
                            color = if (isVideo) Color(0xFF211C1A) else Color(0xFFEFE2DC), border = BorderStroke(1.dp, line)) {
                            if (!hasProject) {
                                EmptyCanvas(enabled = !busy) { pickMedia.launch(mediaRequest) }
                            } else BoxWithConstraints(
                                Modifier.fillMaxSize().then(if (swipeEnabled) Modifier.pointerInput(Unit) {
                                    var total = 0f
                                    detectHorizontalDragGestures(
                                        onDragStart = { total = 0f },
                                        onHorizontalDrag = { change, dragAmount ->
                                            if (canSwipe) {
                                                change.consume()
                                                total += dragAmount
                                            }
                                        },
                                        onDragEnd = {
                                            if (!canSwipe || total == 0f) return@detectHorizontalDragGestures
                                            val threshold = size.width * 0.18f
                                            val current = swipeIndex
                                            val target = when {
                                                total <= -threshold -> current + 1
                                                total >= threshold -> current - 1
                                                else -> current
                                            }
                                            switchPhotoOnSwipe(target)
                                        },
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
                                val fittedWidth = mediaWidth * aspectScale
                                val fittedHeight = mediaHeight * aspectScale
                                val imageWidth = fittedWidth * photoZoom
                                val imageHeight = fittedHeight * photoZoom
                                val left = (viewWidth - imageWidth) / 2 + photoPan.x
                                val top = (viewHeight - imageHeight) / 2 + photoPan.y

                                fun applyEdits(next: MaskEdits) {
                                    if (isVideo) {
                                        updateVideoPreview()
                                        video = video?.copy(edits = next)
                                    } else {
                                        updatePhoto(checkNotNull(draft).copy(edits = next))
                                        rerender()
                                    }
                                }

                                val photoTransform = if (isVideo || photo == null) Modifier else {
                                    Modifier.pointerInput(draft?.uri, fittedWidth, fittedHeight, viewWidth, viewHeight) {
                                        awaitEachGesture {
                                            var transforming = false
                                            do {
                                                val event = awaitPointerEvent(PointerEventPass.Initial)
                                                if (event.changes.count { it.pressed } >= 2) {
                                                    transforming = true
                                                    val zoom = (photoZoom * event.calculateZoom()).coerceIn(1f, 4f)
                                                    val focus = event.calculateCentroid(useCurrent = false)
                                                    if (focus != Offset.Unspecified) {
                                                        val anchor = focus - Offset(viewWidth / 2, viewHeight / 2)
                                                        val pan = anchor + (photoPan - anchor) * (zoom / photoZoom) + event.calculatePan()
                                                        val maxX = ((fittedWidth * zoom - viewWidth) / 2).coerceAtLeast(0f)
                                                        val maxY = ((fittedHeight * zoom - viewHeight) / 2).coerceAtLeast(0f)
                                                        photoPan = Offset(pan.x.coerceIn(-maxX, maxX), pan.y.coerceIn(-maxY, maxY))
                                                        photoZoom = zoom
                                                    }
                                                }
                                                if (transforming) event.changes.forEach { it.consume() }
                                            } while (event.changes.any { it.pressed })
                                        }
                                    }
                                }
                                Box(Modifier.fillMaxSize().then(photoTransform)) {
                                    if (isVideo) {
                                        player?.takeUnless { previewFailed }?.let { active ->
                                            AndroidView(factory = {
                                                (LayoutInflater.from(it).inflate(R.layout.editor_video, null) as PlayerView)
                                                    .apply { setKeepContentOnPlayerReset(true); player = active }
                                            }, update = { it.player = active }, onRelease = { it.player = null },
                                                modifier = Modifier.fillMaxSize())
                                        }
                                    } else {
                                        photo?.let { Image(it.asImageBitmap(), stringResource(R.string.result),
                                            Modifier.fillMaxSize().graphicsLayer {
                                                scaleX = photoZoom
                                                scaleY = photoZoom
                                                translationX = photoPan.x
                                                translationY = photoPan.y
                                            }, contentScale = ContentScale.Fit) }
                                    }

                                    val edits = video?.edits ?: draft?.edits
                                    val faces = draft?.faces.orEmpty()
                                    if (imageWidth > 0 && imageHeight > 0 && mediaReady && edits != null && !strengthOpen) {
                                        val tapAction by rememberUpdatedState<(Offset) -> Unit> { point ->
                                            val x = (point.x - left) / imageWidth
                                            val y = (point.y - top) / imageHeight
                                            if (x !in 0f..1f || y !in 0f..1f) {
                                                selection = null
                                                return@rememberUpdatedState
                                            }
                                            if (!addingMask) {
                                                selection = edits.hitTest(x, y, faces)
                                            } else if (edits.manual.size >= 32) {
                                                notify(getString(R.string.editor_mask_limit))
                                            } else {
                                                addingMask = false
                                                selection = MaskSelection.Manual(edits.manual.size)
                                                applyEdits(edits.copy(manual = edits.manual + FaceBox(x, y, 0.13f, 0.1f)))
                                                notify(getString(R.string.editor_added))
                                                rippleAt = point
                                                rippleRevision++
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
                                    }
                                    val activeSelection = selection
                                    val selectedBox = edits?.boxFor(activeSelection, faces)
                                    if (activeSelection != null && selectedBox != null && mediaReady &&
                                        imageWidth > 0 && imageHeight > 0) {
                                        MaskSelectionControls(
                                            activeSelection, selectedBox, left, top, imageWidth, imageHeight, viewWidth, viewHeight,
                                            onDelete = {
                                                selection = null
                                                applyEdits(edits.remove(activeSelection))
                                                notify(getString(R.string.editor_removed))
                                            },
                                            onTransform = { applyEdits(edits.transform(activeSelection, it)) },
                                        )
                                    }
                                }
                                val canvasEdits = video?.edits ?: draft?.edits
                                if (canvasEdits != null) {
                                    Column(Modifier.align(Alignment.TopStart).padding(10.dp),
                                        verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                            OverlayPill(stringResource(R.string.editor_remove_media), dark = false,
                                                canvasControl = true, enabled = !busy, icon = R.drawable.tap_close) {
                                                pendingPhoto = null
                                                confirmRemove = true
                                            }
                                            if (style != MaskStyle.Sticker) {
                                                OverlayPill(stringResource(R.string.editor_effect_strength),
                                                    dark = strengthOpen, canvasControl = !strengthOpen,
                                                    enabled = mediaReady, icon = R.drawable.tap_settings) {
                                                    strengthOpen = !strengthOpen
                                                }
                                            }
                                            OverlayPill(stringResource(R.string.editor_invert_mask), dark = canvasEdits.inverted,
                                                canvasControl = !canvasEdits.inverted, enabled = mediaReady && (isVideo || photo != null)) {
                                                applyEdits(canvasEdits.copy(inverted = !canvasEdits.inverted))
                                            }
                                            OverlayPill(
                                                label = "",
                                                dark = addingMask,
                                                canvasControl = !addingMask,
                                                enabled = mediaReady,
                                                icon = R.drawable.tap_add,
                                                iconDescription = stringResource(R.string.editor_add_mask),
                                                modifier = Modifier.semantics { selected = addingMask },
                                            ) {
                                                addingMask = !addingMask
                                                selection = null
                                                strengthOpen = false
                                            }
                                        }
                                        if (strengthOpen && style != MaskStyle.Sticker) {
                                            val isBlur = style == MaskStyle.Blur
                                            val savedStrength = if (isBlur) strengths.blur else strengths.mosaic
                                            StrengthPopup(style, savedStrength, mediaReady, onDismiss = { strengthOpen = false }) { value ->
                                                if (value != savedStrength) {
                                                    strengths = if (isBlur) strengths.copy(blur = value) else strengths.copy(mosaic = value)
                                                    editorSettings.edit()
                                                        .putFloat(if (isBlur) "blur_strength" else "mosaic_strength", value).apply()
                                                    if (isVideo) updateVideoPreview() else rerender()
                                                }
                                            }
                                        }
                                    }
                                }
                                if (pendingPhoto != null && !busy) {
                                    LinearProgressIndicator(Modifier.align(Alignment.BottomCenter).fillMaxWidth())
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
                                } else if (isVideo && !videoReady) {
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
                                            switchPhoto(photoIndex - 1)
                                        }
                                    }
                                    if (photoIndex < photos.lastIndex) {
                                        SwipeArrow(Modifier.align(Alignment.CenterEnd).padding(end = 8.dp),
                                            R.drawable.tap_right, stringResource(R.string.editor_next)) {
                                            switchPhoto(photoIndex + 1)
                                        }
                                    }
                                }
                                if (!isVideo) {
                                    // Download just the current photo, independent of the batch button below.
                                    Surface(onClick = { export(false) }, enabled = canExport, shape = CircleShape,
                                        color = Color.Black.copy(alpha = 0.4f), contentColor = Color.White,
                                        modifier = Modifier.align(Alignment.TopEnd).padding(end = 10.dp, top = 10.dp)) {
                                        Box(contentAlignment = Alignment.Center, modifier = Modifier.size(32.dp)) {
                                            TapIcon(R.drawable.tap_download, stringResource(R.string.save), Modifier.size(14.dp))
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
                                    }
                                    Spacer(Modifier.weight(1f))
                                    OverlayPill(stringResource(R.string.editor_reset), dark = false, canvasControl = true,
                                        icon = R.drawable.tap_refresh, enabled = mediaReady) {
                                        selection = null
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
                        val stickersAvailable = SubjectTarget.Face in targets
                        if (hasProject && stickersAvailable && style == MaskStyle.Sticker) {
                            val face = selectedFace
                            val current = draft
                            fun applySticker(sticker: String) {
                                if (face != null && current != null) {
                                    updatePhoto(current.copy(
                                        faceStickers = current.faceStickers + (face to sticker),
                                    ))
                                } else {
                                    emojiIndex = stickers.indexOf(sticker)
                                    if (current != null) updatePhoto(current.copy(faceStickers = emptyMap()))
                                }
                                if (isVideo) updateVideoPreview() else rerender()
                            }
                            StickerPanel(current?.faceStickers?.get(face) ?: emoji, face,
                                mediaReady,
                                onSelect = ::applySticker,
                                onShuffle = {
                                    if (face == null && current != null && !current.faces.isNullOrEmpty()) {
                                        updatePhoto(current.copy(
                                            faceStickers = current.faces.orEmpty().associate { it.id to stickers.random() },
                                        ))
                                        rerender()
                                    } else applySticker(stickers.filter { it != (current?.faceStickers?.get(face) ?: emoji) }.random())
                                },
                                onClear = { selection = null },
                            )
                        }
                        if (hasProject) {
                            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                for (option in MaskStyle.entries) {
                                    val available = option != MaskStyle.Sticker || stickersAvailable
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
                                            selection = null
                                            style = option
                                            if (isVideo) updateVideoPreview() else rerender()
                                        }
                                    }, enabled = mediaReady && available, modifier = Modifier.weight(1f), shape = RoundedCornerShape(16.dp),
                                        color = if (active || !available) paper else Color.White,
                                        border = BorderStroke(if (active) 2.dp else 1.dp, if (active) coral else pink),
                                        contentColor = when {
                                            active -> apricotDark
                                            !available -> mutedInk
                                            else -> brown
                                        }) {
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
                            if (!stickersAvailable) {
                                Text(stringResource(R.string.editor_sticker_requires_face),
                                    color = mutedInk, fontSize = 12.sp)
                            }
                        }
                        if (isVideo) {
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
                        } else {
                            // Photos: the primary button saves the whole batch;
                            // the current photo has its own download icon on the
                            // preview canvas, so the separate batch button is gone.
                            val saveAll = photos.size > 1
                            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                                Button(onClick = { export(false, if (saveAll) photos else null) }, enabled = canExport, shape = pill,
                                    modifier = Modifier.weight(1f).heightIn(min = 50.dp)) {
                                    IconLabel(R.drawable.tap_download, if (saveAll) {
                                        stringResource(R.string.editor_save_batch, photos.size)
                                    } else stringResource(R.string.save))
                                }
                                Button(onClick = { export(true) }, enabled = canExport, colors = secondary, shape = pill,
                                    modifier = Modifier.heightIn(min = 50.dp)) {
                                    IconLabel(R.drawable.tap_share, stringResource(R.string.editor_share))
                                }
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
        if (confirmRemove) {
            EditorConfirmDialog(
                title = stringResource(R.string.editor_remove_media_title),
                message = stringResource(R.string.editor_remove_media_body),
                action = stringResource(R.string.editor_remove_media),
                icon = R.drawable.tap_close,
                destructive = true,
                onDismiss = { confirmRemove = false },
                onConfirm = { confirmRemove = false; removeCurrent() },
            )
        }
        pendingTargets?.let { next ->
            EditorConfirmDialog(
                title = stringResource(R.string.editor_subject_confirm_title),
                message = stringResource(R.string.editor_subject_confirm_body),
                action = stringResource(R.string.editor_subject_apply),
                icon = R.drawable.tap_refresh,
                onDismiss = { pendingTargets = null },
                onConfirm = { pendingTargets = null; applyTargets(next) },
            )
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

    private fun detectPhoto(bitmap: Bitmap, targets: Set<SubjectTarget>): Detection =
        FaceDetector(this, detectPerson = false).use {
            it.detect(bitmap, SubjectTarget.Face in targets, SubjectTarget.Person in targets, SubjectTarget.Pet in targets)
        }

    private suspend fun detectPhoto(uri: Uri, targets: Set<SubjectTarget>): Detection = withContext(Dispatchers.Default) {
        val source = decodePhoto(uri)
        try { detectPhoto(source, targets) } finally { source.recycle() }
    }

    private suspend fun renderPhoto(
        draft: PhotoDraft, style: MaskStyle, emoji: String, targets: Set<SubjectTarget>,
        strengths: EffectStrengths, preview: Boolean = false,
    ): Pair<Bitmap, Detection> {
        var output: Bitmap? = null
        try {
            return withContext(Dispatchers.Default) {
                val source = decodePhoto(draft.uri)
                try {
                    val analysis = draft.analysis ?: detectPhoto(source, targets)
                    val faces = analysis.faces.mapIndexed(::PhotoFace)
                    ensureActive()
                    val overrides = if (style == MaskStyle.Sticker) {
                        faces.mapNotNull { face -> draft.faceStickers[face.id]?.let { draft.edits.boxFor(face) to it } }.toMap()
                    } else emptyMap()
                    val rendered = renderEditorPhoto(source, draft.edits.masks(faces), style, emoji, overrides, draft.edits.inverted, analysis.person, strengths)
                    output = rendered
                    val longEdge = maxOf(rendered.width, rendered.height)
                    if (preview && longEdge > 1080) {
                        val scale = 1080f / longEdge
                        output = Bitmap.createScaledBitmap(rendered,
                            (rendered.width * scale).roundToInt().coerceAtLeast(1),
                            (rendered.height * scale).roundToInt().coerceAtLeast(1), true)
                        rendered.recycle()
                    }
                    checkNotNull(output) to analysis
                } finally { source.recycle() }
            }
        } catch (error: Exception) {
            output?.recycle()
            throw error
        }
    }

    private suspend fun savePhotos(drafts: List<PhotoDraft>, style: MaskStyle, emoji: String,
        targets: Set<SubjectTarget>, strengths: EffectStrengths, progress: (Int) -> Unit): PhotoExport {
        require(drafts.size in 1..batchLimit)
        val saved = mutableListOf<Uri>()
        val failures = mutableSetOf<Uri>()
        try {
            for ((index, draft) in drafts.withIndex()) {
                currentCoroutineContext().ensureActive()
                try {
                    val (bitmap) = renderPhoto(draft, style, emoji, targets, strengths)
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
