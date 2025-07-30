package fr.ideeri.doc_scan

import android.app.Activity
import android.graphics.*
import android.net.Uri
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.opencv.android.OpenCVLoader
import org.opencv.android.Utils
import org.opencv.core.Mat
import org.opencv.core.MatOfPoint
import org.opencv.core.MatOfPoint2f
import org.opencv.core.Point
import org.opencv.core.Size
import org.opencv.imgproc.Imgproc
import java.io.File
import java.io.FileOutputStream
import java.util.ArrayList
import kotlin.math.pow
import kotlin.math.sqrt

class DocScanPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private var activity: Activity? = null
    private var flutterResult: MethodChannel.Result? = null

    private var galleryLauncher: ActivityResultLauncher<String>? = null
    private var cameraLauncher: ActivityResultLauncher<Uri>? = null
    private var cameraImageUri: Uri? = null

    private val coroutineScope = CoroutineScope(Dispatchers.IO)

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "doc_scan")
        channel.setMethodCallHandler(this)
        if (!OpenCVLoader.initDebug()) {
            // Gestisci l'errore di inizializzazione se necessario
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        coroutineScope.cancel()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        setupActivityLaunchers(binding.activity as AppCompatActivity)
    }

    private fun setupActivityLaunchers(activity: AppCompatActivity) {
        galleryLauncher = activity.registerForActivityResult(ActivityResultContracts.GetContent()) { uri: Uri? ->
            handleImageUri(uri)
        }
        cameraLauncher = activity.registerForActivityResult(ActivityResultContracts.TakePicture()) { success: Boolean ->
            if (success) {
                handleImageUri(cameraImageUri)
            } else {
                handleImageUri(null)
            }
        }
    }

    private fun handleImageUri(uri: Uri?) {
        if (uri == null) {
            flutterResult?.success(null)
            return
        }
        coroutineScope.launch {
            val tempFile = saveUriToTempFile(uri)
            withContext(Dispatchers.Main) {
                if (tempFile != null) {
                    flutterResult?.success(tempFile.absolutePath)
                } else {
                    flutterResult?.error("SAVE_ERROR", "Unable to save temporary image", null)
                }
            }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        this.flutterResult = result

        when (call.method) {
            "getImage" -> {
                val source = call.argument<String>("source") ?: "gallery"
                getImage(source)
            }
            "detectEdges" -> {
                val imagePath = call.argument<String>("imagePath")
                if (imagePath == null) {
                    result.error("INVALID_ARGS", "imagePath is missing", null)
                    return
                }
                detectEdges(imagePath, result)
            }
            "applyCropAndSave" -> {
                val args = call.arguments as? Map<String, Any> ?: return
                val imagePath = args["imagePath"] as? String
                val quadValues = args["quad"] as? Map<String, Double>
                val format = args["format"] as? String
                val filter = args["filter"] as? String
                val brightness = args["brightness"] as? Double
                val contrast = args["contrast"] as? Double
                val threshold = args["threshold"] as? Double

                if (imagePath == null || quadValues == null || format == null || filter == null) {
                    result.error("INVALID_ARGS", "Missing arguments for applyCropAndSave", null)
                    return
                }
                applyCropAndSave(imagePath, quadValues, format, filter, brightness, contrast, threshold, result)
            }
            else -> result.notImplemented()
        }
    }

    private fun getImage(source: String) {
        val currentActivity = activity
        if (currentActivity == null) {
            flutterResult?.error("ACTIVITY_NULL", "Activity is not available", null)
            return
        }

        if (source == "gallery") {
            galleryLauncher?.launch("image/*") ?: flutterResult?.error("LAUNCHER_NOT_READY", "Gallery launcher is not initialized.", null)
        } else {
            val tempFile = File.createTempFile("temp_cam_image", ".jpg", currentActivity.cacheDir)
            cameraImageUri = FileProvider.getUriForFile(currentActivity, "${currentActivity.packageName}.provider", tempFile)
            cameraLauncher?.launch(cameraImageUri) ?: flutterResult?.error("LAUNCHER_NOT_READY", "Camera launcher is not initialized.", null)
        }
    }

    private fun detectEdges(imagePath: String, result: MethodChannel.Result) {
        coroutineScope.launch {
            val bitmap = BitmapFactory.decodeFile(imagePath)
            if (bitmap == null) {
                withContext(Dispatchers.Main) { result.error("FILE_NOT_FOUND", "Unable to decode image file", null) }
                return@launch
            }
            val originalMat = Mat()
            Utils.bitmapToMat(bitmap, originalMat)

            val ratio = originalMat.height() / 500.0
            val resizedMat = Mat()
            Imgproc.resize(originalMat, resizedMat, Size(originalMat.width() / ratio, 500.0))

            val grayMat = Mat()
            Imgproc.cvtColor(resizedMat, grayMat, Imgproc.COLOR_RGBA2GRAY)
            val blurredMat = Mat()
            Imgproc.bilateralFilter(grayMat, blurredMat, 9, 75.0, 75.0)

            val edgesMat = Mat()
            Imgproc.Canny(blurredMat, edgesMat, 75.0, 200.0)

            val kernel = Imgproc.getStructuringElement(Imgproc.MORPH_RECT, Size(7.0, 7.0))
            val closedMat = Mat()
            Imgproc.morphologyEx(edgesMat, closedMat, Imgproc.MORPH_CLOSE, kernel, Point(-1.0, -1.0), 2)

            val contours = ArrayList<MatOfPoint>()
            val hierarchy = Mat()
            Imgproc.findContours(closedMat, contours, hierarchy, Imgproc.RETR_EXTERNAL, Imgproc.CHAIN_APPROX_SIMPLE)

            var largestContour: MatOfPoint? = null
            var maxArea = 0.0
            val totalImageArea = resizedMat.size().area()

            for (contour in contours) {
                val area = Imgproc.contourArea(contour)
                if (area < totalImageArea * 0.04) continue

                val approxCurve = MatOfPoint2f()
                val contour2f = MatOfPoint2f(*contour.toArray())
                val peri = Imgproc.arcLength(contour2f, true)
                Imgproc.approxPolyDP(contour2f, approxCurve, 0.01 * peri, true)

                if (approxCurve.total() == 4L && Imgproc.isContourConvex(MatOfPoint(*approxCurve.toArray()))) {
                    if (area > maxArea) {
                        largestContour = MatOfPoint(*approxCurve.toArray())
                        maxArea = area
                    }
                }
            }

            val quad: Map<String, Double>
            if (largestContour != null) {
                val points = largestContour.toArray().map { Point(it.x * ratio / originalMat.width(), 1 - (it.y * ratio / originalMat.height())) }
                val sortedPoints = sortPoints(points)
                val quadrilateral = Quadrilateral(
                    topLeft = sortedPoints[0],
                    topRight = sortedPoints[1],
                    bottomLeft = sortedPoints[3],
                    bottomRight = sortedPoints[2]
                )
                quad = quadrilateral.toDictionary()
            } else {
                quad = defaultQuad().toDictionary()
            }

            originalMat.release()
            resizedMat.release()
            grayMat.release()
            blurredMat.release()
            edgesMat.release()
            closedMat.release()

            withContext(Dispatchers.Main) {
                result.success(quad)
            }
        }
    }

    private fun applyCropAndSave(imagePath: String, quadValues: Map<String, Double>, format: String, filter: String, brightness: Double?, contrast: Double?, threshold: Double?, result: MethodChannel.Result) {
        coroutineScope.launch {
            val bitmap = BitmapFactory.decodeFile(imagePath)
            if (bitmap == null) {
                withContext(Dispatchers.Main) { result.error("FILE_NOT_FOUND", "Unable to decode image file", null) }
                return@launch
            }
            val mat = Mat()
            Utils.bitmapToMat(bitmap, mat)

            val quad = Quadrilateral.fromMap(quadValues)
            val points = quad.toList().map { Point(it.x * mat.width(), (1 - it.y) * mat.height()) }
            val sortedPoints = sortPoints(points)

            val warpedMat = perspectiveTransform(mat, sortedPoints)

            var finalBitmap = Bitmap.createBitmap(warpedMat.cols(), warpedMat.rows(), Bitmap.Config.ARGB_8888)
            Utils.matToBitmap(warpedMat, finalBitmap)

            finalBitmap = applyFilter(finalBitmap, filter, brightness, contrast, threshold)

            val file = File.createTempFile("doc_scan_", ".$format", activity?.cacheDir)
            val fos = FileOutputStream(file)
            if (format == "pdf") {
                val pdfDocument = android.graphics.pdf.PdfDocument()
                val pageInfo = android.graphics.pdf.PdfDocument.PageInfo.Builder(finalBitmap.width, finalBitmap.height, 1).create()
                val page = pdfDocument.startPage(pageInfo)
                page.canvas.drawBitmap(finalBitmap, 0f, 0f, null)
                pdfDocument.finishPage(page)
                pdfDocument.writeTo(fos)
                pdfDocument.close()
            } else {
                finalBitmap.compress(Bitmap.CompressFormat.JPEG, 80, fos)
            }
            fos.close()

            mat.release()
            warpedMat.release()

            withContext(Dispatchers.Main) {
                result.success(file.absolutePath)
            }
        }
    }

    private fun perspectiveTransform(mat: Mat, points: List<Point>): Mat {
        val srcPoints = MatOfPoint2f().apply { fromList(points) }
        val widthA = sqrt((points[2].x - points[3].x).pow(2.0) + (points[2].y - points[3].y).pow(2.0))
        val widthB = sqrt((points[1].x - points[0].x).pow(2.0) + (points[1].y - points[0].y).pow(2.0))
        val maxWidth = maxOf(widthA, widthB).toInt()
        val heightA = sqrt((points[1].x - points[2].x).pow(2.0) + (points[1].y - points[2].y).pow(2.0))
        val heightB = sqrt((points[0].x - points[3].x).pow(2.0) + (points[0].y - points[3].y).pow(2.0))
        val maxHeight = maxOf(heightA, heightB).toInt()
        val dstPoints = MatOfPoint2f().apply {
            fromList(listOf(
                Point(0.0, 0.0),
                Point(maxWidth - 1.0, 0.0),
                Point(maxWidth - 1.0, maxHeight - 1.0),
                Point(0.0, maxHeight - 1.0)
            ))
        }
        val transformMatrix = Imgproc.getPerspectiveTransform(srcPoints, dstPoints)
        val warpedMat = Mat()
        Imgproc.warpPerspective(mat, warpedMat, transformMatrix, Size(maxWidth.toDouble(), maxHeight.toDouble()))
        return warpedMat
    }

    private fun applyFilter(bitmap: Bitmap, filterName: String, brightness: Double?, contrast: Double?, threshold: Double?): Bitmap {
        val mat = Mat()
        Utils.bitmapToMat(bitmap, mat)

        if (filterName != "none") {
            Imgproc.cvtColor(mat, mat, Imgproc.COLOR_RGBA2GRAY)
        }

        when (filterName) {
            "blackAndWhite" -> {
                mat.convertTo(mat, -1, 1.5, (1.0 - 1.5) * 127)
            }
            "custom" -> {
                var b = 0.0
                var c = 1.0
                if (brightness != null) {
                    b = (brightness / 100.0) * 127.0
                }
                if (contrast != null) {
                    c = contrast
                }
                mat.convertTo(mat, -1, c, b)

                if (threshold != null) {
                    // **CORREZIONE**: Limita il valore massimo della soglia per evitare un'immagine nera
                    val threshValue = (threshold * 255).coerceAtMost(254.0)
                    Imgproc.threshold(mat, mat, threshValue, 255.0, Imgproc.THRESH_BINARY)
                }
            }
        }

        if (mat.channels() == 1) {
            Imgproc.cvtColor(mat, mat, Imgproc.COLOR_GRAY2RGBA)
        }

        val resultBitmap = Bitmap.createBitmap(mat.cols(), mat.rows(), Bitmap.Config.ARGB_8888)
        Utils.matToBitmap(mat, resultBitmap)
        mat.release()

        return resultBitmap
    }

    private fun saveUriToTempFile(uri: Uri): File? {
        return try {
            val inputStream = activity?.contentResolver?.openInputStream(uri)
            val tempFile = File.createTempFile("temp_gallery_image", ".jpg", activity?.cacheDir)
            val fos = FileOutputStream(tempFile)
            inputStream?.copyTo(fos)
            inputStream?.close()
            fos.close()
            tempFile
        } catch (e: Exception) {
            null
        }
    }

    private fun sortPoints(points: List<Point>): List<Point> {
        val sortedBySum = points.sortedBy { it.x + it.y }
        val topLeft = sortedBySum.first()
        val bottomRight = sortedBySum.last()

        val sortedByDiff = points.sortedBy { it.y - it.x }
        val topRight = sortedByDiff.first()
        val bottomLeft = sortedByDiff.last()

        return listOf(topLeft, topRight, bottomRight, bottomLeft)
    }

    private fun defaultQuad(): Quadrilateral {
        return Quadrilateral(
            topLeft = Point(0.0, 1.0),
            topRight = Point(1.0, 1.0),
            bottomLeft = Point(0.0, 0.0),
            bottomRight = Point(1.0, 0.0)
        )
    }

    override fun onDetachedFromActivity() {
        activity = null
        galleryLauncher = null
        cameraLauncher = null
    }
    override fun onDetachedFromActivityForConfigChanges() { onDetachedFromActivity() }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) { onAttachedToActivity(binding) }
}

data class Quadrilateral(
    val topLeft: Point,
    val topRight: Point,
    val bottomLeft: Point,
    val bottomRight: Point
) {
    companion object {
        fun fromMap(map: Map<String, Double>): Quadrilateral {
            return Quadrilateral(
                topLeft = Point(map["topLeftX"]!!, map["topLeftY"]!!),
                topRight = Point(map["topRightX"]!!, map["topRightY"]!!),
                bottomLeft = Point(map["bottomLeftX"]!!, map["bottomLeftY"]!!),
                bottomRight = Point(map["bottomRightX"]!!, map["bottomRightY"]!!)
            )
        }
    }
    fun toList(): List<Point> = listOf(topLeft, topRight, bottomRight, bottomLeft)
    fun toDictionary(): Map<String, Double> {
        return mapOf(
            "topLeftX" to topLeft.x, "topLeftY" to topLeft.y,
            "topRightX" to topRight.x, "topRightY" to topRight.y,
            "bottomLeftX" to bottomLeft.x, "bottomLeftY" to bottomLeft.y,
            "bottomRightX" to bottomRight.x, "bottomRightY" to bottomRight.y
        )
    }
}
