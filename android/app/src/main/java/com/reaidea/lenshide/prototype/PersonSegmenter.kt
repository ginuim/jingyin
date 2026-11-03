package com.reaidea.lenshide.prototype

import android.content.Context
import org.tensorflow.lite.Interpreter
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.min

/**
 * On-device person silhouette from DeepLab-v3 (PASCAL VOC 21 classes, person = 15) on TensorFlow Lite CPU.
 *
 * Deliberately not MediaPipe ImageSegmenter: its segmentation graph initialises GL post-processing and
 * fails on devices or emulators without GLES 3.1 compute support. This path has no GL dependency.
 * Input is the same 320×320 letterboxed RGBA as the face detector. Masks are never persisted.
 * The model weights are a lab-only dependency; see android/THIRD_PARTY.md before any release.
 */
class PersonSegmenter(context: Context, private val analysisSize: Int) : AutoCloseable {
    private val interpreter: Interpreter
    private val modelSize: Int
    private val classes: Int
    private val input: ByteBuffer
    private val output: ByteBuffer

    init {
        val bytes = context.assets.open(MODEL).use { it.readBytes() }
        val model = ByteBuffer.allocateDirect(bytes.size).order(ByteOrder.nativeOrder()).put(bytes)
        model.rewind()
        interpreter = Interpreter(model, Interpreter.Options().setNumThreads(2))
        val inputTensor = interpreter.getInputTensor(0)
        val outputTensor = interpreter.getOutputTensor(0)
        val inputShape = inputTensor.shape()
        val outputShape = outputTensor.shape()
        check(inputShape.size == 4 && inputShape[0] == 1 && inputShape[1] == inputShape[2] && inputShape[3] == 3) {
            "Unexpected segmenter input ${inputShape.contentToString()}"
        }
        check(outputShape.size == 4 && outputShape[0] == 1 && outputShape[1] == inputShape[1] &&
            outputShape[2] == inputShape[2] && outputShape[3] > PERSON_CLASS) {
            "Unexpected segmenter output ${outputShape.contentToString()}"
        }
        check(inputTensor.dataType() == org.tensorflow.lite.DataType.FLOAT32) { "Expected float32 input" }
        modelSize = inputShape[1]
        classes = outputShape[3]
        input = ByteBuffer.allocateDirect(modelSize * modelSize * 3 * 4).order(ByteOrder.nativeOrder())
        output = ByteBuffer.allocateDirect(modelSize * modelSize * classes * 4).order(ByteOrder.nativeOrder())
    }

    /** [rgba] is top-first RGBA8 of exactly analysisSize². Returns a dilated person mask on the same grid. */
    fun segment(rgba: ByteArray, person: Boolean = true, pets: Boolean = false): PersonMask {
        require(rgba.size == analysisSize * analysisSize * 4) { "Unexpected analysis size" }
        fillInput(rgba)
        input.rewind(); output.clear()
        interpreter.run(input, output)
        output.rewind()

        // Per-pixel margin: person logit minus the strongest other class. Argmax is margin > 0.
        // No exp/softmax per class keeps the CPU cost to one pass over the logits.
        val floats = output.asFloatBuffer()
        val margin = FloatArray(modelSize * modelSize)
        for (index in margin.indices) {
            val base = index * classes
            var strongestTarget = Float.NEGATIVE_INFINITY
            var strongestOther = Float.NEGATIVE_INFINITY
            for (c in 0 until classes) {
                val value = floats.get(base + c)
                if ((person && c == PERSON_CLASS) || (pets && (c == CAT_CLASS || c == DOG_CLASS))) {
                    strongestTarget = maxOf(strongestTarget, value)
                } else strongestOther = maxOf(strongestOther, value)
            }
            margin[index] = strongestTarget - strongestOther
        }

        // Bilinear resample of the margin to the analysis grid, then threshold at zero.
        val binary = ByteArray(analysisSize * analysisSize)
        val scale = modelSize.toFloat() / analysisSize
        for (y in 0 until analysisSize) {
            val sy = ((y + 0.5f) * scale - 0.5f).coerceIn(0f, modelSize - 1f)
            val y0 = sy.toInt(); val y1 = min(y0 + 1, modelSize - 1); val fy = sy - y0
            for (x in 0 until analysisSize) {
                val sx = ((x + 0.5f) * scale - 0.5f).coerceIn(0f, modelSize - 1f)
                val x0 = sx.toInt(); val x1 = min(x0 + 1, modelSize - 1); val fx = sx - x0
                val top = margin[y0 * modelSize + x0] + (margin[y0 * modelSize + x1] - margin[y0 * modelSize + x0]) * fx
                val bottom = margin[y1 * modelSize + x0] + (margin[y1 * modelSize + x1] - margin[y1 * modelSize + x0]) * fx
                binary[y * analysisSize + x] = if (top + (bottom - top) * fy > 0f) 0xFF.toByte() else 0
            }
        }
        return PersonMask.dilated(analysisSize, binary)
    }

    /** Bilinear RGBA→RGB resample to the model size, normalised to [-1, 1] (x − 127.5) / 127.5. */
    private fun fillInput(rgba: ByteArray) {
        input.clear()
        val scale = analysisSize.toFloat() / modelSize
        for (y in 0 until modelSize) {
            val sy = ((y + 0.5f) * scale - 0.5f).coerceIn(0f, analysisSize - 1f)
            val y0 = sy.toInt(); val y1 = min(y0 + 1, analysisSize - 1); val fy = sy - y0
            for (x in 0 until modelSize) {
                val sx = ((x + 0.5f) * scale - 0.5f).coerceIn(0f, analysisSize - 1f)
                val x0 = sx.toInt(); val x1 = min(x0 + 1, analysisSize - 1); val fx = sx - x0
                for (c in 0 until 3) {
                    val p00 = channel(rgba, y0, x0, c); val p01 = channel(rgba, y0, x1, c)
                    val p10 = channel(rgba, y1, x0, c); val p11 = channel(rgba, y1, x1, c)
                    val top = p00 + (p01 - p00) * fx
                    val bottom = p10 + (p11 - p10) * fx
                    input.putFloat(((top + (bottom - top) * fy) - 127.5f) / 127.5f)
                }
            }
        }
        input.rewind()
    }

    private fun channel(rgba: ByteArray, y: Int, x: Int, c: Int): Float =
        (rgba[(y * analysisSize + x) * 4 + c].toInt() and 0xFF).toFloat()

    override fun close() = interpreter.close()

    companion object {
        const val MODEL = "deeplab_v3.tflite"
        const val PERSON_CLASS = 15
        private const val CAT_CLASS = 8
        private const val DOG_CLASS = 12
    }
}
