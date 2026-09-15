cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "gpu_texture_poc.cpp"
  "wgpu_texture_poc.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# 本仓库源码注释使用中文，而 MSVC 在中文 Windows 上默认按 GBK(936) 解析源文件，
# 会把 UTF-8 的中文字节序列读错。典型症状是注释收尾处吞掉换行，之后整片语法
# 雪崩；并且 C4819 还会被 apply_standard_settings 里的 /WX 升级成 error C2220。
# 显式声明源文件与执行字符集为 UTF-8 即可根治。
target_compile_options(${BINARY_NAME} PRIVATE "/utf-8")

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")

# Gate A / 风险 1：用 D3D12 创建 shared texture 交给 Flutter 合成。
#   d3d12.lib -> D3D12CreateDevice / CreateCommittedResource / CreateSharedHandle
#   dxgi.lib  -> CreateDXGIFactory2 / EnumAdapterByGpuPreference / GetGraphicsAdapter 的 LUID
target_link_libraries(${BINARY_NAME} PRIVATE "d3d12.lib" "dxgi.lib")

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)

# ─────────────────────────────────────────────────────────────────────────────
# Gate A / 风险 2：Rust + wgpu 探针
#
# 探针编译成 cdylib（wgpu_probe.dll），运行时由 wgpu_texture_poc.cpp
# 用 LoadLibrary 动态加载，不走 import lib —— 免得把 CMake 的链接顺序
# 和 cargo 的构建顺序耦在一起。
# ─────────────────────────────────────────────────────────────────────────────
set(WGPU_PROBE_DIR "${CMAKE_SOURCE_DIR}/../rust/wgpu-probe")
set(WGPU_PROBE_MANIFEST "${WGPU_PROBE_DIR}/Cargo.toml")
set(WGPU_PROBE_LIB_SRC "${WGPU_PROBE_DIR}/src/lib.rs")
set(WGPU_PROBE_DLL "${WGPU_PROBE_DIR}/target/release/wgpu_probe.dll")

find_program(CARGO_EXECUTABLE cargo)
if(NOT CARGO_EXECUTABLE AND DEFINED ENV{CARGO_HOME})
  set(CARGO_EXECUTABLE "$ENV{CARGO_HOME}/bin/cargo.exe")
endif()

if(CARGO_EXECUTABLE AND EXISTS "${CARGO_EXECUTABLE}")
  message(STATUS "wgpu 探针: 使用 cargo = ${CARGO_EXECUTABLE}")

  # 必须显式覆盖 CARGO_TARGET_DIR。
  #
  # Phase 0 的环境脚本里为了让 Breeze 主项目的产物留在 D 盘，设了
  #   CARGO_TARGET_DIR = <repo>/rust/target
  # 这个变量会被本 PoC 的 cargo 调用继承，于是产物跑进主项目的 target 目录，
  # 与那边已有的产物混用。症状是编译期蹦出
  #   "only metadata stub found for `rlib` dependency `core`"
  # 这类看起来像工具链坏掉的错误，极难从字面定位。
  # 环境变量优先级高于 .cargo/config.toml，所以只能在这里用 cmake -E env 覆盖。
  set(WGPU_PROBE_TARGET_DIR "${WGPU_PROBE_DIR}/target")

  add_custom_command(
    OUTPUT "${WGPU_PROBE_DLL}"
    COMMAND ${CMAKE_COMMAND} -E env
            "CARGO_TARGET_DIR=${WGPU_PROBE_TARGET_DIR}"
            "${CARGO_EXECUTABLE}" build --release --manifest-path "${WGPU_PROBE_MANIFEST}"
    DEPENDS "${WGPU_PROBE_LIB_SRC}" "${WGPU_PROBE_MANIFEST}"
    COMMENT "构建 Rust wgpu 探针 (wgpu_probe.dll)"
    VERBATIM
  )
  add_custom_target(wgpu_probe_target DEPENDS "${WGPU_PROBE_DLL}")
  add_dependencies(${BINARY_NAME} wgpu_probe_target)

  add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${WGPU_PROBE_DLL}" "$<TARGET_FILE_DIR:${BINARY_NAME}>"
    COMMENT "拷贝 wgpu_probe.dll 到输出目录"
  )
else()
  # 不中断构建：窗口照常起来，wgpu 那条路径会显示为不可用。
  message(WARNING "找不到 cargo，跳过 wgpu 探针；运行时 wgpu 路径将不可用")
endif()

# ─────────────────────────────────────────────────────────────────────────────
# DXC（dxcompiler.dll / dxil.dll）
#
# wgpu 的 DX12 后端走 WGSL → naga → HLSL → DXC → DXIL，
# 需要这两个 DLL 在进程可搜索的路径里。它们随 Windows SDK 分发但不在 PATH，
# 所以必须显式拷到 exe 旁边，否则创建设备/编译着色器会直接失败。
# ─────────────────────────────────────────────────────────────────────────────
file(GLOB DXC_CANDIDATES "C:/Program Files (x86)/Windows Kits/10/bin/*/x64/dxcompiler.dll")
if(DXC_CANDIDATES)
  list(SORT DXC_CANDIDATES)
  list(GET DXC_CANDIDATES -1 DXC_DLL)
  get_filename_component(DXC_BIN_DIR "${DXC_DLL}" DIRECTORY)
  message(STATUS "DXC: 从 ${DXC_BIN_DIR} 拷贝 dxcompiler.dll / dxil.dll")
  add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${DXC_BIN_DIR}/dxcompiler.dll"
            "${DXC_BIN_DIR}/dxil.dll"
            "$<TARGET_FILE_DIR:${BINARY_NAME}>"
    COMMENT "拷贝 DXC 供 wgpu 编译 WGSL"
  )
else()
  message(WARNING "找不到 dxcompiler.dll（Windows SDK），wgpu 可能无法编译着色器")
endif()
