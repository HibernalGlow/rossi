#!/bin/bash
set -euo pipefail

# Flutter's native-assets hook builds windcore only. This separate library must
# be rebuilt and embedded by Xcode before the application is signed.
project_root="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${HOME}/.cargo/bin:/opt/homebrew/bin:${PATH}"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-${project_root}/rust/target}"
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
