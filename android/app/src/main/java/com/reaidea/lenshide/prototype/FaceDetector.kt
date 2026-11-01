package com.reaidea.lenshide.prototype

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import android.os.SystemClock
import org.opencv.android.OpenCVLoader
import org.opencv.android.Utils
import org.opencv.core.Core
import org.opencv.core.CvType
import org.opencv.core.Mat
import org.opencv.core.Size
import org.opencv.imgproc.Imgproc
import org.opencv.objdetect.FaceDetectorYN
import java.io.File
import kotlin.math.max
import kotlin.math.min

/** Display-oriented, top-left normalized bounds, shared by photo and video rendering. */
data class FaceBox(val x: Float, val y: Float, val width: Float, val height: Float)
data class Detection(val faces: List<FaceBox>, val millis: Double)

/** One instance per worker/GL thread. No identity embeddings or persistence of detections. */
class FaceDetector(context: Context, val inputSize: Int = 320) : AutoCloseable {
    private val initialized = OpenCVLoader.initLocal().also { check(it) { "OpenCV initialization failed" } }
    private val model: FaceDetectorYN
    private val rgba = Mat(inputSize, inputSize, CvType.CV_8UC4)
    private val bgr = Mat()
    private val result = Mat()
    private val square = Bitmap.createBitmap(inputSize, inputSize, Bitmap.Config.ARGB_8888)
    private val canvas = Canvas(square)
    private val paint = Paint(Paint.FILTER_BITMAP_FLAG)

    init {
        Core.setNumThreads(2)
        val file = File(context.noBackupFilesDir, MODEL)
        if (!file.exists()) {
            val temporary = File(file.parentFile, "$MODEL.tmp-${Thread.currentThread().id}")
            context.assets.open(MODEL).use { source -> temporary.outputStream().use(source::copyTo) }
            check(temporary.renameTo(file) || file.exists()) { "Cannot prepare model" }
            temporary.delete()
        }
        model = FaceDetectorYN.create(file.path, "", Size(inputSize.toDouble(), inputSize.toDouble()),
            0.55f, 0.3f, 5000)
    }

    fun detect(bitmap: Bitmap): Detection {
        val fit = fit(bitmap.width, bitmap.height)
        canvas.drawColor(Color.BLACK)
        canvas.drawBitmap(bitmap, null, RectF(fit[0], fit[1], fit[0] + fit[2], fit[1] + fit[3]), paint)
        Utils.bitmapToMat(square, rgba)
        return infer(bitmap.width, bitmap.height)
    }

    /** RGBA readback of a letterboxed GL texture, with the first row at bottom. */
    fun detectGl(bytes: ByteArray, width: Int, height: Int): Detection {
        rgba.put(0, 0, bytes)
        Core.flip(rgba, rgba, 0)
        return infer(width, height)
    }

    private fun infer(width: Int, height: Int): Detection {
        val start = SystemClock.elapsedRealtimeNanos()
        Imgproc.cvtColor(rgba, bgr, Imgproc.COLOR_RGBA2BGR)
        model.detect(bgr, result)
        val fit = fit(width, height)
        val faces = (0 until result.rows()).mapNotNull { row ->
            val r = FloatArray(15)
            result.get(row, 0, r)
            val x = (r[0] - fit[0]) / fit[2]
            val y = (r[1] - fit[1]) / fit[3]
            val w = r[2] / fit[2]
            val h = r[3] / fit[3]
            if (w <= 0 || h <= 0 || x + w <= 0 || y + h <= 0 || x >= 1 || y >= 1) null else {
                // Match the conservative face coverage policy of the iOS coordinate model.
                val cx = x + w / 2
                val cy = y + h / 2 - h * 0.05f
                val ew = max(w * 1.48f, 0.08f)
                val eh = max(h * 1.62f, 0.10f)
                val left = max(0f, cx - ew / 2)
                val top = max(0f, cy - eh / 2)
                FaceBox(left, top, min(1f, cx + ew / 2) - left, min(1f, cy + eh / 2) - top)
            }
        }
        return Detection(faces, (SystemClock.elapsedRealtimeNanos() - start) / 1e6)
    }

    private fun fit(width: Int, height: Int): FloatArray {
        val scale = inputSize.toFloat() / max(width, height)
        val w = width * scale
        val h = height * scale
        return floatArrayOf((inputSize - w) / 2, (inputSize - h) / 2, w, h)
    }

    override fun close() {
        rgba.release(); bgr.release(); result.release(); square.recycle()
        // OpenCV's generated FaceDetectorYN wrapper has no explicit native delete API.
        // Keep one detector per job, never per frame; ncnn is the planned production comparison.
    }

    companion object {
        const val MODEL = "face_detection_yunet_2023mar.onnx"

        fun pixelate(bitmap: Bitmap, faces: List<FaceBox>): Bitmap {
            val output = bitmap.copy(Bitmap.Config.ARGB_8888, true)
            val canvas = Canvas(output)
            val paint = Paint().apply { isFilterBitmap = false }
            faces.forEach { face ->
                val rect = Rect((face.x * bitmap.width).toInt().coerceIn(0, bitmap.width - 1),
                    (face.y * bitmap.height).toInt().coerceIn(0, bitmap.height - 1),
                    ((face.x + face.width) * bitmap.width).toInt().coerceIn(1, bitmap.width),
                    ((face.y + face.height) * bitmap.height).toInt().coerceIn(1, bitmap.height))
                if (!rect.isEmpty) {
                    // At most four blocks across a face; nearest-neighbor expansion.
                    val tile = Bitmap.createBitmap(4, 4, Bitmap.Config.ARGB_8888)
                    Canvas(tile).drawBitmap(bitmap, rect, Rect(0, 0, 4, 4), paint)
                    canvas.drawBitmap(tile, null, rect, paint)
                    tile.recycle()
                }
            }
            return output
        }
    }
}
