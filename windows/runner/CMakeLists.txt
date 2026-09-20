cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "gpu_present_bridge.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

apply_standard_settings(${BINARY_NAME})

# 本仓库源码注释使用中文；根 CMakeLists 已经全局加了 /utf-8，
# 这里只是把那条约束在 runner 上也写明，免得将来有人挪动全局设置时踩到
# （症状是注释收尾吞掉换行、之后整片语法雪崩，且 C4819 会被 /WX 升级成 error）。
target_compile_options(${BINARY_NAME} PRIVATE "/utf-8")

# GPU 呈现桥用到的 D3D12 / DXGI 类型与 COM 接口。
target_link_libraries(${BINARY_NAME} PRIVATE "d3d12.lib" "dxgi.lib")

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
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)

# ==============================================================================
# 🔍 托盘图标调试与复制脚本
# ==============================================================================

# 1. 定义源路径 (通常在 windows/runner/resources/app_icon.ico)
# CMAKE_CURRENT_SOURCE_DIR 指的是当前 CMakeLists.txt 所在的目录 (即 windows/runner)
set(TRAY_ICON_SRC "${CMAKE_CURRENT_SOURCE_DIR}/resources/app_icon.ico")

# 2. 定义目标路径 (即编译生成的 exe 旁边)
set(TRAY_ICON_DEST "${CMAKE_CURRENT_BINARY_DIR}/app_icon.ico")

# 3. 打印调试日志 (在编译输出中搜索 "[Rossi]" 关键词)
message(STATUS "-------------------------------------------------------")
message(STATUS ">>> [Rossi] 正在检查托盘图标...")
message(STATUS ">>> [Rossi] 源文件路径: ${TRAY_ICON_SRC}")
message(STATUS ">>> [Rossi] 目标路径:   ${TRAY_ICON_DEST}")

if(EXISTS "${TRAY_ICON_SRC}")
    message(STATUS ">>> [Rossi] ✅ 成功找到图标文件！正在复制...")
    # 执行复制 (COPYONLY 表示如果目标已存在且较新，则不复制)
    configure_file("${TRAY_ICON_SRC}" "${TRAY_ICON_DEST}" COPYONLY)
else()
    # 如果找不到，打印错误警告，并列出 resources 目录下有什么
    message(WARNING ">>> [Rossi] ❌ 错误：在源路径找不到图标文件！")
    file(GLOB FILES_IN_RES "${CMAKE_CURRENT_SOURCE_DIR}/resources/*")
    message(STATUS ">>> [Rossi] resources 目录下的文件列表: ${FILES_IN_RES}")
endif()

message(STATUS "-------------------------------------------------------")
# ==============================================================================

# ==============================================================================
# GPU 上屏路径：Rust 侧呈现器（rust/gpu_present → rossi_gpu_present.dll）
#
# 与 Gate A 的 PoC（poc/texture-bridge）同一条路子：编成 cdylib，运行时由
# gpu_present_bridge.cpp 用 LoadLibrary 加载，**不走 import lib** —— 免得把
# CMake 的链接顺序和 cargo 的构建顺序耦在一起，也免得非 Windows 平台要处理
# 一个根本不存在的产物。
# ==============================================================================
set(GPU_PRESENT_DIR "${CMAKE_SOURCE_DIR}/../rust/gpu_present")
set(GPU_PRESENT_MANIFEST "${GPU_PRESENT_DIR}/Cargo.toml")
set(GPU_PRESENT_DLL "${GPU_PRESENT_DIR}/target/release/rossi_gpu_present.dll")

find_program(CARGO_EXECUTABLE cargo)
if(NOT CARGO_EXECUTABLE AND DEFINED ENV{CARGO_HOME})
  set(CARGO_EXECUTABLE "$ENV{CARGO_HOME}/bin/cargo.exe")
endif()
if(NOT CARGO_EXECUTABLE AND DEFINED ENV{USERPROFILE})
  set(CARGO_EXECUTABLE "$ENV{USERPROFILE}/.cargo/bin/cargo.exe")
endif()

if(CARGO_EXECUTABLE AND EXISTS "${CARGO_EXECUTABLE}")
  message(STATUS "GPU 呈现器: 使用 cargo = ${CARGO_EXECUTABLE}")

  # 必须显式覆盖 CARGO_TARGET_DIR。
  #
  # 构建环境脚本为了让主项目产物留在 D 盘，设了 CARGO_TARGET_DIR=<repo>/rust/target。
  # 那个变量会被这里继承，于是本 DLL 的产物跑进主项目的 target 目录，
  # 与 Flutter 的 native-assets 构建（用自己的 --target-dir）互相看见对方的中间产物。
  # 症状是编译期蹦出 "only metadata stub found for `rlib` dependency `core`"
  # 这类看起来像工具链坏掉的错误，极难从字面定位。环境变量优先级高于
  # .cargo/config.toml，所以只能在这里用 cmake -E env 覆盖。
  set(GPU_PRESENT_TARGET_DIR "${GPU_PRESENT_DIR}/target")
  set(GPU_PRESENT_ENV "CARGO_TARGET_DIR=${GPU_PRESENT_TARGET_DIR}")

  # cargo 的 [env] 段是按**当前工作目录**向上找 .cargo/config.toml 的，
  # 而这里的 cwd 是构建目录 —— 够不到仓库根的那份。dav1d（AVIF 解码）
  # 要经 pkg-config 找，缺了它 local_core 的 build script 会直接失败，
  # 所以显式把环境递进去。
  if(DEFINED ENV{PKG_CONFIG_PATH})
    # ⚠ 必须转义分号再交出去。
    #
    # 本机的 PKG_CONFIG_PATH 是**分号分隔的多条路径**（vcpkg 的 release + debug）。
    # 直接写 `list(APPEND ... "PKG_CONFIG_PATH=$ENV{...}")` 会被 CMake 当列表处理，
    # 在分号处拆成**两个**元素，生成出来的命令行就成了：
    #
    #   cmake -E env PKG_CONFIG_PATH=<第一条> <第二条> <cargo ...>
    #
    # 而 `cmake -E env` 把**第一个不含 `=` 的参数当成要执行的命令** —— 于是它去
    # "执行"一个目录，立刻失败。症状是 MSB8066「自定义生成已退出，代码为 1」，
    # 而且日志里**没有 cargo 的任何输出**：cargo 压根没被启动。
    # 这个指纹很好认：**自定义命令失败 + 被调用工具自己的输出一个字都没有**。
    string(REPLACE ";" "\\;" GPU_PRESENT_PKG_CONFIG_PATH "$ENV{PKG_CONFIG_PATH}")
    list(APPEND GPU_PRESENT_ENV "PKG_CONFIG_PATH=${GPU_PRESENT_PKG_CONFIG_PATH}")
    unset(GPU_PRESENT_PKG_CONFIG_PATH)
  endif()
  if(DEFINED ENV{VCPKG_ROOT})
    list(APPEND GPU_PRESENT_ENV "VCPKG_ROOT=$ENV{VCPKG_ROOT}")
  endif()

  # 呈现器解出来的每一个像素都来自 local_core（归档 / 解码），它的源码变了
  # 就必须重编 DLL。少了这条依赖，改完 Rust 再构建会**静默沿用旧的 dll** ——
  # 现象是"改了代码却没变化"，排查时会先去怀疑 cargo 没重编，方向全错。
  # 连 Cargo.lock 一起盯着：依赖升级同样会让产物本身失效。
  file(GLOB_RECURSE GPU_PRESENT_CORE_SOURCES
       "${CMAKE_SOURCE_DIR}/../rust/local_core/src/*.rs")
  file(GLOB_RECURSE GPU_PRESENT_OWN_SOURCES
       "${GPU_PRESENT_DIR}/src/*.rs")
  set(GPU_PRESENT_SOURCES
      ${GPU_PRESENT_CORE_SOURCES}
      ${GPU_PRESENT_OWN_SOURCES}
      "${CMAKE_SOURCE_DIR}/../rust/Cargo.lock")
  unset(GPU_PRESENT_CORE_SOURCES)
  unset(GPU_PRESENT_OWN_SOURCES)

  add_custom_command(
    OUTPUT "${GPU_PRESENT_DLL}"
    COMMAND ${CMAKE_COMMAND} -E env ${GPU_PRESENT_ENV}
            "${CARGO_EXECUTABLE}" build --release
            --manifest-path "${GPU_PRESENT_MANIFEST}"
            --package rossi_gpu_present
    DEPENDS
      ${GPU_PRESENT_SOURCES}
      "${GPU_PRESENT_MANIFEST}"
    COMMENT "构建 Rust GPU 呈现器 (rossi_gpu_present.dll)"
    # cargo 的配置发现是**从 cwd 向上**找 `.cargo/config.toml`，而本步默认的 cwd 是
    # build/ 里的构建目录 —— 够不到仓库根那一份（里面是本机 dav1d 的 pkg-config 路径，
    # 见 docs/windows-build/README.md §7.7）。把 cwd 定在仓库根，这一步就与
    # "在仓库里手敲 cargo build" 完全等价，不再依赖上面那串环境变量透传。
    WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}/.."
    VERBATIM
  )
  add_custom_target(gpu_present_target DEPENDS "${GPU_PRESENT_DLL}")
  add_dependencies(${BINARY_NAME} gpu_present_target)

  add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${GPU_PRESENT_DLL}" "$<TARGET_FILE_DIR:${BINARY_NAME}>"
    COMMENT "拷贝 rossi_gpu_present.dll 到输出目录"
  )
else()
  # 不中断构建：窗口照常起来，GPU 上屏路径显示为不可用（Dart 侧会给出原因）。
  message(WARNING
    "找不到 cargo，跳过 GPU 呈现器；运行时 GPU 上屏路径将不可用")
endif()

# ─────────────────────────────────────────────────────────────────────────────
# DXC（dxcompiler.dll / dxil.dll）
#
# wgpu 的 DX12 后端把 WGSL 经 naga 转成 HLSL，再交给 DXC 编出 DXIL。
# 这两个 DLL 随 Windows SDK 分发但**不在 PATH 上**，所以必须拷到 exe 旁边，
# 否则创建着色器模块会直接失败 —— 表现是"GPU 路径初始化失败"而不是编译错误。
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
    COMMENT "拷贝 DXC 供 naga 编译 WGSL"
  )
else()
  message(WARNING
    "找不到 dxcompiler.dll（Windows SDK），GPU 上屏路径会在创建着色器时失败")
endif()