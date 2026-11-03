package com.reaidea.lenshide.prototype

import android.content.Context
import android.content.pm.ApplicationInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
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

/** Face coverage ellipses plus person silhouette for one analysis image. No identity data. */
data class Detection(
    val faces: List<FaceBox>,
    val person: PersonMask?,
    val millis: Double,
    val segmentMillis: Double = 0.0,
)

/** One instance per worker/GL thread. No identity embeddings or persistence of detections. */
class FaceDetector(context: Context, val inputSize: Int = 320, detectPerson: Boolean = true) : AutoCloseable {
    private val initialized = OpenCVLoader.initLocal().also { check(it) { "OpenCV initialization failed" } }
    private val model: FaceDetectorYN
    private val segmenter = if (detectPerson && context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) {
        PersonSegmenter(context, inputSize)
    } else null
    private val rgba = Mat(inputSize, inputSize, CvType.CV_8UC4)
    private val bgr = Mat()
    private val result = Mat()
    private val square = Bitmap.createBitmap(inputSize, inputSize, Bitmap.Config.ARGB_8888)
    private val canvas = Canvas(square)
    private val paint = Paint(Paint.FILTER_BITMAP_FLAG)
    private val scratch = ByteArray(inputSize * inputSize * 4)

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
        val fit = placement(bitmap.width, bitmap.height)
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
        val fit = placement(width, height)
        val faces = (0 until result.rows()).mapNotNull { row ->
            val r = FloatArray(15)
            result.get(row, 0, r)
            // Analysis pixels -> display-normalized, top-left origin.
            val x = (r[0] - fit[0]) / fit[2]
            val y = (r[1] - fit[1]) / fit[3]
            val w = r[2] / fit[2]
            val h = r[3] / fit[3]
            if (w <= 0 || h <= 0 || x + w <= 0 || y + h <= 0 || x >= 1 || y >= 1) null else {
                // Same expansion as iOS expandedForFaceCoverage, kept unclamped for a true ellipse.
                val cx = x + w / 2
                val cy = y + h / 2 - h * 0.05f
                FaceBox(cx, cy, max(w * 1.48f, 0.08f) / 2, max(h * 1.62f, 0.10f) / 2)
            }
        }
        val detectMillis = (SystemClock.elapsedRealtimeNanos() - start) / 1e6

        val segmentStart = SystemClock.elapsedRealtimeNanos()
        val person = segmenter?.let {
            rgba.get(0, 0, scratch)
            it.segment(scratch)
        }
        val segmentMillis = (SystemClock.elapsedRealtimeNanos() - segmentStart) / 1e6
        return Detection(faces, person, detectMillis, segmentMillis)
    }

    /** Letterboxed placement of the source inside the square analysis image, in analysis pixels. */
    private fun placement(width: Int, height: Int): FloatArray {
        val scale = inputSize.toFloat() / max(width, height)
        val w = width * scale
        val h = height * scale
        return floatArrayOf((inputSize - w) / 2, (inputSize - h) / 2, w, h)
    }

    override fun close() {
        rgba.release(); bgr.release(); result.release(); square.recycle()
        segmenter?.close()
        // OpenCV's generated FaceDetectorYN wrapper has no explicit native delete API.
        // Keep one detector per job, never per frame; ncnn is the planned production comparison.
    }

    companion object {
        const val MODEL = "face_detection_yunet_2023mar.onnx"
    }
}
