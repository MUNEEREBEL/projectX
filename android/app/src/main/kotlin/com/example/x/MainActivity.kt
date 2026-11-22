package com.example.x

import com.example.x.capability.DeviceProbe
import com.example.x.scanner.DiscoveryEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class MainActivity : FlutterActivity() {
    private val METHOD_CHANNEL = "com.example.x/mediastore"
    private val EVENT_CHANNEL = "com.example.x/mediastore_stream"
    private val CAPABILITY_CHANNEL = "com.example.x/device_capability"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CAPABILITY_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "probe" -> {
                    val includeSustained = (call.argument<Boolean>("sustained")) ?: false
                    // Off the main thread: the sustained-load exercise blocks.
                    CoroutineScope(Dispatchers.Default).launch {
                        try {
                            val probe = DeviceProbe(applicationContext)
                            val snapshot = probe.collect(includeSustained)
                            runOnUiThread { result.success(snapshot) }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("CAPABILITY_ERROR", e.message, null)
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "ping" -> result.success("pong")
                "startDiscovery", "getMediaStoreFiles" -> {
                    val discoveryEngine = DiscoveryEngine(applicationContext.contentResolver)
                    CoroutineScope(Dispatchers.IO).launch {
                        try {
                            val list = discoveryEngine.discoverAll()
                            runOnUiThread {
                                result.success(list)
                            }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("DISCOVERY_ERROR", e.message, null)
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                private var scanJob: kotlinx.coroutines.Job? = null

                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    if (events == null) return
                    scanJob?.cancel()
                    val discoveryEngine = DiscoveryEngine(applicationContext.contentResolver)
                    scanJob = CoroutineScope(Dispatchers.IO).launch {
                        try {
                            discoveryEngine.discoverInBatches(batchSize = 500) { batch, isCompleted ->
                                val payload = mapOf(
                                    "batch" to batch,
                                    "isCompleted" to isCompleted
                                )
                                runOnUiThread {
                                    events.success(payload)
                                }
                            }
                        } catch (e: Exception) {
                            runOnUiThread {
                                events.error("DISCOVERY_ERROR", e.message, null)
                            }
                        }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    scanJob?.cancel()
                    scanJob = null
                }
            }
        )
    }
}

