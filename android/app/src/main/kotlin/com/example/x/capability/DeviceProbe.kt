package com.example.x.capability

import android.app.ActivityManager
import android.content.Context
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLSurface
import android.opengl.GLES20
import android.os.Build
import android.os.Debug
import android.os.PowerManager
import android.os.Process
import android.os.StatFs
import java.io.File

/**
 * Read-only device capability probe (Milestone 3, step 5A-1).
 *
 * Gathers the real hardware/memory/storage/thermal facts that determine which
 * on-device GGUF LLM class the phone can *plausibly* run. It deliberately does
 * NOT estimate tokens/sec or claim a definitive model — that decision belongs to
 * the later llama.cpp inference benchmark. Every field is best-effort: any API
 * that is missing on a given OS level or OEM is caught and reported as null
 * rather than crashing the probe.
 *
 * Everything returned is composed of types the Flutter StandardMessageCodec can
 * serialize (Map/List/String/Int/Long/Double/Boolean/null).
 */
class DeviceProbe(private val context: Context) {

    /** Collects the full capability snapshot as a codec-friendly map. */
    fun collect(includeSustainedLoad: Boolean): Map<String, Any?> {
        return mapOf(
            "hardware" to hardware(),
            "memory" to memory(),
            "storage" to storage(),
            "thermal" to thermal(),
            "sustained" to if (includeSustainedLoad) sustainedLoad() else null,
            "probeSchema" to 1,
        )
    }

    // --- Hardware -----------------------------------------------------------

    private fun hardware(): Map<String, Any?> {
        val abis: List<String> = try {
            Build.SUPPORTED_ABIS?.toList() ?: emptyList()
        } catch (_: Throwable) {
            emptyList()
        }

        val socManufacturer: String? = if (Build.VERSION.SDK_INT >= 31) {
            safe { Build.SOC_MANUFACTURER }
        } else null
        val socModel: String? = if (Build.VERSION.SDK_INT >= 31) {
            safe { Build.SOC_MODEL }
        } else null

        val cpu = readCpuInfo()

        return mapOf(
            "socManufacturer" to socManufacturer,
            "socModel" to socModel,
            "board" to safe { Build.BOARD },
            "hardware" to safe { Build.HARDWARE },
            "device" to safe { Build.DEVICE },
            "model" to safe { Build.MODEL },
            "manufacturer" to safe { Build.MANUFACTURER },
            "cpuModel" to cpu["model"],
            "cpuHardware" to cpu["hardware"],
            "cpuCores" to safe { Runtime.getRuntime().availableProcessors() },
            "supportedAbis" to abis,
            "is64Bit" to abis.any { it.contains("64") || it == "arm64-v8a" || it == "x86_64" },
            "androidRelease" to safe { Build.VERSION.RELEASE },
            "sdkInt" to Build.VERSION.SDK_INT,
            "gpu" to gpuInfo(),
        )
    }

    /** Parses /proc/cpuinfo for a human-readable core model, best-effort. */
    private fun readCpuInfo(): Map<String, String?> {
        return try {
            val text = File("/proc/cpuinfo").readText()
            var model: String? = null
            var hardware: String? = null
            for (line in text.lineSequence()) {
                val idx = line.indexOf(':')
                if (idx <= 0) continue
                val key = line.substring(0, idx).trim().lowercase()
                val value = line.substring(idx + 1).trim()
                if (model == null && (key == "model name" || key == "processor" && value.any { it.isLetter() })) {
                    if (value.any { it.isLetter() }) model = value
                }
                if (hardware == null && key == "hardware") hardware = value
            }
            mapOf("model" to model, "hardware" to hardware)
        } catch (_: Throwable) {
            mapOf("model" to null, "hardware" to null)
        }
    }

    /**
     * Queries GL_RENDERER / GL_VENDOR by spinning up a throwaway offscreen EGL
     * pbuffer context. Requires no permissions. Fully guarded: on any EGL/GL
     * failure it returns nulls instead of propagating.
     */
    private fun gpuInfo(): Map<String, Any?> {
        var display: EGLDisplay? = null
        var eglContext: EGLContext? = null
        var surface: EGLSurface? = null
        try {
            display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
            if (display == EGL14.EGL_NO_DISPLAY) return gpuNulls()
            val version = IntArray(2)
            if (!EGL14.eglInitialize(display, version, 0, version, 1)) return gpuNulls()

            val configAttribs = intArrayOf(
                EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
                EGL14.EGL_SURFACE_TYPE, EGL14.EGL_PBUFFER_BIT,
                EGL14.EGL_RED_SIZE, 8,
                EGL14.EGL_GREEN_SIZE, 8,
                EGL14.EGL_BLUE_SIZE, 8,
                EGL14.EGL_NONE
            )
            val configs = arrayOfNulls<EGLConfig>(1)
            val numConfig = IntArray(1)
            if (!EGL14.eglChooseConfig(display, configAttribs, 0, configs, 0, 1, numConfig, 0) ||
                numConfig[0] == 0 || configs[0] == null
            ) {
                return gpuNulls()
            }

            val ctxAttribs = intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE)
            eglContext = EGL14.eglCreateContext(
                display, configs[0], EGL14.EGL_NO_CONTEXT, ctxAttribs, 0
            )
            if (eglContext == EGL14.EGL_NO_CONTEXT) return gpuNulls()

            val surfAttribs = intArrayOf(
                EGL14.EGL_WIDTH, 1, EGL14.EGL_HEIGHT, 1, EGL14.EGL_NONE
            )
            surface = EGL14.eglCreatePbufferSurface(display, configs[0], surfAttribs, 0)
            if (surface == EGL14.EGL_NO_SURFACE) return gpuNulls()

            if (!EGL14.eglMakeCurrent(display, surface, surface, eglContext)) return gpuNulls()

            val renderer = safe { GLES20.glGetString(GLES20.GL_RENDERER) }
            val vendor = safe { GLES20.glGetString(GLES20.GL_VENDOR) }
            val glVersion = safe { GLES20.glGetString(GLES20.GL_VERSION) }
            return mapOf(
                "renderer" to renderer,
                "vendor" to vendor,
                "glVersion" to glVersion,
            )
        } catch (_: Throwable) {
            return gpuNulls()
        } finally {
            try {
                if (display != null) {
                    EGL14.eglMakeCurrent(
                        display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT
                    )
                    if (surface != null) EGL14.eglDestroySurface(display, surface)
                    if (eglContext != null) EGL14.eglDestroyContext(display, eglContext)
                    EGL14.eglTerminate(display)
                }
            } catch (_: Throwable) {
                // ignore teardown races
            }
        }
    }

    private fun gpuNulls(): Map<String, Any?> =
        mapOf("renderer" to null, "vendor" to null, "glVersion" to null)

    // --- Memory -------------------------------------------------------------

    private fun memory(): Map<String, Any?> {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
        val mi = ActivityManager.MemoryInfo()
        am?.getMemoryInfo(mi)

        // Per-app heap ceilings, in MB — the practical limit for on-heap work.
        val memoryClass = am?.memoryClass
        val largeMemoryClass = am?.largeMemoryClass

        // Current process footprint (PSS) in KB, best-effort.
        val processPssKb: Int? = try {
            val pid = Process.myPid()
            val infos: Array<Debug.MemoryInfo>? = am?.getProcessMemoryInfo(intArrayOf(pid))
            infos?.firstOrNull()?.totalPss
        } catch (_: Throwable) {
            null
        }

        return mapOf(
            "totalMemBytes" to safeLong { mi.totalMem },
            "availMemBytes" to safeLong { mi.availMem },
            "lowMemory" to safe { mi.lowMemory },
            "thresholdBytes" to safeLong { mi.threshold },
            "memoryClassMb" to memoryClass,
            "largeMemoryClassMb" to largeMemoryClass,
            "processPssKb" to processPssKb,
        )
    }

    // --- Storage ------------------------------------------------------------

    private fun storage(): Map<String, Any?> {
        // Internal data dir — where a bundled/downloaded model would live.
        val dataDir: File = context.filesDir
        val dataStat = statOf(dataDir)

        // App-specific external files dir (may be null on some devices).
        val extDir: File? = context.getExternalFilesDir(null)
        val extStat = extDir?.let { statOf(it) }

        return mapOf(
            "dataPath" to safe { dataDir.absolutePath },
            "dataTotalBytes" to dataStat["total"],
            "dataFreeBytes" to dataStat["free"],
            "dataUsableBytes" to dataStat["usable"],
            "externalPath" to (extDir?.absolutePath),
            "externalTotalBytes" to extStat?.get("total"),
            "externalFreeBytes" to extStat?.get("free"),
            "externalUsableBytes" to extStat?.get("usable"),
        )
    }

    private fun statOf(dir: File): Map<String, Long?> {
        return try {
            val stat = StatFs(dir.absolutePath)
            mapOf(
                "total" to stat.totalBytes,
                "free" to stat.freeBytes,
                "usable" to stat.availableBytes,
            )
        } catch (_: Throwable) {
            // Fallback to java.io.File space APIs.
            try {
                mapOf(
                    "total" to dir.totalSpace,
                    "free" to dir.freeSpace,
                    "usable" to dir.usableSpace,
                )
            } catch (_: Throwable) {
                mapOf("total" to null, "free" to null, "usable" to null)
            }
        }
    }

    // --- Thermal ------------------------------------------------------------

    private fun thermal(): Map<String, Any?> {
        val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        val status: Int? = if (Build.VERSION.SDK_INT >= 29 && pm != null) {
            safe { pm.currentThermalStatus }
        } else null

        return mapOf(
            "status" to status, // maps to PowerManager.THERMAL_STATUS_* (0..6)
            "statusLabel" to thermalLabel(status),
            // Ambient/skin temperature via HardwarePropertiesManager needs a
            // system/privileged permission and is unavailable to normal apps, so
            // it is intentionally not read here.
            "temperatureAvailable" to false,
        )
    }

    private fun thermalLabel(status: Int?): String? = when (status) {
        0 -> "none"
        1 -> "light"
        2 -> "moderate"
        3 -> "severe"
        4 -> "critical"
        5 -> "emergency"
        6 -> "shutdown"
        else -> null
    }

    /**
     * A short, bounded CPU exercise to hint at sustained-load behavior WITHOUT
     * an LLM: it runs a fixed integer workload for ~1.5s, reports a rough
     * ops/sec figure, and whether the thermal status escalated during the run.
     * This is a coarse indicator only — real sustained tokens/sec comes from the
     * llama.cpp benchmark, not from here.
     */
    private fun sustainedLoad(): Map<String, Any?> {
        val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        val before: Int? = if (Build.VERSION.SDK_INT >= 29 && pm != null) safe { pm.currentThermalStatus } else null

        val durationMs = 1500L
        val start = System.nanoTime()
        var ops = 0L
        var acc = 1.000001
        val deadline = start + durationMs * 1_000_000
        while (System.nanoTime() < deadline) {
            // Mixed int/float busywork; volatile-ish accumulation avoids JIT elision.
            var i = 0
            while (i < 100_000) {
                acc = (acc * 1.0000001) + 1.0
                if (acc > 1e12) acc = 1.000001
                i++
            }
            ops += 100_000
        }
        val elapsedSec = (System.nanoTime() - start) / 1e9
        val after: Int? = if (Build.VERSION.SDK_INT >= 29 && pm != null) safe { pm.currentThermalStatus } else null

        return mapOf(
            "elapsedSec" to elapsedSec,
            "opsPerSec" to if (elapsedSec > 0) (ops / elapsedSec) else null,
            "thermalBefore" to before,
            "thermalAfter" to after,
            "thermalEscalated" to (before != null && after != null && after > before),
            "checksum" to acc, // keeps the loop live; not meaningful to the caller
        )
    }

    // --- helpers ------------------------------------------------------------

    private inline fun <T> safe(block: () -> T): T? = try {
        block()
    } catch (_: Throwable) {
        null
    }

    private inline fun safeLong(block: () -> Long): Long? = try {
        block()
    } catch (_: Throwable) {
        null
    }
}
