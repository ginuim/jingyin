package com.reaidea.lenshide.prototype

import android.graphics.Bitmap
import android.net.Uri
import android.util.Size
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
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
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

@Composable
internal fun TapIcon(icon: Int, description: String? = null, modifier: Modifier = Modifier.size(19.dp)) {
    Icon(painterResource(icon), description, modifier)
}

@Composable
internal fun IconLabel(icon: Int, label: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
        TapIcon(icon, modifier = Modifier.size(17.dp))
        Text(label)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun EditorSheet(onClose: () -> Unit, content: @Composable ColumnScope.() -> Unit) {
    ModalBottomSheet(onDismissRequest = onClose, containerColor = Color.White,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp), dragHandle = null) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp), content = content)
    }
}

@Composable
internal fun SheetHeading(title: String, subtitle: String? = null, icon: Int? = null, onClose: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        if (icon != null) {
            Surface(shape = RoundedCornerShape(13.dp), color = MaterialTheme.colorScheme.secondaryContainer,
                contentColor = MaterialTheme.colorScheme.onSecondaryContainer) {
                TapIcon(icon, modifier = Modifier.padding(10.dp).size(21.dp))
            }
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.ExtraBold)
            if (subtitle != null) Text(subtitle, style = MaterialTheme.typography.bodySmall)
        }
        IconButton(onClick = onClose) { TapIcon(R.drawable.tap_close, stringResource(R.string.editor_close)) }
    }
}

/** Inline privacy note under the header, mirroring the "!" popover in the design reference. */
@Composable
internal fun PrivacyPopover(onClose: () -> Unit) {
    Surface(shape = RoundedCornerShape(16.dp), color = ink.copy(alpha = 0.95f), contentColor = Color.White,
        shadowElevation = 6.dp) {
        Row(Modifier.padding(14.dp), verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(stringResource(R.string.editor_info_body), Modifier.weight(1f), fontSize = 12.sp, lineHeight = 18.sp)
            Surface(onClick = onClose, shape = CircleShape, color = Color.White.copy(alpha = 0.15f),
                contentColor = Color.White, modifier = Modifier.size(20.dp)) {
                Box(contentAlignment = Alignment.Center) { Text("✕", fontSize = 10.sp) }
            }
        }
    }
}

/** Initial empty state rendered inside the preview canvas (no separate home screen). */
@Composable
internal fun EmptyCanvas(enabled: Boolean, onPick: () -> Unit) {
    Box(Modifier.fillMaxSize()
        .background(Brush.verticalGradient(listOf(Color(0xFFFFFDFB), Color(0xFFFCEEE9))))
        .padding(14.dp)) {
        Column(
            Modifier.fillMaxSize()
                .background(Color.White.copy(alpha = 0.75f), RoundedCornerShape(16.dp))
                .drawBehind {
                    drawRoundRect(
                        color = apricot300,
                        cornerRadius = CornerRadius(16.dp.toPx()),
                        style = Stroke(width = 2.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(10f, 8f))),
                    )
                }
                .padding(horizontal = 16.dp, vertical = 18.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.SpaceBetween,
        ) {
            Surface(shape = pill, color = pink.copy(alpha = 0.8f), contentColor = apricotDark) {
                Text(stringResource(R.string.editor_steps), Modifier.padding(horizontal = 12.dp, vertical = 5.dp),
                    fontSize = 11.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }

            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
                EmptyIllustration()
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(5.dp)) {
                    Text(stringResource(R.string.editor_empty_title), fontSize = 15.sp, fontWeight = FontWeight.ExtraBold,
                        color = ink, textAlign = TextAlign.Center)
                    Text(stringResource(R.string.editor_empty_body), fontSize = 12.sp, lineHeight = 18.sp, color = brown,
                        textAlign = TextAlign.Center, modifier = Modifier.widthIn(max = 240.dp))
                }
            }

            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = onPick, enabled = enabled, shape = pill, modifier = Modifier.fillMaxWidth()) {
                    IconLabel(R.drawable.tap_add, stringResource(R.string.editor_pick_media))
                }
                Text(stringResource(R.string.editor_limit_hint), fontSize = 11.sp, fontWeight = FontWeight.SemiBold,
                    color = brown, textAlign = TextAlign.Center)
                Text(stringResource(R.string.editor_rule_detail), fontSize = 10.sp, lineHeight = 15.sp, color = mutedInk,
                    textAlign = TextAlign.Center)
            }
        }
    }
}

@Composable
private fun EmptyIllustration() {
    Box(Modifier.size(80.dp)) {
        Box(Modifier.matchParentSize()
            .background(pink, RoundedCornerShape(24.dp))
            .drawBehind {
                drawRoundRect(color = line, cornerRadius = CornerRadius(24.dp.toPx()), style = Stroke(1.dp.toPx()))
            })
        Canvas(Modifier.size(56.dp).align(Alignment.Center)) {
            val unit = size.width / 64f
            drawRoundRect(color = paper, topLeft = androidx.compose.ui.geometry.Offset(8 * unit, 8 * unit),
                size = androidx.compose.ui.geometry.Size(48 * unit, 48 * unit), cornerRadius = CornerRadius(12 * unit))
            drawRoundRect(color = coral, topLeft = androidx.compose.ui.geometry.Offset(8 * unit, 8 * unit),
                size = androidx.compose.ui.geometry.Size(48 * unit, 48 * unit), cornerRadius = CornerRadius(12 * unit),
                style = Stroke(2.5f * unit))
            val cells = listOf(
                listOf(Color(0xFF5A4944), Color(0xFFC89D7C), Color(0xFFF19A87)),
                listOf(Color(0xFFE89954), coral, Color(0xFFB84B37)),
                listOf(Color(0xFFFAD9D0), Color(0xFFDC644D), Color(0xFFF28F27)),
            )
            cells.forEachIndexed { row, colors ->
                colors.forEachIndexed { col, color ->
                    drawRoundRect(color = color,
                        topLeft = androidx.compose.ui.geometry.Offset((20 + col * 8) * unit, (16 + row * 8) * unit),
                        size = androidx.compose.ui.geometry.Size(8 * unit, 8 * unit),
                        cornerRadius = CornerRadius(1.5f * unit))
                }
            }
        }
        Surface(Modifier.align(Alignment.BottomEnd).offset(x = 6.dp, y = 6.dp).size(32.dp),
            shape = RoundedCornerShape(12.dp), color = Color.White, border = BorderStroke(1.dp, line)) {
            Box(contentAlignment = Alignment.Center) { Text("😊", fontSize = 16.sp) }
        }
        Surface(Modifier.align(Alignment.TopStart).offset(x = (-8).dp, y = (-8).dp),
            shape = pill, color = emerald, contentColor = Color.White) {
            Text(stringResource(R.string.editor_local_badge), Modifier.padding(horizontal = 8.dp, vertical = 2.dp),
                fontSize = 10.sp, fontWeight = FontWeight.Bold, maxLines = 1)
        }
    }
}

@Composable
internal fun SettingsPanel(language: String, canChangeLanguage: Boolean, onLanguage: (String) -> Unit, onClose: () -> Unit) {
    EditorSheet(onClose) {
        SheetHeading(stringResource(R.string.editor_settings), icon = R.drawable.tap_settings, onClose = onClose)
        Text(stringResource(R.string.editor_language), fontWeight = FontWeight.SemiBold)
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            for ((tag, label) in listOf("zh-CN" to "简中", "zh-TW" to "繁體", "en" to "EN", "ja" to "日本語")) {
                FilterChip(language == tag, onClick = { onLanguage(tag) }, label = { Text(label) },
                    enabled = canChangeLanguage, modifier = Modifier.weight(1f))
            }
        }
        if (!canChangeLanguage) Text(stringResource(R.string.editor_language_after_close), style = MaterialTheme.typography.bodySmall)
        Surface(shape = RoundedCornerShape(16.dp), color = MaterialTheme.colorScheme.surface) {
            Column(Modifier.fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                IconLabel(R.drawable.tap_shield, stringResource(R.string.editor_privacy_title))
                Text(stringResource(R.string.editor_privacy_body), style = MaterialTheme.typography.bodySmall)
                Text(stringResource(R.string.editor_privacy_limits), style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}

@Composable
internal fun LifetimePanel(onClose: () -> Unit) {
    EditorSheet(onClose) {
        SheetHeading(stringResource(R.string.editor_lifetime), stringResource(R.string.editor_lifetime_subtitle),
            R.drawable.tap_shield, onClose)
        val rows = listOf(
            Triple(R.string.editor_feature, R.string.editor_free_column, R.string.editor_lifetime_column),
            Triple(R.string.editor_editing, R.string.editor_full_access, R.string.editor_full_access),
            Triple(R.string.editor_video_export, R.string.editor_free_video, R.string.editor_full_video),
            Triple(R.string.editor_photo_export, R.string.editor_free_photo, R.string.editor_full_photo),
        )
        Surface(shape = RoundedCornerShape(16.dp), color = Color.White,
            border = BorderStroke(1.dp, MaterialTheme.colorScheme.secondaryContainer)) {
            Column {
                rows.forEachIndexed { index, (feature, free, lifetime) ->
                    if (index != 0) HorizontalDivider(color = MaterialTheme.colorScheme.secondaryContainer)
                    Surface(color = if (index == 0) MaterialTheme.colorScheme.surface else Color.White) {
                        Row(Modifier.fillMaxWidth().padding(12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text(stringResource(feature), Modifier.weight(0.95f), fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                            Text(stringResource(free), Modifier.weight(1f), fontSize = 12.sp)
                            Text(stringResource(lifetime), Modifier.weight(1.1f), fontSize = 12.sp,
                                fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSecondaryContainer)
                        }
                    }
                }
            }
        }
        Text(stringResource(R.string.editor_android_billing), style = MaterialTheme.typography.bodySmall)
        Button(onClick = onClose, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.editor_done)) }
    }
}

@Composable
internal fun StickerPanel(selection: String, selectedFace: Int?, enabled: Boolean,
    onSelect: (String) -> Unit, onShuffle: () -> Unit, onClear: () -> Unit) {
    Surface(shape = RoundedCornerShape(16.dp), color = Color.White, border = BorderStroke(1.dp, line)) {
        Column(Modifier.fillMaxWidth().padding(10.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(stringResource(R.string.editor_sticker_count, stickers.size), fontSize = 12.sp,
                    fontWeight = FontWeight.ExtraBold, color = ink, maxLines = 1)
                Surface(shape = pill, color = pink, contentColor = apricotDark) {
                    Text(if (selectedFace == null) stringResource(R.string.editor_all_faces)
                         else stringResource(R.string.editor_selected_face, selectedFace + 1),
                        Modifier.padding(horizontal = 8.dp, vertical = 2.dp), fontSize = 11.sp,
                        fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                Spacer(Modifier.weight(1f))
                TextButton(onClick = onShuffle, enabled = enabled) {
                    Text(stringResource(R.string.editor_shuffle), fontSize = 12.sp, fontWeight = FontWeight.Bold)
                }
            }
            Row(Modifier.horizontalScroll(rememberScrollState()).padding(vertical = 2.dp),
                horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                for (sticker in stickers) {
                    val active = sticker == selection
                    Surface(onClick = { onSelect(sticker) }, enabled = enabled, shape = RoundedCornerShape(12.dp),
                        color = if (active) pink else paper,
                        border = if (active) BorderStroke(1.5.dp, coral) else null) {
                        Box(Modifier.size(38.dp), contentAlignment = Alignment.Center) {
                            Text(sticker, fontSize = 20.sp)
                        }
                    }
                }
            }
            if (selectedFace != null) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Spacer(Modifier.weight(1f))
                    IconButton(onClick = onClear, enabled = enabled) {
                        TapIcon(R.drawable.tap_close, stringResource(R.string.editor_done))
                    }
                }
            }
        }
    }
}

internal data class SavedExport(val items: List<Uri>, val video: Boolean, val failures: Int = 0)

@Composable
internal fun SavePanel(progress: Int, result: SavedExport?, error: Boolean, onClose: () -> Unit,
    onRetry: () -> Unit, onShare: (Uri, Boolean) -> Unit, onCopy: (Uri, Boolean) -> Unit, enabled: Boolean) {
    EditorSheet(onClose) {
        when {
            result == null && !error -> {
                Column(Modifier.fillMaxWidth().padding(vertical = 4.dp), horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Surface(shape = CircleShape, color = pink, contentColor = coral, modifier = Modifier.size(44.dp)) {
                        Box(contentAlignment = Alignment.Center) {
                            TapIcon(R.drawable.tap_shield, modifier = Modifier.size(20.dp))
                        }
                    }
                    Text(stringResource(R.string.editor_saving), fontSize = 14.sp, fontWeight = FontWeight.ExtraBold,
                        color = ink, textAlign = TextAlign.Center)
                    val bar = Modifier.fillMaxWidth().height(10.dp)
                    if (progress > 0) LinearProgressIndicator(progress = { progress / 100f }, modifier = bar,
                        color = coral, trackColor = pink, strokeCap = StrokeCap.Round)
                    else LinearProgressIndicator(modifier = bar, color = coral, trackColor = pink, strokeCap = StrokeCap.Round)
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text(stringResource(R.string.editor_on_device), fontSize = 11.sp, color = mutedInk)
                        Text("$progress%", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = coralDeep)
                    }
                    OutlinedButton(onClick = onClose, shape = pill, modifier = Modifier.fillMaxWidth(),
                        colors = ButtonDefaults.outlinedButtonColors(containerColor = paper, contentColor = brown),
                        border = BorderStroke(1.dp, line)) {
                        Text(stringResource(R.string.editor_cancel_cleanup), fontSize = 12.sp, fontWeight = FontWeight.Bold)
                    }
                }
            }
            result == null -> {
                SheetHeading(stringResource(R.string.failed), onClose = onClose)
                Button(onClick = onRetry, shape = pill, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.editor_retry)) }
            }
            else -> {
                val success = result.items.isNotEmpty()
                val heading = if (result.failures > 0 || result.items.size > 1)
                    stringResource(R.string.editor_batch_result, result.items.size, result.failures)
                    else stringResource(R.string.saved)
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Surface(shape = CircleShape, color = emeraldSoft, contentColor = emeraldDeep, modifier = Modifier.size(30.dp)) {
                        Box(contentAlignment = Alignment.Center) {
                            TapIcon(R.drawable.tap_check, modifier = Modifier.size(16.dp))
                        }
                    }
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(heading, fontSize = 16.sp, fontWeight = FontWeight.ExtraBold, color = ink)
                        if (success) Text(stringResource(R.string.editor_clean_metadata), fontSize = 11.sp, color = mutedInk)
                    }
                    Surface(onClick = onClose, shape = CircleShape, color = paper, contentColor = brown,
                        modifier = Modifier.size(28.dp)) {
                        Box(contentAlignment = Alignment.Center) { TapIcon(R.drawable.tap_close, stringResource(R.string.editor_close), Modifier.size(12.dp)) }
                    }
                }
                var index by remember(result) { mutableIntStateOf(0) }
                result.items.getOrNull(index)?.let { uri ->
                    SavedThumbnail(uri)
                    if (result.items.size > 1) {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically) {
                            IconButton(onClick = { index-- }, enabled = index > 0) {
                                TapIcon(R.drawable.tap_left, stringResource(R.string.editor_previous))
                            }
                            Text(stringResource(R.string.editor_photo_count, index + 1, result.items.size), fontSize = 12.sp, color = brown)
                            IconButton(onClick = { index++ }, enabled = index < result.items.lastIndex) {
                                TapIcon(R.drawable.tap_right, stringResource(R.string.editor_next))
                            }
                        }
                    }
                    if (success) {
                        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            MetadataBadge(stringResource(R.string.editor_badge_gps))
                            MetadataBadge(stringResource(R.string.editor_badge_device))
                        }
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(onClick = { onCopy(uri, result.video) }, enabled = enabled, shape = pill,
                            modifier = Modifier.weight(1f), colors = ButtonDefaults.buttonColors(containerColor = pink, contentColor = brown),
                            contentPadding = PaddingValues(horizontal = 8.dp, vertical = 10.dp)) {
                            IconLabel(R.drawable.tap_download, stringResource(R.string.editor_save_copy))
                        }
                        Button(onClick = { onShare(uri, result.video) }, enabled = enabled, shape = pill,
                            modifier = Modifier.weight(1f), contentPadding = PaddingValues(horizontal = 8.dp, vertical = 10.dp)) {
                            IconLabel(R.drawable.tap_share, stringResource(R.string.editor_share))
                        }
                    }
                }
                if (result.failures > 0) {
                    Surface(shape = RoundedCornerShape(12.dp), color = roseSoft, border = BorderStroke(1.dp, roseLine)) {
                        Text(stringResource(R.string.editor_batch_failed_notice, result.failures),
                            Modifier.padding(10.dp), fontSize = 11.sp, lineHeight = 16.sp, color = roseDeep)
                    }
                    OutlinedButton(onClick = onRetry, enabled = enabled, shape = pill, modifier = Modifier.fillMaxWidth()) {
                        Text(stringResource(R.string.editor_retry_failed, result.failures))
                    }
                }
                TextButton(onClick = onClose, enabled = enabled, modifier = Modifier.fillMaxWidth()) {
                    Text(stringResource(R.string.editor_done_clean), fontSize = 12.sp, color = mutedInk)
                }
            }
        }
    }
}

@Composable
private fun MetadataBadge(label: String) {
    Surface(shape = pill, color = emeraldSoft, contentColor = emeraldDeep) {
        Text(label, Modifier.padding(horizontal = 10.dp, vertical = 4.dp), fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun SavedThumbnail(uri: Uri) {
    val resolver = LocalContext.current.contentResolver
    // remember(uri) resets to null on key change; LaunchedEffect then loads off the main thread.
    var bitmap by remember(uri) { mutableStateOf<Bitmap?>(null) }
    LaunchedEffect(uri) {
        bitmap = withContext(Dispatchers.IO) {
            runCatching { resolver.loadThumbnail(uri, Size(720, 720), null) }.getOrNull()
        }
    }
    Surface(shape = RoundedCornerShape(16.dp), color = paper, border = BorderStroke(1.dp, line),
        modifier = Modifier.fillMaxWidth()) {
        Box(Modifier.fillMaxWidth().height(208.dp), contentAlignment = Alignment.Center) {
            val loaded = bitmap
            if (loaded != null) {
                Image(loaded.asImageBitmap(), stringResource(R.string.result),
                    Modifier.fillMaxSize(), contentScale = ContentScale.Fit)
                Surface(Modifier.align(Alignment.BottomEnd).padding(8.dp), shape = pill,
                    color = Color.Black.copy(alpha = 0.65f), contentColor = Color.White) {
                    Text(stringResource(R.string.editor_export_badge), Modifier.padding(horizontal = 10.dp, vertical = 3.dp),
                        fontSize = 10.sp, fontWeight = FontWeight.Bold)
                }
            } else {
                CircularProgressIndicator(Modifier.size(24.dp), color = coral, strokeWidth = 2.dp)
            }
        }
    }
}
