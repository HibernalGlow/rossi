#!/usr/bin/env bash
# Phase 0 vendor spike 第 2 项：Cargo `[patch.crates-io]` 会不会跨 workspace 传递？
#
# 背景（ADR-0007）：mImageViewer 在自己的 workspace 根用 `[patch.crates-io]` 把三个 egui
# 换成 `vendor/` 下的本地副本。Rossi 打算用 **path 依赖** 复用它的源码（不把它挂进自己的
# workspace）。于是必须回答：那份 `[patch]` 在我们这边还算数吗？不算数的话症状是什么？
#
# 三个子实验（都用 cfg-if 当假想的 egui，因为它零依赖、编译秒级）：
#   基线  在 external/ 自己内部构建      -> patch 应当生效（本地实现被用）
#   案例1 external 有 patch，host 没有   -> 父 workspace 能不能蹭到？
#   案例2 external 有 patch，host 也写一份同样的 patch -> 能用，但谁在维护这份 patch？
#   案例3 external 直接 path 依赖本地实现，host 又要 crates.io 的同名同版本 -> Cargo 报什么？
#
# 用法（注意：**不要**写裸 `bash run.sh`）
#
# 本机 PATH 里的 `bash` 会解析到 `C:\Windows\System32\bash.exe`，那是 **WSL 的入口**，
# 会被沙箱的安全策略拦掉（报 PROGRAM BLOCKED BY SECURITY POLICY / wsl.exe）。
# 两种正确姿势：
#   1) 用 PortableGit 的 bash 绝对路径：
#      "C:/Users/30902/.workbuddy/binaries/PortableGit/versions/1.2.0/bin/bash.exe" poc/cargo-patch-scope/run.sh
#   2) 在当前 shell 里 source（此时 $0 不是脚本名，所以下面用绝对路径定位）：
#      . poc/cargo-patch-scope/run.sh

set -u
BASE="D:/1VSCODE/Projects/rossi/poc/cargo-patch-scope"
GEN="$BASE/gen"
LOG="$BASE/results.txt"

rm -rf "$GEN"
mkdir -p "$GEN"

w() { mkdir -p "$(dirname "$1")"; cat > "$1"; }

# ---------- 假想的「外部仓库」：自成 workspace root，内部有 patch ----------
w "$GEN/external/Cargo.toml" <<'EOF'
[workspace]
members = ["core"]
resolver = "2"

# 模拟 mImageViewer 的 [patch.crates-io]：把 egui 换成仓库内的本地副本
[patch.crates-io]
cfg-if = { path = "cfg-if-local" }
EOF

w "$GEN/external/cfg-if-local/Cargo.toml" <<'EOF'
[package]
name = "cfg-if"
version = "1.0.0"
edition = "2021"
EOF

w "$GEN/external/cfg-if-local/src/lib.rs" <<'EOF'
// 假冒 crates.io 的 cfg-if 1.0.0：多一个哨兵常量，用来分辨到底用的是哪一份
pub const SOURCE_MARKER: &str = "local-copy-in-external-repo";
EOF

w "$GEN/external/core/Cargo.toml" <<'EOF'
[package]
name = "vendored-core"
version = "0.1.0"
edition = "2021"

# 注意：这里依赖的是 crates.io 的 cfg-if，补丁由上层 workspace 的 [patch] 提供
[dependencies]
cfg-if = "1"
EOF

w "$GEN/external/core/src/lib.rs" <<'EOF'
pub fn marker() -> &'static str {
    cfg_if::SOURCE_MARKER
}
EOF

# ---------- 外部仓库的第二种形态：不用 patch，直接 path 依赖 ----------
w "$GEN/external-direct/Cargo.toml" <<'EOF'
[workspace]
members = ["core"]
resolver = "2"
EOF

w "$GEN/external-direct/core/Cargo.toml" <<'EOF'
[package]
name = "vendored-core-direct"
version = "0.1.0"
edition = "2021"

[dependencies]
# 直接 path 指向本地副本（不走 [patch]）
cfg-if = { path = "../cfg-if-local" }
EOF

w "$GEN/external-direct/core/src/lib.rs" <<'EOF'
pub fn marker() -> &'static str {
    cfg_if::SOURCE_MARKER
}
EOF
cp -r "$GEN/external/cfg-if-local" "$GEN/external-direct/cfg-if-local"

# ---------- 父 workspace ----------
w "$GEN/host-nopatch/Cargo.toml" <<'EOF'
[workspace]
members = ["adapter"]
resolver = "2"
EOF

w "$GEN/host-nopatch/adapter/Cargo.toml" <<'EOF'
[package]
name = "adapter"
version = "0.1.0"
edition = "2021"

[dependencies]
vendored-core = { path = "../../external/core" }
EOF

w "$GEN/host-nopatch/adapter/src/lib.rs" <<'EOF'
pub fn who() -> &'static str {
    vendored_core::marker()
}
EOF

w "$GEN/host-patch/Cargo.toml" <<'EOF'
[workspace]
members = ["adapter"]
resolver = "2"

# 父 workspace 自己再写一遍同样的 patch
[patch.crates-io]
cfg-if = { path = "../external/cfg-if-local" }
EOF

w "$GEN/host-patch/adapter/Cargo.toml" <<'EOF'
[package]
name = "adapter"
version = "0.1.0"
edition = "2021"

[dependencies]
vendored-core = { path = "../../external/core" }
EOF

w "$GEN/host-patch/adapter/src/lib.rs" <<'EOF'
pub fn who() -> &'static str {
    vendored_core::marker()
}
EOF

w "$GEN/host-dup/Cargo.toml" <<'EOF'
[workspace]
members = ["adapter"]
resolver = "2"
EOF

w "$GEN/host-dup/adapter/Cargo.toml" <<'EOF'
[package]
name = "adapter"
version = "0.1.0"
edition = "2021"

[dependencies]
vendored-core-direct = { path = "../../external-direct/core" }
# 同一个 crate 名 + 同一个版本，但来自 crates.io
cfg-if = "1"
EOF

w "$GEN/host-dup/adapter/src/lib.rs" <<'EOF'
pub fn both() -> (&'static str, &'static str) {
    (vendored_core_direct::marker(), cfg_if::SOURCE_MARKER)
}
EOF

w "$GEN/host-dup-samever/Cargo.toml" <<'EOF'
[workspace]
members = ["adapter"]
resolver = "2"
EOF

w "$GEN/host-dup-samever/adapter/Cargo.toml" <<'EOF'
[package]
name = "adapter"
version = "0.1.0"
edition = "2021"

[dependencies]
vendored-core-direct = { path = "../../external-direct/core" }
# 这一行是本次新增的关键：**锁到与本地副本完全相同的版本**（1.0.0），
# 用来验证 ADR-0007 里「同名 crate 有两个来源 → 构建错误」这句话到底成不成立
cfg-if = "=1.0.0"
EOF

w "$GEN/host-dup-samever/adapter/src/lib.rs" <<'EOF'
pub fn both() -> (&'static str, &'static str) {
    (vendored_core_direct::marker(), cfg_if::SOURCE_MARKER)
}
EOF

# ---------- 探测哪个 cfg-if 真的进了图 ----------
probe() {
  local dir="$1" label="$2"
  echo "### $label  ($dir)"
  local meta
  meta=$(cd "$dir" && cargo metadata --format-version 1 --quiet 2>&1)
  if [ $? -ne 0 ]; then
    echo "    cargo metadata 失败："
    echo "$meta" | grep -E "^error|^Caused by|error\[" | sed 's/^/    /' | head -6
    return
  fi
  printf '%s' "$meta" | C:/Users/30902/.workbuddy/binaries/python/versions/3.13.12/python.exe -c '
import json,sys
m=json.load(sys.stdin)
for p in m["packages"]:
    if p["name"]=="cfg-if":
        src=p.get("source") or "PATH(本地副本)"
        print("    cfg-if", p["version"], "->", src)
'
  echo "    cargo build:"
  (cd "$dir" && cargo build --quiet 2>&1 | grep -E "error|warning: unused" | head -4 | sed 's/^/      /') || true
  echo "    (build 无 error 输出 = 编译通过)"
  echo
}

{
  echo "=== Cargo [patch.crates-io] 跨 workspace 传递性实验 ==="
  echo "日期: $(date +%F)   cargo: $(cargo --version)"
  echo
  probe "$GEN/external" "基线：patch 就在这个 workspace 根里"
  probe "$GEN/host-nopatch" "案例 1：外部有 patch，父 workspace 没有"
  probe "$GEN/host-patch" "案例 2：父 workspace 自己补一份同样的 patch"
  probe "$GEN/host-dup" "案例 3：外部直接 path 依赖，父 workspace 又依赖 crates.io 同名（版本不同）"
  probe "$GEN/host-dup-samever" "案例 4：同上，但父锁到与本地副本完全相同的版本（=1.0.0）"
} 2>&1 | tee "$LOG"

echo "结果已写入 results.txt"
