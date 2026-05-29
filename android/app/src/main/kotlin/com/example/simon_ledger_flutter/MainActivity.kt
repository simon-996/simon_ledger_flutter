package com.example.simon_ledger_flutter

import android.content.ContentUris
import android.content.Intent
import android.net.Uri
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
                    "openImageByName" -> {
                        try {
                            val imageName = call.argument<String>("imageName")
                            openImageByName(imageName)
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

    private fun openImageByName(imageName: String?) {
        val uri = findLatestImageUri(imageName)
        if (uri == null) {
            openGalleryApp()
            return
        }

        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "image/*")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        applicationContext.startActivity(intent)
    }

    private fun findLatestImageUri(imageName: String?): Uri? {
        if (imageName.isNullOrBlank()) return null

        val projection = arrayOf(MediaStore.Images.Media._ID)
        val selection = "${MediaStore.Images.Media.DISPLAY_NAME} LIKE ?"
        val selectionArgs = arrayOf("$imageName%")
        val sortOrder = "${MediaStore.Images.Media.DATE_ADDED} DESC"

        applicationContext.contentResolver.query(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            projection,
            selection,
            selectionArgs,
            sortOrder
        )?.use { cursor ->
            if (!cursor.moveToFirst()) return null
            val idColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
            val id = cursor.getLong(idColumn)
            return ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, id)
        }

        return null
    }
}
