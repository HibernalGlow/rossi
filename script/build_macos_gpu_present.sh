#!/bin/bash
set -euo pipefail

# Flutter's native-assets hook builds windcore only. This separate library must
# be rebuilt and embedded by Xcode before the application is signed.
project_root="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${HOME}/.cargo/bin:/opt/homebrew/bin:${PATH}"
# 必须用自己的 target 目录，不能沿用 `${project_root}/rust/target`。
#
# 本脚本是 Xcode 的 Run Script phase，xcodebuild 会把 build settings 倒进环境
# （`MACOSX_DEPLOYMENT_TARGET=12.0`、`DEVELOPER_DIR=…`）。而 `unrar_sys` / `libwebp-sys` /
# `libsqlite3-sys` 的 cc-rs build script 声明了
# `cargo:rerun-if-env-changed=MACOSX_DEPLOYMENT_TARGET`，与终端那条
# `cargo build -p windcore --release`（没有这个变量）共用同一个 target 目录时，
# 两边每次交替都要重跑 build script 并重编整条 C 子树及其下游（实测约 5 分钟）。
# Windows 侧的同一个库在 CMake 里也是这么隔离的，见 `windows/runner/CMakeLists.txt`。
#
# 这里**不**回退到继承来的 `CARGO_TARGET_DIR`：那个变量优先级高于 `.cargo/config.toml`，
# 一旦被外部构建脚本设成 `rust/target`，隔离就白做了。要改位置用专门的
# `ROSSI_GPU_PRESENT_TARGET_DIR`。产物目录落在 `rust/.gitignore` 的 `/*/target/` 里。
export CARGO_TARGET_DIR="${ROSSI_GPU_PRESENT_TARGET_DIR:-${project_root}/rust/gpu_present/target}"
export PKG_CONFIG_PATH="${PKG_CONFIG_PATH:-/opt/homebrew/lib/pkgconfig:/usr/local/lib/pkgconfig}"
host_target="$(rustc -vV | sed -n 's/^host: //p')"
libraries=()

for arch in ${ARCHS:?Xcode ARCHS is required}; do
    case "$arch" in
        arm64) target=aarch64-apple-darwin ;;
        x86_64) target=x86_64-apple-darwin ;;
        *) echo "Unsupported macOS architecture: $arch" >&2; exit 1 ;;
    esac
    cargo_args=(build --manifest-path "${project_root}/rust/Cargo.toml" --locked --release --package rossi_gpu_present --lib)
    library_dir="${CARGO_TARGET_DIR}/release"
    if [[ "$target" != "$host_target" ]]; then
        cargo_args+=(--target "$target")
        library_dir="${CARGO_TARGET_DIR}/${target}/release"
    fi
    cargo "${cargo_args[@]}"
    libraries+=("${library_dir}/librossi_gpu_present.dylib")
done

destination="${TARGET_BUILD_DIR:?}/${FRAMEWORKS_FOLDER_PATH:?}/librossi_gpu_present.dylib"
mkdir -p "$(dirname "$destination")"
if [[ ${#libraries[@]} -eq 1 ]]; then
    cp "${libraries[0]}" "$destination"
else
    lipo -create "${libraries[@]}" -output "$destination"
fi
install_name_tool -id '@rpath/librossi_gpu_present.dylib' "$destination"
if [[ "${CODE_SIGNING_ALLOWED:-YES}" != NO ]]; then
    codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" --timestamp=none "$destination"
fi
echo "Embedded GPU presenter: $destination"
