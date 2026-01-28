package com.example.flutter_application_1

import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.FlutterInjector
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.io.OutputStream

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.flutter_application_1/helper"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "copyAsset") {
                val assetPath = call.argument<String>("assetPath")
                val targetPath = call.argument<String>("targetPath")

                if (assetPath != null && targetPath != null) {
                    // Run on background thread to avoid blocking UI
                    Thread {
                        try {
                            val loader = FlutterInjector.instance().flutterLoader()
                            val key = loader.getLookupKeyForAsset(assetPath)
                            val inputStream: InputStream = context.assets.open(key)
                            val outputFile = File(targetPath)
                            
                            // Ensure parent directories exist
                            outputFile.parentFile?.mkdirs()
                            
                            val outputStream: OutputStream = FileOutputStream(outputFile)

                            val buffer = ByteArray(1024 * 1024) // 1MB buffer
                            var length: Int
                            while (inputStream.read(buffer).also { length = it } > 0) {
                                outputStream.write(buffer, 0, length)
                            }

                            outputStream.flush()
                            outputStream.close()
                            inputStream.close()

                            runOnUiThread {
                                result.success(true)
                            }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("COPY_ERROR", "Failed to copy asset: ${e.message}", null)
                            }
                        }
                    }.start()
                } else {
                    result.error("INVALID_ARGUMENT", "Path cannot be null", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
