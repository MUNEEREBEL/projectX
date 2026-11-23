package com.example.x

import android.content.Intent
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
    private val OVERLAY_CHANNEL = "com.example.x/assistive_overlay"
    private val STORAGE_CHANNEL = "com.example.x/storage_channel"
    private var overlayChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        overlayChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, OVERLAY_CHANNEL)
        overlayChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "canDrawOverlays" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        result.success(Settings.canDrawOverlays(this))
                    } else {
                        result.success(true)
                    }
                }
                "requestOverlayPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName")
                        )
                        startActivity(intent)
                        result.success(true)
                    } else {
                        result.success(true)
                    }
                }
                "startAssistiveBall" -> {
                    try {
                        val intent = Intent(this, AssistiveBallService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_START_FAILED", e.message, null)
                    }
                }
                "stopAssistiveBall" -> {
                    try {
                        val intent = Intent(this, AssistiveBallService::class.java)
                        stopService(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_STOP_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

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
                "scanFolderNative" -> {
                    val pathOrUri = call.argument<String>("target") ?: ""
                    CoroutineScope(Dispatchers.IO).launch {
                        try {
                            val matchingPaths = mutableListOf<String>()
                            val supportedExts = setOf("pdf", "png", "jpg", "jpeg", "docx")

                            if (pathOrUri.startsWith("content://")) {
                                val treeUri = Uri.parse(pathOrUri)
                                try {
                                    val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION
                                    applicationContext.contentResolver.takePersistableUriPermission(treeUri, flags)
                                } catch (_: Exception) {}

                                val docFile = DocumentFile.fromTreeUri(applicationContext, treeUri)
                                if (docFile != null && docFile.isDirectory) {
                                    fun scanRecursive(dir: DocumentFile, depth: Int) {
                                        if (depth > 3) return
                                        for (child in dir.listFiles()) {
                                            if (child.isDirectory) {
                                                scanRecursive(child, depth + 1)
                                            } else if (child.isFile) {
                                                val name = child.name ?: continue
                                                val ext = name.substringAfterLast('.', "").lowercase()
                                                if (ext in supportedExts) {
                                                    val cachedFile = File(applicationContext.cacheDir, "vault_import_${System.currentTimeMillis()}_$name")
                                                    applicationContext.contentResolver.openInputStream(child.uri)?.use { input ->
                                                        cachedFile.outputStream().use { output ->
                                                            input.copyTo(output)
                                                        }
                                                    }
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
                            }

                            runOnUiThread { result.success(matchingPaths) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("SCAN_FAILED", e.message, null) }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Handle case where activity opened from AssistiveBall tap
        checkIntentForCopilot(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        checkIntentForCopilot(intent)
    }

    private fun checkIntentForCopilot(intent: Intent?) {
        if (intent?.getBooleanExtra("OPEN_COPILOT", false) == true) {
            overlayChannel?.invokeMethod("onOpenCopilotRequested", null)
        }
    }
}
