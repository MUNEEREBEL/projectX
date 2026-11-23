package com.example.x

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.io.File

class MainActivity : FlutterActivity() {
    private val STORAGE_CHANNEL = "com.example.x/storage_channel"
    private val REQ_PICK_FOLDER = 9921
    private var pendingFolderResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Native Storage & Folder Discovery Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, STORAGE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasStoragePermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        result.success(Environment.isExternalStorageManager())
                    } else {
                        result.success(true)
                    }
                }
                "requestStoragePermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        val has = Environment.isExternalStorageManager()
                        if (!has) {
                            try {
                                val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
                                    data = Uri.parse("package:$packageName")
                                }
                                startActivity(intent)
                            } catch (e: Exception) {
                                val intent = Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
                                startActivity(intent)
                            }
                        }
                        result.success(has)
                    } else {
                        result.success(true)
                    }
                }
                "pickFolder" -> {
                    pendingFolderResult = result
                    try {
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                            addFlags(
                                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                                Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
                            )
                        }
                        startActivityForResult(intent, REQ_PICK_FOLDER)
                    } catch (e: Exception) {
                        pendingFolderResult = null
                        result.error("PICK_FOLDER_ERROR", e.message, null)
                    }
                }
                "scanFolderNative" -> {
                    val pathOrUri = call.argument<String>("target") ?: ""
                    CoroutineScope(Dispatchers.IO).launch {
                        try {
                            val matchingPaths = scanFilesFromTarget(pathOrUri)
                            runOnUiThread { result.success(matchingPaths) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("SCAN_FAILED", e.message, null) }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_PICK_FOLDER) {
            val result = pendingFolderResult
            pendingFolderResult = null
            if (result == null) return

            if (resultCode == Activity.RESULT_OK && data?.data != null) {
                val treeUri = data.data!!
                CoroutineScope(Dispatchers.IO).launch {
                    try {
                        val takeFlags = Intent.FLAG_GRANT_READ_URI_PERMISSION
                        try {
                            applicationContext.contentResolver.takePersistableUriPermission(treeUri, takeFlags)
                        } catch (_: Exception) {}

                        val docFile = DocumentFile.fromTreeUri(applicationContext, treeUri)
                        val folderName = docFile?.name ?: "Monitored Folder"
                        val matchingPaths = scanFilesFromTarget(treeUri.toString())

                        val resultMap = mapOf(
                            "folderUri" to treeUri.toString(),
                            "folderName" to folderName,
                            "files" to matchingPaths
                        )
                        runOnUiThread { result.success(resultMap) }
                    } catch (e: Exception) {
                        runOnUiThread { result.error("SCAN_ERROR", e.message, null) }
                    }
                }
            } else {
                result.success(null)
            }
        }
    }

    private fun scanFilesFromTarget(pathOrUri: String): List<String> {
        val matchingPaths = mutableListOf<String>()
        val supportedExts = setOf("pdf", "png", "jpg", "jpeg", "docx")

        if (pathOrUri.startsWith("content://")) {
            val treeUri = Uri.parse(pathOrUri)
            try {
                applicationContext.contentResolver.takePersistableUriPermission(
                    treeUri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION
                )
            } catch (_: Exception) {}

            val docFile = DocumentFile.fromTreeUri(applicationContext, treeUri)
            if (docFile != null && docFile.isDirectory) {
                fun scanRecursive(dir: DocumentFile, depth: Int) {
                    if (depth > 3) return
                    val children = dir.listFiles()
                    for (child in children) {
                        if (child.isDirectory) {
                            scanRecursive(child, depth + 1)
                        } else if (child.isFile) {
                            val name = child.name ?: continue
                            val ext = name.substringAfterLast('.', "").lowercase()
                            if (ext in supportedExts) {
                                val cachedFile = File(applicationContext.cacheDir, "vault_staging_${System.currentTimeMillis()}_$name")
                                copyOrDownsample(child.uri, cachedFile, ext)
                                matchingPaths.add(cachedFile.absolutePath)
                            }
                        }
                    }
                }
                scanRecursive(docFile, 0)
            }
        } else {
            val dir = File(pathOrUri)
            if (dir.exists() && dir.isDirectory) {
                dir.walkTopDown().maxDepth(3).forEach { file ->
                    if (file.isFile) {
                        val ext = file.extension.lowercase()
                        if (ext in supportedExts) {
                            matchingPaths.add(file.absolutePath)
                        }
                    }
                }
            }

            // Fallback for Scoped Storage: try resolving as primary external storage DocumentFile
            if (matchingPaths.isEmpty()) {
                val rel = pathOrUri.replace("/storage/emulated/0/", "").replace("/storage/emulated/0", "").trim('/')
                if (rel.isNotEmpty()) {
                    val encoded = Uri.encode(rel)
                    val synthUri = Uri.parse("content://com.android.externalstorage.documents/tree/primary%3A$encoded")
                    val docFile = DocumentFile.fromTreeUri(applicationContext, synthUri)
                    if (docFile != null && docFile.isDirectory) {
                        for (child in docFile.listFiles()) {
                            if (child.isFile) {
                                val name = child.name ?: continue
                                val ext = name.substringAfterLast('.', "").lowercase()
                                if (ext in supportedExts) {
                                    val cachedFile = File(applicationContext.cacheDir, "vault_staging_${System.currentTimeMillis()}_$name")
                                    copyOrDownsample(child.uri, cachedFile, ext)
                                    matchingPaths.add(cachedFile.absolutePath)
                                }
                            }
                        }
                    }
                }
            }
        }

        return matchingPaths
    }

    private fun copyOrDownsample(uri: Uri, cachedFile: File, ext: String) {
        if (ext in setOf("jpg", "jpeg", "png")) {
            try {
                val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                applicationContext.contentResolver.openInputStream(uri)?.use { input ->
                    BitmapFactory.decodeStream(input, null, options)
                }
                val maxDim = maxOf(options.outWidth, options.outHeight)
                var sampleSize = 1
                if (maxDim > 1280) {
                    sampleSize = maxDim / 1280
                }
                val decodeOptions = BitmapFactory.Options().apply { inSampleSize = sampleSize }
                val bitmap = applicationContext.contentResolver.openInputStream(uri)?.use { input ->
                    BitmapFactory.decodeStream(input, null, decodeOptions)
                }
                if (bitmap != null) {
                    cachedFile.outputStream().use { out ->
                        bitmap.compress(Bitmap.CompressFormat.JPEG, 75, out)
                    }
                    bitmap.recycle()
                    return
                }
            } catch (_: Exception) {}
        }

        // Direct stream copy
        applicationContext.contentResolver.openInputStream(uri)?.use { input ->
            cachedFile.outputStream().use { output ->
                input.copyTo(output)
            }
        }
    }
}
