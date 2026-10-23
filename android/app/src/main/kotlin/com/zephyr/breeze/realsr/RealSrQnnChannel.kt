package com.zephyr.breeze.realsr

import android.content.Context
import android.util.Log
import com.zephyr.breeze.realsr.npu.NpuModelStatus
import com.zephyr.breeze.realsr.qnn.QualcommHtp
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.TimeUnit

/**
 * `realsr_super_resolution` MethodChannel 的 QNN（Qualcomm NPU）方法组。
 *
 * 方法（与 Dart 侧 `AndroidQnnEngine` 一一对应）：
 * - `qnnProbe`：探测 QNN 运行时与 HTP 架构（v69/v73/v75/v79/v81）。
 * - `qnnPrepare`：编译并缓存指定模型的上下文（设置页 / 调试用）。
 * - `qnnUpscale`：对一张 PNG 做端到端 NPU 超分。
 * - `qnnStatus`：各模型的准备状态（preparing/ready/failed/idle）。
 * - `qnnRelease`：交还 NPU 上下文（阅读会话结束）。
 *
 * 阻塞调用一律转发到 RealSrQnn 的单线程 executor；结果回投主线程。
 */
object RealSrQnnChannel {
    private const val TAG = "RealSrQnnChannel"
    private const val PROBE_TIMEOUT_MS = 10_000L
    private const val PREPARE_TIMEOUT_MS = 60_000L
    private const val UPSCALE_TIMEOUT_MS = 120_000L

    /** 处理 QNN 方法；非 QNN 方法返回 false（调用方回退到 notImplemented）。 */
    fun tryHandle(context: Context, call: MethodCall, result: MethodChannel.Result): Boolean {
        if (!call.method.startsWith("qnn")) return false
        when (call.method) {
            "qnnProbe" -> probe(context, result)
            "qnnPrepare" -> prepare(context, call, result)
            "qnnUpscale" -> upscale(context, call, result)
            "qnnStatus" -> status(result)
            "qnnRelease" -> release(result)
            else -> result.notImplemented()
        }
        return true
    }

    private fun probe(context: Context, result: MethodChannel.Result) {
        Thread {
            try {
                val runtimeAvailable = RealSrQnn.runtimeAvailable()
                val architecture = if (runtimeAvailable) {
                    runCatching { QualcommHtp.architecture(context) }.getOrNull()
                } else {
                    null
                }
                post(result) {
                    mapOf(
                        "libraryLoaded" to RealSrQnn.libraryLoaded,
                        "runtimeAvailable" to runtimeAvailable,
                        // null = 不支持 / 探测失败；数字 = 实际 HTP 架构（受支持时非空）
                        "architecture" to architecture,
                    )
                }
            } catch (e: Exception) {
                postError(result, "QNN_PROBE_ERROR", e)
            }
        }.start()
    }

    private fun prepare(context: Context, call: MethodCall, result: MethodChannel.Result) {
        val modelRoot = call.argument<String>("modelRoot")
        val modelName = call.argument<String>("modelName")
        val retry = call.argument<Boolean>("retry") ?: false
        if (modelRoot == null || modelName == null) {
            result.error("INVALID_ARGS", "modelRoot and modelName are required", null)
            return
        }
        try {
            val outcome = RealSrQnn.prepare(context, File(modelRoot), modelName, retry)
                .get(PREPARE_TIMEOUT_MS, TimeUnit.MILLISECONDS)
            post(result) { outcomeToMap(outcome) }
        } catch (e: Exception) {
            postError(result, "QNN_PREPARE_ERROR", e)
        }
    }

    private fun upscale(context: Context, call: MethodCall, result: MethodChannel.Result) {
        val inputPath = call.argument<String>("inputPath")
        val outputPath = call.argument<String>("outputPath")
        val modelRoot = call.argument<String>("modelRoot")
        val modelName = call.argument<String>("modelName")
        if (inputPath == null || outputPath == null || modelRoot == null || modelName == null) {
            result.error(
                "INVALID_ARGS",
                "inputPath, outputPath, modelRoot and modelName are required",
                null,
            )
            return
        }
        val padding = call.argument<Int>("padding") ?: 18
        val isPro = call.argument<Boolean>("isPro") ?: false
        val retryPrepare = call.argument<Boolean>("retryPrepare") ?: true
        Thread {
            try {
                val outcome = RealSrQnn.upscalePng(
                    context = context,
                    inputPath = inputPath,
                    outputPath = outputPath,
                    modelRoot = File(modelRoot),
                    model = RealSrQnn.ModelSpec(name = modelName, padding = padding, isPro = isPro),
                    retryPrepare = retryPrepare,
                ).get(UPSCALE_TIMEOUT_MS, TimeUnit.MILLISECONDS)
                post(result) { outcomeToMap(outcome) }
            } catch (e: Exception) {
                postError(result, "QNN_UPSCALE_ERROR", e)
            }
        }.start()
    }

    private fun status(result: MethodChannel.Result) {
        val models = RealSrQnnStatus.snapshot().mapValues { (_, status) ->
            when (status) {
                is NpuModelStatus.Preparing -> mapOf("state" to "preparing")
                is NpuModelStatus.Ready -> mapOf("state" to "ready")
                is NpuModelStatus.Failed -> mapOf("state" to "failed", "error" to status.message)
            }
        }
        post(result) { mapOf("models" to models) }
    }

    private fun release(result: MethodChannel.Result) {
        try {
            RealSrQnn.release().get(PROBE_TIMEOUT_MS, TimeUnit.MILLISECONDS)
            post(result) { null }
        } catch (e: Exception) {
            postError(result, "QNN_RELEASE_ERROR", e)
        }
    }

    private fun outcomeToMap(outcome: RealSrQnn.Outcome): Map<String, Any?> = when (outcome) {
        is RealSrQnn.Outcome.Success ->
            mapOf(
                "success" to true,
                "scale" to outcome.scale,
                "elapsedMs" to outcome.elapsedMs,
                "error" to null,
            )
        is RealSrQnn.Outcome.Failure ->
            mapOf("success" to false, "scale" to 0, "elapsedMs" to 0, "error" to outcome.error)
    }

    private fun post(result: MethodChannel.Result, value: () -> Any?) {
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            runCatching { result.success(value()) }
        }
    }

    private fun postError(result: MethodChannel.Result, code: String, e: Exception) {
        Log.w(TAG, "$code: ${e.message}", e)
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            runCatching { result.error(code, e.message, e.stackTraceToString()) }
        }
    }
}

/** QnnModelContexts 状态的稳定视图（避免 channel 层直接摸内部对象）。 */
private object RealSrQnnStatus {
    fun snapshot(): Map<String, NpuModelStatus> = com.zephyr.breeze.realsr.qnn.QnnModelContexts.states()
}
