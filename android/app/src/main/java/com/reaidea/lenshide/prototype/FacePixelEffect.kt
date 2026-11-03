package com.reaidea.lenshide.prototype

import android.content.Context
import android.opengl.GLES20
import android.opengl.GLUtils
import android.os.SystemClock
import androidx.media3.common.VideoFrameProcessingException
import androidx.media3.common.util.GlProgram
import androidx.media3.common.util.GlUtil
import androidx.media3.common.util.Size
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.BaseGlShaderProgram
import androidx.media3.effect.GlEffect
import androidx.media3.effect.GlShaderProgram
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Bounded aggregates only: never retains frame images or per-frame face history. */
class FrameMetrics {
    private var frames = 0L
    private var inferenceMs = 0.0
    private var segmentMs = 0.0
    private var totalMs = 0.0
    private var maxMs = 0.0
    private var faces = 0L
    private var personFrames = 0L
    @Synchronized fun record(detection: Detection, elapsed: Double) {
        frames++; inferenceMs += detection.millis; segmentMs += detection.segmentMillis; totalMs += elapsed
        maxMs = maxOf(maxMs, elapsed); faces += detection.faces.size
        if (detection.person != null) personFrames++
    }
    @Synchronized fun snapshot(): String =
        "frames=$frames, faces=$faces, personFrames=$personFrames, inferenceMeanMs=%.2f, segmentMeanMs=%.2f, effectMeanMs=%.2f, effectMaxMs=%.2f".format(
            inferenceMs / maxOf(1, frames), segmentMs / maxOf(1, frames), totalMs / maxOf(1, frames), maxMs)
    @Synchronized fun count(): Long = frames
}

@UnstableApi
class FacePixelEffect internal constructor(
    private val metrics: FrameMetrics,
    initialOptions: VideoMaskOptions?,
) : GlEffect {
    constructor(metrics: FrameMetrics) : this(metrics, null)

    @Volatile private var options = initialOptions

    internal fun updateOptions(next: VideoMaskOptions?): Boolean {
        if (options == next) return false
        options = next
        return true
    }

    override fun toGlShaderProgram(context: Context, useHdr: Boolean): GlShaderProgram {
        check(!useHdr) { "This prototype supports SDR only" }
        return SubjectPixelShader(context, metrics, options == null) { options }
    }
}

/**
 * Whole-frame mosaic blended by a person silhouette plus face ellipses, both feathered.
 * Shares its geometry with [SubjectMask]; keep the GLSL formulas in sync with that file.
 */
@UnstableApi
private class SubjectPixelShader(
    context: Context,
    private val metrics: FrameMetrics,
    detectPerson: Boolean,
    private val currentOptions: () -> VideoMaskOptions?,
) : BaseGlShaderProgram(false, 1) {
    private val detector = FaceDetector(context, detectPerson = detectPerson)
    private val stickerTexture = GlUtil.createTexture(256, 256, false)
    private val analysis = GlProgram(VERTEX, ANALYSIS)
    private val render = GlProgram(VERTEX, RENDER)
    private val pixels = ByteBuffer.allocateDirect(320 * 320 * 4).order(ByteOrder.nativeOrder())
    private val bytes = ByteArray(320 * 320 * 4)
    private val texture = GlUtil.createTexture(320, 320, false)
    private val fbo = GlUtil.createFboForTexture(texture)
    private val maskTexture = IntArray(1)
    private val maskBuffer = ByteBuffer.allocateDirect(320 * 320).order(ByteOrder.nativeOrder())
    private var maskAllocated = false
    private val ellipses = FloatArray(64 * 4)
    private var width = 0
    private var height = 0

    private var uploadedSticker: String? = null

    init {
        analysis.setBufferAttribute("aPosition", GlUtil.getNormalizedCoordinateBounds(), 4)
        render.setBufferAttribute("aPosition", GlUtil.getNormalizedCoordinateBounds(), 4)
        GLES20.glGenTextures(1, maskTexture, 0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, maskTexture[0])
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
    }

    override fun configure(inputWidth: Int, inputHeight: Int): Size {
        width = inputWidth; height = inputHeight
        return Size(width, height)
    }

    override fun drawFrame(inputTexId: Int, presentationTimeUs: Long) {
        val start = SystemClock.elapsedRealtimeNanos()
        val oldFbo = IntArray(1)
        GLES20.glGetIntegerv(GLES20.GL_FRAMEBUFFER_BINDING, oldFbo, 0)
        try {
            val options = currentOptions()
            val targets = options?.targets
            val fit = SubjectMask.letterboxFit(width, height)
            val detection = run {
                GlUtil.focusFramebufferUsingCurrentContext(fbo, 320, 320)
                analysis.use()
                analysis.setSamplerTexIdUniform("uTex", inputTexId, 0)
                analysis.setFloatsUniform("uFit", fit)
                analysis.bindAttributesAndUniforms()
                GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
                pixels.clear()
                GLES20.glReadPixels(0, 0, 320, 320, GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, pixels)
                GlUtil.checkGlError()
                pixels.rewind(); pixels.get(bytes)
                if (targets == null) detector.detectGl(bytes, width, height)
                else detector.detectGl(bytes, width, height,
                    SubjectTarget.Face in targets, SubjectTarget.Person in targets, SubjectTarget.Pet in targets)
            }
            if (options?.style == MaskStyle.Sticker && !options.inverted && options.sticker != uploadedSticker) {
                val bitmap = stickerBitmap(options.sticker)
                try {
                    GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, stickerTexture)
                    GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, bitmap, 0)
                    uploadedSticker = options.sticker
                } finally { bitmap.recycle() }
            }
            val masks = detection.faces + options?.manual.orEmpty()
            check(masks.size <= 64) { "Too many masks; processing stopped" }
            if (detection.person != null || !maskAllocated) uploadPersonMask(detection.person)
            GlUtil.focusFramebufferUsingCurrentContext(oldFbo[0], width, height)

            render.use()
            render.setSamplerTexIdUniform("uTex", inputTexId, 0)
            render.setSamplerTexIdUniform("uMask", maskTexture[0], 1)
            render.setFloatsUniform("uFit", fit)
            render.setFloatsUniform("uSize", floatArrayOf(width.toFloat(), height.toFloat()))
            render.setFloatsUniform("uCell", floatArrayOf(SubjectMask.cellSize(width, height).toFloat()))
            render.setSamplerTexIdUniform("uSticker", stickerTexture, 2)
            render.setIntUniform("uStyle", options?.style?.let { it.ordinal + 1 } ?: 0)
            render.setIntUniform("uCount", masks.size)
            render.setIntUniform("uHasSilhouette", if (detection.person != null) 1 else 0)
            render.setIntUniform("uInverted", if (options?.inverted == true) 1 else 0)
            render.bindAttributesAndUniforms()
            ellipses.fill(0f)
            masks.forEachIndexed { index, face ->
                ellipses[index * 4] = face.cx; ellipses[index * 4 + 1] = face.cy
                ellipses[index * 4 + 2] = face.rx; ellipses[index * 4 + 3] = face.ry
            }
            GLES20.glUniform4fv(render.getUniformLocation("uFaces[0]"), 64, ellipses, 0)
            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
            GlUtil.checkGlError()
            metrics.record(detection, (SystemClock.elapsedRealtimeNanos() - start) / 1e6)
        } catch (error: Exception) {
            throw VideoFrameProcessingException(error, presentationTimeUs)
        } finally {
            GlUtil.focusFramebufferUsingCurrentContext(oldFbo[0], width, height)
        }
    }

    /** Uploads a 320² luminance mask, top row first. An absent silhouette uploads zeros. */
    private fun uploadPersonMask(person: PersonMask?) {
        maskBuffer.clear()
        if (person != null) maskBuffer.put(person.alpha) else repeat(320 * 320) { maskBuffer.put(0) }
        maskBuffer.rewind()
        GLES20.glPixelStorei(GLES20.GL_UNPACK_ALIGNMENT, 1)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE1)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, maskTexture[0])
        if (maskAllocated) {
            GLES20.glTexSubImage2D(GLES20.GL_TEXTURE_2D, 0, 0, 0, 320, 320,
                GLES20.GL_LUMINANCE, GLES20.GL_UNSIGNED_BYTE, maskBuffer)
        } else {
            GLES20.glTexImage2D(GLES20.GL_TEXTURE_2D, 0, GLES20.GL_LUMINANCE, 320, 320, 0,
                GLES20.GL_LUMINANCE, GLES20.GL_UNSIGNED_BYTE, maskBuffer)
            maskAllocated = true
        }
        GlUtil.checkGlError()
    }

    override fun release() {
        try {
            analysis.delete(); render.delete()
            GLES20.glDeleteTextures(1, maskTexture, 0)
            GlUtil.deleteFbo(fbo); GlUtil.deleteTexture(texture)
            GlUtil.deleteTexture(stickerTexture)
            detector.close()
        } finally { super.release() }
    }

    companion object {
        const val VERTEX = """
            attribute vec4 aPosition;
            varying vec2 vTex;
            void main() { gl_Position = aPosition; vTex = aPosition.xy * 0.5 + 0.5; }
        """
        const val ANALYSIS = """
            precision highp float;
            uniform sampler2D uTex;
            uniform vec2 uFit;
            varying vec2 vTex;
            void main() {
                vec2 uv = (vTex - 0.5) / uFit + 0.5;
                gl_FragColor = (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0)
                    ? vec4(0.0, 0.0, 0.0, 1.0) : texture2D(uTex, uv);
            }
        """
        /**
         * p is top-left display coordinates. The mask is sampled in analysis space, which is the
         * same letterbox mapping as detection. Mosaic cell centres use integer pixel grids.
         */
        const val RENDER = """
            precision highp float;
            uniform sampler2D uTex;
            uniform sampler2D uMask;
            uniform sampler2D uSticker;
            uniform int uStyle;
            uniform vec2 uFit;
            uniform vec2 uSize;
            uniform float uCell;
            uniform vec4 uFaces[64];
            uniform int uCount;
            uniform int uInverted;
            uniform int uHasSilhouette;
            varying vec2 vTex;
            void main() {
                vec2 p = vec2(vTex.x, 1.0 - vTex.y);
                vec2 maskUv = (p - 0.5) * uFit + 0.5;
                float person = uHasSilhouette == 1 ? smoothstep(0.35, 0.65, texture2D(uMask, maskUv).r) : 0.0;
                float face = 0.0;
                for (int i = 0; i < 64; i++) {
                    if (i >= uCount) break;
                    vec4 e = uFaces[i];
                    float r = length((p - e.xy) / e.zw);
                    face = max(face, 1.0 - smoothstep(0.86, 1.0, r));
                }
                float coverage = max(person, face);
                vec2 cellCentre = (floor(p * uSize / uCell) + 0.5) * uCell / uSize;
                cellCentre = clamp(cellCentre, vec2(0.0), vec2(1.0));
                vec4 source = texture2D(uTex, vTex);
                vec4 mosaic = texture2D(uTex, vec2(cellCentre.x, 1.0 - cellCentre.y));
                float effectAlpha = uInverted == 1 ? 1.0 - coverage : coverage;
                if (uStyle <= 1 || (uStyle == 3 && uInverted == 1)) {
                    gl_FragColor = mix(source, mosaic, effectAlpha);
                    return;
                }
                if (uStyle == 2) {
                    if (effectAlpha <= 0.0) {
                        gl_FragColor = source;
                        return;
                    }
                    vec4 blurred = vec4(0.0);
                    float stepPx = min(uSize.x, uSize.y) / 120.0;
                    for (int y = -3; y <= 3; y++) {
                        for (int x = -3; x <= 3; x++) {
                            blurred += texture2D(uTex, vTex + vec2(float(x), float(y)) * stepPx / uSize);
                        }
                    }
                    gl_FragColor = mix(source, blurred / 49.0, effectAlpha);
                    return;
                }
                vec4 result = mix(source, mosaic, person);
                for (int i = 0; i < 64; i++) {
                    if (i >= uCount) break;
                    vec4 e = uFaces[i];
                    float radius = min(e.z * uSize.x, e.w * uSize.y);
                    vec2 stickerUv = (p - e.xy) * uSize / (2.0 * radius) + 0.5;
                    if (all(greaterThanEqual(stickerUv, vec2(0.0))) && all(lessThanEqual(stickerUv, vec2(1.0)))) {
                        vec4 sticker = texture2D(uSticker, stickerUv);
                        result = vec4(sticker.rgb + result.rgb * (1.0 - sticker.a), 1.0);
                    }
                }
                gl_FragColor = result;
            }
        """
    }
}
