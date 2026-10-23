package com.zephyr.breeze.realsr.qnn

import android.content.Context
import android.util.Log

// Ported from HaoweiLi97/mihon_img_upscale (Apache License 2.0):
// app/src/main/java/eu/kanade/tachiyomi/util/qnn/QualcommHtp.kt
// （仅换包名与 so 库名；JNI 实现在 cpp/realsr_qnn/realsr_qnn_jni.cpp）

/** Runtime HTP capability detection shared by the QNN upscaler. */
object QualcommHtp {
    private val supportedArchitectures = setOf(69, 73, 75, 79, 81)

    @Volatile
    private var cachedArchitecture = UNQUERIED

    init {
        runCatching { System.loadLibrary("realsr_qnn") }
    }

    fun architecture(context: Context): Int? = architecture(context.applicationInfo.nativeLibraryDir)

    private fun architecture(nativeLibraryDir: String): Int? {
        var architecture = cachedArchitecture
        if (architecture == UNQUERIED) {
            synchronized(this) {
                architecture = cachedArchitecture
                if (architecture == UNQUERIED) {
                    architecture = runCatching {
                        nativeArchitecture(nativeLibraryDir)
                    }.getOrDefault(UNKNOWN)
                    if (architecture != UNKNOWN) cachedArchitecture = architecture
                    Log.d(TAG, "Detected Qualcomm HTP architecture: v$architecture")
                }
            }
        }
        return architecture.takeIf(supportedArchitectures::contains)
    }

    private external fun nativeArchitecture(nativeLibraryDir: String): Int

    private const val TAG = "QualcommHtp"
    private const val UNQUERIED = -1
    private const val UNKNOWN = 0
}
