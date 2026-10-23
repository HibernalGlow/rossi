# Rossi 的 QNN（Qualcomm HTP NPU）推理库。
#
# 结构对齐 HaoweiLi97/mihon_img_upscale 的 app/src/main/cpp/CMakeLists.txt
# （Apache License 2.0），但只保留 QNN 部分：Rossi 的 Vulkan 路线是外部
# waifu2x CLI 进程（由 script/android/build_waifu2x_cli_android.py 单独构建），
# 不像上游那样在同一个 JNI 库里链接 ncnn。
#
# 没有 QAIRT SDK 时以 stub 形态编译（ROSSI_ENABLE_QNN=0）：库可加载，
# 但 is_runtime_loadable()/architecture() 恒报不可用 —— CI 无 SDK 也能出包。

cmake_minimum_required(VERSION 3.18)
project(realsr_qnn)

set(CMAKE_CXX_STANDARD 17)

set(QNN_SDK_DIR "${QNN_SDK_DIR}" CACHE PATH "Path to the Qualcomm AI Runtime (QAIRT) SDK")

add_library(realsr_qnn SHARED
    qnn_backend.cpp
    spatial_qnn_runtime.cpp
    qnn_context_bridge.cpp
    realsr_qnn_jni.cpp
)

if(QNN_SDK_DIR AND ANDROID_ABI STREQUAL "arm64-v8a")
    if(NOT EXISTS "${QNN_SDK_DIR}/include/QNN/QnnInterface.h")
        message(FATAL_ERROR "QNN SDK headers not found under ${QNN_SDK_DIR}/include/QNN")
    endif()
    target_compile_definitions(realsr_qnn PRIVATE ROSSI_ENABLE_QNN=1)
    target_include_directories(realsr_qnn PRIVATE "${QNN_SDK_DIR}/include/QNN")
else()
    target_compile_definitions(realsr_qnn PRIVATE ROSSI_ENABLE_QNN=0)
endif()

target_link_libraries(realsr_qnn
    android
    log
    jnigraphics
    dl
)
