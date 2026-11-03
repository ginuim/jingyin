package com.reaidea.lenshide.prototype

import android.graphics.Bitmap
import android.net.Uri
import android.util.Size
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
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
internal fun StickerPanel(selection: String, selectedFace: Int?, revealed: Boolean, enabled: Boolean,
    onSelect: (String) -> Unit, onShuffle: () -> Unit, onReveal: () -> Unit, onClear: () -> Unit) {
    Surface(shape = RoundedCornerShape(16.dp), color = Color.White,
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.secondaryContainer)) {
        Column(Modifier.fillMaxWidth().padding(10.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(stringResource(R.string.editor_sticker_count, stickers.size), fontWeight = FontWeight.Bold)
                    Text(if (selectedFace == null) stringResource(R.string.editor_all_faces)
                         else stringResource(R.string.editor_selected_face, selectedFace + 1), fontSize = 12.sp)
                }
                IconButton(onClick = onShuffle, enabled = enabled) {
                    TapIcon(R.drawable.tap_shuffle, stringResource(R.string.editor_shuffle))
                }
            }
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                for (sticker in stickers) {
                    FilterChip(selected = sticker == selection, onClick = { onSelect(sticker) }, enabled = enabled,
                        label = { Text(sticker, fontSize = 23.sp) })
                }
            }
            if (selectedFace != null) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    TextButton(onClick = onReveal, enabled = enabled) {
                        Text(stringResource(if (revealed) R.string.editor_cover_face else R.string.editor_reveal_face))
                    }
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
                SheetHeading(stringResource(R.string.editor_saving), stringResource(R.string.editor_on_device),
                    R.drawable.tap_shield, onClose)
                if (progress > 0) LinearProgressIndicator(progress = { progress / 100f }, modifier = Modifier.fillMaxWidth())
                else LinearProgressIndicator(Modifier.fillMaxWidth())
                Text("$progress%", Modifier.align(Alignment.End), fontWeight = FontWeight.SemiBold)
                OutlinedButton(onClick = onClose, modifier = Modifier.fillMaxWidth()) {
                    Text(stringResource(R.string.editor_cancel_cleanup))
                }
            }
            result == null -> {
                SheetHeading(stringResource(R.string.failed), onClose = onClose)
                Button(onClick = onRetry, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.editor_retry)) }
            }
            else -> {
                val heading = if (result.failures > 0 || result.items.size > 1) stringResource(R.string.editor_batch_result, result.items.size, result.failures)
                    else stringResource(R.string.saved)
                SheetHeading(heading, if (result.items.isNotEmpty()) stringResource(R.string.editor_clean_metadata) else null,
                    if (result.items.isNotEmpty()) R.drawable.tap_check else null, onClose)
                var index by remember(result) { mutableIntStateOf(0) }
                result.items.getOrNull(index)?.let { uri ->
                    SavedThumbnail(uri)
                    if (result.items.size > 1) {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically) {
                            IconButton(onClick = { index-- }, enabled = index > 0) {
                                TapIcon(R.drawable.tap_left, stringResource(R.string.editor_previous))
                            }
                            Text(stringResource(R.string.editor_photo_count, index + 1, result.items.size))
                            IconButton(onClick = { index++ }, enabled = index < result.items.lastIndex) {
                                TapIcon(R.drawable.tap_right, stringResource(R.string.editor_next))
                            }
                        }
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedButton(onClick = { onCopy(uri, result.video) }, enabled = enabled,
                            modifier = Modifier.weight(1f), contentPadding = PaddingValues(horizontal = 8.dp, vertical = 8.dp)) {
                            IconLabel(R.drawable.tap_download, stringResource(R.string.editor_save_copy))
                        }
                        Button(onClick = { onShare(uri, result.video) }, enabled = enabled, modifier = Modifier.weight(1f)) {
                            IconLabel(R.drawable.tap_share, stringResource(R.string.editor_share))
                        }
                    }
                }
                if (result.failures > 0) {
                    OutlinedButton(onClick = onRetry, enabled = enabled, modifier = Modifier.fillMaxWidth()) {
                        Text(stringResource(R.string.editor_retry_failed, result.failures))
                    }
                }
                TextButton(onClick = onClose, enabled = enabled, modifier = Modifier.fillMaxWidth()) {
                    Text(stringResource(R.string.editor_done))
                }
            }
        }
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
    bitmap?.let {
        Surface(shape = RoundedCornerShape(16.dp), color = MaterialTheme.colorScheme.surface,
            border = BorderStroke(1.dp, MaterialTheme.colorScheme.secondaryContainer)) {
            Image(it.asImageBitmap(), stringResource(R.string.result),
                Modifier.fillMaxWidth().height(192.dp), contentScale = ContentScale.Fit)
        }
    }
}
