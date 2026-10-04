#!/usr/bin/env bash
# 把 Flutter hook 已经编好的 release 产物搬到「开发期加载点」，
# 取代 `cd rust && cargo build -p windcore --release` 那条重复编译。
#
# 为什么要它：native-assets 的 hook 构建恒定带 `--target <三元组>`，而终端里的
# cargo 不带 —— 这不只是路径不同，**cargo 的 unit 元数据哈希也不同**（实测同一批
# 依赖在 `--target` 两边的同名同哈希产物为 0）。所以「终端 release 树」和「hook release
# 树」就算共用 target 目录也不会互相复用，只会各存一份全量缓存（本仓实测前者 5.1 GB）。
# 又因为 hook 子进程的环境与终端不同（CC/AR/PKG_CONFIG_PATH 等），两边共用同一个目录
# 会让 cc-rs 的 rerun-if-env-changed 每次交替都重编整条 C 子树 —— 同一个坑的记录见
# script/build_macos_gpu_present.sh 的注释。唯一不破的解法是：**只编一次，产物搬过去。**
#
# 加载点是谁在消费：`lib/src/rust/frb_generated.dart` 的 `ioDirectory`（`flutter test`
# 从仓库根启动时按当前工作目录解析），以及 macos/Runner/GpuPresentBridgeMac.swift 的
# 开发期候选路径。内容哈希门禁仍然有效：搬来的产物若与当前生成物不同源，
# RustLib.init() 会直接抛 "Content hash ... different from Rust side"，不会静默测旧代码。
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
host_target="$(rustc -vV | sed -n 's/^host: //p')"

case "$(uname -s)" in
    Darwin) lib_name="libwindcore.dylib" ;;
    Linux) lib_name="libwindcore.so" ;;
    *MSYS* | *MINGW* | *CYGWIN* | Windows*) lib_name="windcore.dll" ;;
    *) echo "不支持的平台：$(uname -s)" >&2
       exit 1 ;;
esac

# hook 的稳定目录布局：<rust>/target/native-assets/<三元组>/<profile>/，
# 不带三元组的那一份是历史布局与「宿主 unit」的落点，都留作候选。
sources=(
    "$project_root/rust/target/native-assets/$host_target/release/$lib_name"
    "$project_root/rust/target/native-assets/release/$lib_name"
)
destination_dir="$project_root/rust/target/release"
destination="$destination_dir/$lib_name"

source=""
for candidate in "${sources[@]}"; do
    if [[ -f "$candidate" ]]; then source="$candidate"; break; fi
done

if [[ -z "$source" ]]; then
    echo "没有可搬的 hook 产物。先跑一次 release 构建（flutter build macos --release）。" >&2
    echo "候选路径：${sources[*]}" >&2
    exit 1
fi

mkdir -p "$destination_dir"

if [[ -f "$destination" ]]; then
    # 目标更新 = 已经有一份比 hook 更近的产物（例如刚跑过终端 release 构建），
    # 拿旧的盖它是纯退化，必须拒。
    if [[ "$destination" -nt "$source" && "${1:-}" != "--force" ]]; then
        echo "跳过：$destination 比 $source 新，不覆盖（确实要覆盖加 --force）"
        exit 0
    fi
fi

cp -f "$source" "$destination"
echo "已搬：$source"
echo "  -> $destination"

# 源码比产物新 → 搬过去也大概率过不了哈希门禁，把话说明白，别让人对着黑屏猜。
newest_source="$(find "$project_root/rust/src" "$project_root/rust/local_core/src" \
    "$project_root/rust/ocr_core/src" -type f -name '*.rs' -newer "$destination" 2>/dev/null | head -1 || true)"
if [[ -n "$newest_source" ]]; then
    echo "注意：$newest_source 比这份产物新，过桥测试可能报 content hash 不一致；" \
        "要对它取信就得重跑一次 release 构建。" >&2
fi
