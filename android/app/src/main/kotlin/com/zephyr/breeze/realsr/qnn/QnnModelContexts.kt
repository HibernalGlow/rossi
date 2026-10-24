package com.zephyr.breeze.realsr.qnn

import android.content.Context
import android.os.Build
import android.util.Log
import com.zephyr.breeze.realsr.npu.NpuModelStatus
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest

// Ported from HaoweiLi97/mihon_img_upscale (Apache License 2.0):
// app/src/main/java/eu/kanade/tachiyomi/util/qnn/QnnModelContexts.kt
//
// 与上游的差异（ROSSI，登记于 docs/upstream-sync.md）：
// 1. DLC 与 manifest 不随 APK assets 分发，而是 Rossi 首次使用时下载到
//    `<filesDir>/super_resolution/qnn/`；[modelRoot] 即该目录。
// 2. 下载产物不受 APK 签名保护，编译前按 manifest 的 SHA-256 校验 DLC 完整性
//    （上游的 assets 由包签名兜底，不需要这一步）。
// 3. 状态不用 kotlinx.coroutines 的 StateFlow（本工程 Kotlin 侧未引入该依赖），
//    换成线程安全快照，Dart 侧经 MethodChannel 读取。
// 其余设计原样保留：上下文身份 = 缓存版本|运行时版本|模型哈希|HTP 架构|
// Build.FINGERPRINT|主 ABI，落在 noBackupFilesDir；校验和原子提交；失败保留
// 状态供 UI 重试，不静默回退其它后端。

/** Compiles downloaded FP16 DLCs once per model/runtime/device, outside the image cache. */
object QnnModelContexts {
    const val CACHE_VERSION = "1"
    private const val RUNTIME_VERSION = "2.50.0"
    private const val TAG = "QnnModelContexts"

    private val statesLock = Any()
    private var statesMap: Map<String, NpuModelStatus> = emptyMap()

    fun states(): Map<String, NpuModelStatus> = synchronized(statesLock) { statesMap }

    init {
        runCatching { System.loadLibrary("realsr_qnn") }
    }

    internal fun contextFile(context: Context, modelRoot: File, modelName: String): File {
        val manifest =
            JSONObject(File(modelRoot, "manifest.json").bufferedReader().use { it.readText() })
        require(manifest.has(modelName) && modelName.matches(Regex("[a-z0-9-]+"))) { "Unknown QNN model: $modelName" }
        val modelHash = manifest.getString(modelName)
        val architecture = QualcommHtp.architecture(context) ?: error("No supported FP16 HTP runtime")
        // A driver/OS update can invalidate compiled binaries even on the same HTP architecture.
        val identity = listOf(
            CACHE_VERSION,
            RUNTIME_VERSION,
            modelHash,
            architecture.toString(),
            Build.FINGERPRINT,
            Build.SUPPORTED_ABIS.first(),
        ).joinToString("|")
        val key = sha256(identity.toByteArray()).take(32)
        return File(context.noBackupFilesDir, "qnn-contexts/$modelName/$key/context.bin")
    }

    /** Blocking: call on an IO worker. Serialization also prevents duplicate preparations from the UI and decoder. */
    @Synchronized
    fun prepare(context: Context, modelRoot: File, modelName: String, retry: Boolean = false): File? {
        val previous = states()[modelName]
        if (previous is NpuModelStatus.Failed && !retry) return null
        return runCatching {
            val manifest =
                JSONObject(File(modelRoot, "manifest.json").bufferedReader().use { it.readText() })
            check(manifest.has(modelName)) { "manifest.json does not list $modelName" }
            val dlcSource = File(modelRoot, "$modelName.dlc")
            check(dlcSource.isFile && dlcSource.length() > 0) { "DLC file missing: $dlcSource" }
            // ROSSI: 下载产物先验完整性，编译几秒级的失败要尽量发生在最前面。
            val expectedHash = manifest.getString(modelName)
            check(sha256(dlcSource) == expectedHash) { "DLC checksum mismatch: $modelName" }

            val binary = contextFile(context, modelRoot, modelName)
            val directory = requireNotNull(binary.parentFile)
            check(directory.isDirectory || directory.mkdirs()) { "Unable to create NPU model directory" }
            val checksum = File(directory, "context.sha256")
            if (binary.length() > 0 && checksum.isFile && checksum.readText() == sha256(binary)) {
                setState(modelName, NpuModelStatus.Ready(binary))
                Log.d(TAG, "Reusing persisted FP16 context: $modelName")
                return@runCatching binary
            }
            setState(modelName, NpuModelStatus.Preparing)
            // An uncommitted/modified binary must never be mistaken for a prepared context.
            check(!binary.exists() || binary.delete()) { "Unable to replace invalid NPU context" }
            checksum.delete()
            val dlc = File(directory, "model.dlc")
            val temporary = File(directory, "model.dlc.partial")
            try {
                dlcSource.inputStream().use { input ->
                    temporary.outputStream().use(input::copyTo)
                }
                check(temporary.renameTo(dlc)) { "Unable to stage NPU model" }
                val started = android.os.SystemClock.elapsedRealtime()
                val error =
                    nativeCompile(dlc.absolutePath, binary.absolutePath, context.applicationInfo.nativeLibraryDir)
                check(error.isEmpty()) { error }
                check(binary.length() > 0) { "NPU compilation produced an empty context" }
                val pendingChecksum = File(directory, "context.sha256.partial")
                pendingChecksum.writeText(sha256(binary))
                check(pendingChecksum.renameTo(checksum)) { "Unable to commit NPU context checksum" }
                Log.i(
                    TAG,
                    "Compiled FP16 $modelName on device in ${android.os.SystemClock.elapsedRealtime() - started} ms",
                )
            } finally {
                temporary.delete()
                dlc.delete()
            }
            setState(modelName, NpuModelStatus.Ready(binary))
            // Reclaim obsolete versions only after a replacement has been successfully prepared.
            directory.parentFile?.listFiles()?.filter {
                it.isDirectory && it != directory
            }?.forEach { it.deleteRecursively() }
            binary
        }.onFailure { error ->
            Log.w(TAG, "Unable to prepare $modelName; enhancement skipped", error)
            setState(modelName, NpuModelStatus.Failed(error.message.orEmpty()))
        }.getOrNull()
    }

    fun resetState(modelName: String) {
        synchronized(statesLock) { statesMap = statesMap - modelName }
    }

    private fun setState(modelName: String, status: NpuModelStatus) {
        synchronized(statesLock) { statesMap = statesMap + (modelName to status) }
    }

    private fun sha256(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256")
        .digest(bytes).joinToString("") { "%02x".format(it) }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(65536)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private external fun nativeCompile(dlcPath: String, contextPath: String, nativeLibraryDir: String): String
}
