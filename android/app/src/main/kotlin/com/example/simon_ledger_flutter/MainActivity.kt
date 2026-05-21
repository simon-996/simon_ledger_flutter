package com.example.simon_ledger_flutter

import android.content.Intent
import android.provider.MediaStore
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "simon_ledger/gallery"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openGalleryApp" -> {
                        try {
                            openGalleryApp()
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("UNEXPECTED", e.toString(), null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun openGalleryApp() {
        val mainIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_APP_GALLERY)
        mainIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val resolved = mainIntent.resolveActivity(packageManager)
        if (resolved != null) {
            applicationContext.startActivity(mainIntent)
            return
        }

        val fallback = Intent(Intent.ACTION_VIEW, MediaStore.Images.Media.EXTERNAL_CONTENT_URI)
        fallback.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        applicationContext.startActivity(fallback)
    }
}
