package com.reaidea.lenshide.prototype

import android.content.Context
import android.opengl.GLES20
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
    private var totalMs = 0.0
    private var maxMs = 0.0
    private var faces = 0L
    @Synchronized fun record(detection: Detection, elapsed: Double) {
        frames++; inferenceMs += detection.millis; totalMs += elapsed
        maxMs = maxOf(maxMs, elapsed); faces += detection.faces.size
    }
    @Synchronized fun snapshot(): String =
        "frames=$frames, faces=$faces, inferenceMeanMs=%.2f, effectMeanMs=%.2f, effectMaxMs=%.2f".format(
            inferenceMs / maxOf(1, frames), totalMs / maxOf(1, frames), maxMs)
    @Synchronized fun count(): Long = frames
}

@UnstableApi
class FacePixelEffect(private val metrics: FrameMetrics) : GlEffect {
    override fun toGlShaderProgram(context: Context, useHdr: Boolean): GlShaderProgram {
        check(!useHdr) { "This prototype supports SDR only" }
        return FacePixelShader(context, metrics)
    }
}

@UnstableApi
private class FacePixelShader(context: Context, private val metrics: FrameMetrics) : BaseGlShaderProgram(false, 1) {
    private val detector = FaceDetector(context)
    private val analysis = GlProgram(VERTEX, ANALYSIS)
    private val render = GlProgram(VERTEX, PIXEL)
    private val pixels = ByteBuffer.allocateDirect(320 * 320 * 4).order(ByteOrder.nativeOrder())
    private val bytes = ByteArray(320 * 320 * 4)
    private val rectangles = FloatArray(64 * 4)
    private val texture = GlUtil.createTexture(320, 320, false)
    private val fbo = GlUtil.createFboForTexture(texture)
    private var width = 0
    private var height = 0

    init {
        analysis.setBufferAttribute("aPosition", GlUtil.getNormalizedCoordinateBounds(), 4)
        render.setBufferAttribute("aPosition", GlUtil.getNormalizedCoordinateBounds(), 4)
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
            GlUtil.focusFramebufferUsingCurrentContext(fbo, 320, 320)
            analysis.use()
            analysis.setSamplerTexIdUniform("uTex", inputTexId, 0)
            val maxDimension = maxOf(width, height).toFloat()
            analysis.setFloatsUniform("uFit", floatArrayOf(width / maxDimension, height / maxDimension))
            analysis.bindAttributesAndUniforms()
            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
            pixels.clear()
            GLES20.glReadPixels(0, 0, 320, 320, GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, pixels)
            GlUtil.checkGlError()
            pixels.rewind(); pixels.get(bytes)
            val detection = detector.detectGl(bytes, width, height)
            check(detection.faces.size <= 64) { "Too many faces for the prototype; export stopped" }
            GlUtil.focusFramebufferUsingCurrentContext(oldFbo[0], width, height)
            render.use()
            render.setSamplerTexIdUniform("uTex", inputTexId, 0)
            render.setIntUniform("uCount", detection.faces.size)
            render.bindAttributesAndUniforms()
            rectangles.fill(0f)
            detection.faces.forEachIndexed { index, face ->
                rectangles[index * 4] = face.x; rectangles[index * 4 + 1] = face.y
                rectangles[index * 4 + 2] = face.width; rectangles[index * 4 + 3] = face.height
            }
            GLES20.glUniform4fv(render.getUniformLocation("uFaces[0]"), 64, rectangles, 0)
            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
            GlUtil.checkGlError()
            metrics.record(detection, (SystemClock.elapsedRealtimeNanos() - start) / 1e6)
        } catch (error: Exception) {
            throw VideoFrameProcessingException(error, presentationTimeUs)
        } finally {
            GlUtil.focusFramebufferUsingCurrentContext(oldFbo[0], width, height)
        }
    }

    override fun release() {
        try {
            analysis.delete(); render.delete()
            GlUtil.deleteFbo(fbo); GlUtil.deleteTexture(texture)
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
        const val PIXEL = """
            precision highp float;
            uniform sampler2D uTex;
            uniform vec4 uFaces[64];
            uniform int uCount;
            varying vec2 vTex;
            void main() {
                vec2 p = vec2(vTex.x, 1.0 - vTex.y);
                vec2 uv = vTex;
                for (int i = 0; i < 64; i++) {
                    if (i >= uCount) break;
                    vec4 r = uFaces[i];
                    if (p.x >= r.x && p.y >= r.y && p.x <= r.x+r.z && p.y <= r.y+r.w) {
                        vec2 local = clamp((p-r.xy)/r.zw, 0.0, 0.9999);
                        vec2 sampleAt = r.xy + (floor(local*4.0)+0.5)/4.0*r.zw;
                        uv = vec2(sampleAt.x, 1.0-sampleAt.y);
                        break;
                    }
                }
                gl_FragColor = texture2D(uTex, uv);
            }
        """
    }
}
