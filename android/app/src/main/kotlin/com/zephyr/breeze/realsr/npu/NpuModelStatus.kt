package com.zephyr.breeze.realsr.npu

import java.io.File

// Ported from HaoweiLi97/mihon_img_upscale (Apache License 2.0):
// app/src/main/java/eu/kanade/tachiyomi/util/npu/NpuModelStatus.kt
sealed interface NpuModelStatus {
    data object Preparing : NpuModelStatus
    data class Ready(val file: File) : NpuModelStatus
    data class Failed(val message: String) : NpuModelStatus
}
