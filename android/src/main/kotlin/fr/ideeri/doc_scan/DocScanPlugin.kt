package fr.ideeri.doc_scan

import android.app.Activity
import android.content.Intent
import android.content.IntentSender
import android.net.Uri
import androidx.annotation.NonNull
import com.google.mlkit.vision.documentscanner.*

import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.PluginRegistry.ActivityResultListener

class DocScanPlugin: FlutterPlugin, MethodCallHandler, ActivityAware, ActivityResultListener {
    private lateinit var channel: MethodChannel
    private var activity: Activity? = null
    private var result: MethodChannel.Result? = null
    private val REQUEST_CODE = 1001

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "doc_scan")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this) // Register activity result listener
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onDetachedFromActivityForConfigChanges() {
        onDetachedFromActivity()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "scanDocument") {
            this.result = result
            val format = call.argument<String>("format") ?: "jpeg"
            scanDocument(format)
        } else {
            result.notImplemented()
        }
    }

    private fun scanDocument(format: String) {
        val resultFormat = if (format == "pdf") {
            GmsDocumentScannerOptions.RESULT_FORMAT_PDF
        } else {
            GmsDocumentScannerOptions.RESULT_FORMAT_JPEG
        }

        val options = GmsDocumentScannerOptions.Builder()
            .setGalleryImportAllowed(true)
            .setResultFormats(resultFormat)
            .build()

        val scanner = GmsDocumentScanning.getClient(options)

        scanner.getStartScanIntent(activity!!)
            .addOnSuccessListener { intentSender ->
                try {
                    activity?.startIntentSenderForResult(intentSender, REQUEST_CODE, null, 0, 0, 0, null)
                } catch (e: IntentSender.SendIntentException) {
                    result?.error("SCAN_ERROR", e.localizedMessage, null)
                }
            }
            .addOnFailureListener { e ->
                result?.error("SCAN_ERROR", e.localizedMessage, null)
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == REQUEST_CODE) {
            if (resultCode == Activity.RESULT_OK) {
                val scanResult = GmsDocumentScanningResult.fromActivityResultIntent(data)
                val fileUris = if (scanResult?.pdf != null) {
                    listOf(scanResult.pdf!!.uri.toString()) // Return PDF path
                } else {
                    scanResult?.pages?.map { it.imageUri.toString() } ?: emptyList()
                }
                result?.success(fileUris)
            } else {
                result?.success(null) // User canceled
            }
            return true
        }
        return false
    }
}
