package com.reaidea.lenshide.prototype

import android.app.ActivityManager
import android.content.Context
import android.media.MediaCodecList
import android.media.MediaFormat
import android.os.Build
import android.os.Debug

object DeviceCapabilities {
    fun describe(context: Context): String {
        val manager = context.getSystemService(ActivityManager::class.java)
        val memory = ActivityManager.MemoryInfo().also(manager::getMemoryInfo)
        val encoders = MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.filter {
            it.isEncoder && it.supportedTypes.any { type -> type.equals(MediaFormat.MIMETYPE_VIDEO_AVC, true) }
        }.map { codec ->
            val caps = codec.getCapabilitiesForType(MediaFormat.MIMETYPE_VIDEO_AVC).videoCapabilities
            val hardware = if (Build.VERSION.SDK_INT >= 29) codec.isHardwareAccelerated.toString() else "unknown(API<29)"
            "${codec.name}: hw=$hardware, 720p30=${caps.areSizeAndRateSupported(1280, 720, 30.0)}"
        }
        return buildString {
            appendLine("${Build.MANUFACTURER} ${Build.MODEL} / Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})")
            appendLine("ABI=${Build.SUPPORTED_ABIS.joinToString()}, CPUs=${Runtime.getRuntime().availableProcessors()}")
            appendLine("RAM=%.2f GiB, lowRam=${manager.isLowRamDevice}, heapClass=${manager.memoryClass} MiB".format(memory.totalMem / 1073741824.0))
            appendLine("processPss=${Debug.getPss()} KiB (snapshot, not peak)")
            appendLine("H.264 encoders:")
            encoders.forEach(::appendLine)
            append("API level is a compatibility filter, not a performance score.")
        }
    }
}
