#!/usr/bin/env bash
# 把最近一次 macOS 构建的 .app 增量同步到 /Applications。
#
# 动机：build/ 与 rust/target 会被 flutter clean / 手动清理，放在里面的 app 会一起没掉。
# /Applications 里的副本是完整 bundle（windcore.framework 等已嵌入），可独立双击运行；
# flutter run 仍然从 build/macos/Build/Products/<Config>/ 启动，两者互不影响。
#
# 用法: bash script/sync_macos_app.sh [Profile|Release] [目标 .app 路径]
#   Profile 对应 task dev，Release 对应 task b / task r。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-Profile}"
DEST="${2:-/Applications/Rossi Profile.app}"
SRC_DIR="${ROOT}/build/macos/Build/Products/${CONFIG}"

# 构建失败（例如 SwiftPM 解析挂了）时 Xcode 可能只留下空壳 .app。
# 挑第一个结构完整的产物，别让残骸把 /Applications 里能用的副本覆盖掉。
SRC=""
while IFS= read -r candidate; do
  if [[ -d "${candidate}/Contents/Frameworks/App.framework" && -d "${candidate}/Contents/MacOS" ]]; then
    SRC="${candidate}"
    break
  fi
done < <(find "${SRC_DIR}" -maxdepth 1 -name '*.app' -type d 2>/dev/null || true)

if [[ -z "${SRC}" ]]; then
  echo "⚠️  ${CONFIG} 产物不存在或不完整（${SRC_DIR}），跳过同步" >&2
  exit 0
fi

echo "同步 ${SRC} → ${DEST}"
# -a 保留可执行文件里内嵌的 ad-hoc 签名与 _CodeSignature，副本可直接启动；
# --checksum 避免「同尺寸同秒」的改动被 rsync 跳过；--delete 让副本不残留旧 framework。
rsync -a --checksum --delete "${SRC}/" "${DEST}/"
xattr -cr "${DEST}" 2>/dev/null || true # 清 quarantine，避免首次打开被 Gatekeeper 拦
touch "${DEST}"                         # 让 LaunchServices 注意到 bundle 变了
echo "✅ 已更新 ${DEST} ($(du -sh "${DEST}" | cut -f1))"
