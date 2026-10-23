package com.zephyr.breeze.realsr

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import com.zephyr.breeze.realsr.qnn.QnnModelContexts
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.Future

/**
 * Rossi 的 Qualcomm QNN（HTP NPU）推理封装。
 *
 * 上游参考 HaoweiLi97/mihon_img_upscale（Apache License 2.0）的
 * `util/waifu2x/Waifu2x.kt` + `waifu2x_jni.cpp`，只保留 QNN 路线：
 * Rossi 的 Vulkan 路线是外部 waifu2x CLI 进程，与这里的进程内 JNI 推理互不相干。
 *
 * 所有调用经单线程 executor 串行（编译 / 初始化 / 推理共用一把大锁，
 * 上游在 C++ 侧同样全局串行）；通道层把阻塞调用转发进来即可。
 */
object RealSrQnn {
    private const val TAG = "RealSrQnn"

    /** `librealsr_qnn.so` 是否加载成功（stub 构建 / 非 arm64 也能加载，运行时自报不可用）。 */
    val libraryLoaded: Boolean = runCatching { System.loadLibrary("realsr_qnn") }.isSuccess

    /** 一次推理所需的模型规格（Dart 侧模型配置透传）。 */
    data class ModelSpec(
        /** 与 manifest.json / `<name>.dlc` 对应的模型名。 */
        val name: String,
        /** 模型 prepadding（Real-CUGAN SE/Pro 2x = 18，与上游一致）。 */
        val padding: Int,
        /** Real-CUGan Pro 家族标志：仅 Pro + 单色源启用网点纹理防护方案。 */
        val isPro: Boolean,
    )

    sealed class Outcome {
        data class Success(val scale: Int, val elapsedMs: Long) : Outcome()
        data class Failure(val error: String) : Outcome()
    }

    private val executor: ExecutorService =
        Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "realsr-qnn").apply { priority = Thread.NORM_PRIORITY - 1 }
        }

    /** 上次成功初始化的上下文路径；同一路径复用已加载的 QNN 上下文。 */
    @Volatile
    private var initializedContextPath: String? = null

    fun runtimeAvailable(): Boolean {
        if (!libraryLoaded) return false
        return runCatching { nativeIsRuntimeAvailable() }.getOrDefault(false)
    }

    fun isInitialized(): Boolean =
        libraryLoaded && runCatching { nativeIsInitialized() }.getOrDefault(false)

    /** 只编译并缓存上下文（设置页「准备模型」用），不做推理。 */
    fun prepare(context: Context, modelRoot: File, modelName: String, retry: Boolean): Future<Outcome> =
        executor.submit {
            val binary = QnnModelContexts.prepare(context, modelRoot, modelName, retry)
            if (binary != null) Outcome.Success(scale = 0, elapsedMs = 0)
            else Outcome.Failure(
                (QnnModelContexts.states()[modelName] as? com.zephyr.breeze.realsr.npu.NpuModelStatus.Failed)
                    ?.message ?: "prepare failed",
            )
        }

    /**
     * 对一张 PNG 做超分：解码 → 上下文准备/复用 → NPU 推理 → PNG 编码。
     * 失败时 [outputPath] 上不留任何产物，调用方保留原图。
     */
    fun upscalePng(
        context: Context,
        inputPath: String,
        outputPath: String,
        modelRoot: File,
        model: ModelSpec,
        retryPrepare: Boolean,
    ): Future<Outcome> =
        executor.submit {
            val started = android.os.SystemClock.elapsedRealtime()
            try {
                val binary = QnnModelContexts.prepare(context, modelRoot, model.name, retryPrepare)
                    ?: return@submit Outcome.Failure(
                        (QnnModelContexts.states()[model.name] as? com.zephyr.breeze.realsr.npu.NpuModelStatus.Failed)
                            ?.message ?: "model prepare failed",
                    )

                val contextPath = binary.absolutePath
                if (initializedContextPath != contextPath || !isInitialized()) {
                    if (!nativeInit(contextPath, context.applicationInfo.nativeLibraryDir, model.padding)) {
                        initializedContextPath = null
                        return@submit Outcome.Failure("QNN context init failed: ${model.name}")
                    }
                    initializedContextPath = contextPath
                    Log.i(TAG, "QNN context loaded: $contextPath")
                }

                val options = BitmapFactory.Options().apply {
                    inPreferredConfig = Bitmap.Config.ARGB_8888
                }
                val input = BitmapFactory.decodeFile(inputPath, options)
                if (input == null) {
                    return@submit Outcome.Failure("decode failed: $inputPath")
                }
                val output = try {
                    nativeProcess(input, model.isPro)
                } finally {
                    input.recycle()
                }
                if (output == null) {
                    return@submit Outcome.Failure("NPU inference failed: ${model.name}")
                }
                try {
                    FileOutputStream(outputPath).use { stream ->
                        if (!output.compress(Bitmap.CompressFormat.PNG, 100, stream)) {
                            return@submit Outcome.Failure("PNG encode failed: $outputPath")
                        }
                    }
                } finally {
                    output.recycle()
                }
                val scale = nativeScale()
                if (scale < 2) {
                    File(outputPath).delete()
                    return@submit Outcome.Failure("NPU reported invalid scale: $scale")
                }
                val elapsed = android.os.SystemClock.elapsedRealtime() - started
                Log.i(TAG, "QNN upscale done: $inputPath -> $outputPath (${elapsed} ms, ${scale}x)")
                Outcome.Success(scale = scale, elapsedMs = elapsed)
            } catch (t: Throwable) {
                File(outputPath).delete()
                Log.e(TAG, "QNN upscale failed", t)
                Outcome.Failure(t.message ?: t.javaClass.simpleName)
            }
        }

    /** 交还 NPU 上下文（阅读会话结束时调用；磁盘上已编译的上下文不受影响）。 */
    fun release(): Future<Unit> =
        executor.submit {
            if (libraryLoaded) {
                runCatching { nativeShutdown() }
                initializedContextPath = null
            }
        }

    private external fun nativeIsRuntimeAvailable(): Boolean
    private external fun nativeInit(contextPath: String, nativeLibraryDir: String, padding: Int): Boolean
    private external fun nativeIsInitialized(): Boolean
    private external fun nativeScale(): Int
    private external fun nativeProcess(bitmap: Bitmap, isPro: Boolean): Bitmap?
    private external fun nativeShutdown()
}
