#!/bin/bash
# 本机编 Android APK（只出 arm64）。
#
#   script/build_apk_local.sh release   # 默认；AOT release 包，借用本机 debug keystore 签名
#   script/build_apk_local.sh debug     # debug 包（JIT，会卡；只在要断点/热重载时用）
#
# 为什么 release 需要这么多铺垫（每条都在本机撞过一次，不是预防性代码）：
#  1. **签名**：`android/key.properties` 在本仓是 git-crypt 密文，本机没装 git-crypt，
#     AGP 于是直接报 `SigningConfig "release" is missing required property "storeFile"`。
#     这里不去动那两个被 `filter=git-crypt` 声明的路径，而是往 `~/.gradle/init.d/` 放一个
#     **只对 <仓库根> 前缀生效**的 init 脚本，把 release 签名指到 `~/.android/debug.keystore`；
#     脚本退出时（含失败）删掉它。产物因此是「debug 私钥签的 release 包」：能装能跑 AOT，
#     但不能覆盖升级正式签名的同名应用，也不能对外分发。
#  2. **integration_test**：release 下 Flutter 不把 dev 依赖插件编进去（PluginHandler 按 n 位过滤），
#     但 Dart 侧生成的 GeneratedPluginRegistrant.java 照样注册它 ⇒ javac 报
#     「程序包 dev.flutter.plugins.integration_test 不存在」。这里临时从 pubspec 摘掉那两行，
#     `pub get` 后构建，退出时按快照还原；期间若 pubspec 被别人改过则**拒绝覆盖**并提示人工处理。
#  3. **dav1d 交叉库**：`image` 的 avif-native 要 pkg-config 找到安卓版 dav1d，
#     缺失时先跑 third_party/build_dav1d_android.sh 生成 third_party/android_sysroot/<triple>。
#  4. **Gradle 的代理**：Gradle 不读 shell 的 https_proxy，只认 JVM 系统属性；
#     直连 repo.maven.apache.org 时握手会被掐。用 ROSSI_GRADLE_PROXY 覆盖，默认走本机 7890。
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-release}"
TRIPLE=aarch64-linux-android
SNAP_DIR="$REPO/.dart_tool/apk-local-build"
INIT_SCRIPT="$HOME/.gradle/init.d/rossi-local-release-signing.gradle"

cd "$REPO"
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

case "$MODE" in
  release | debug) ;;
  *)
    echo "用法: $0 [release|debug]" >&2
    exit 2
    ;;
esac

if [ ! -f third_party/android_build_env.sh ]; then
  echo "缺少 third_party/android_build_env.sh（安卓交叉环境）" >&2
  exit 1
fi
# shellcheck disable=SC1091
source third_party/android_build_env.sh
# android_build_env.sh 里的路径是按某台机器的仓库位置写死的，这里按实际仓库根纠正。
export PKG_CONFIG_LIBDIR="$REPO/third_party/android_sysroot/$TRIPLE/lib/pkgconfig"
export PKG_CONFIG_PATH="$PKG_CONFIG_LIBDIR"

if [ ! -d "$PKG_CONFIG_LIBDIR" ]; then
  echo "== 没有安卓版 dav1d，先跑 third_party/build_dav1d_android.sh =="
  bash third_party/build_dav1d_android.sh || exit 1
fi

: "${ROSSI_GRADLE_PROXY:=${https_proxy:-${HTTPS_PROXY:-http://127.0.0.1:7890}}}"
if [ -n "$ROSSI_GRADLE_PROXY" ]; then
  case "$ROSSI_GRADLE_PROXY" in
    http://*) hostport="${ROSSI_GRADLE_PROXY#http://}" ;;
    *) hostport="$ROSSI_GRADLE_PROXY" ;;
  esac
  host="${hostport%%:*}"
  port="${hostport##*:}"
  # 注意别把 nonProxyHosts 写进来：值里的 `|` 会被 android/gradlew 的 eval 当管道，
  # 现场报错是 `line 157: 127.0.0.1: command not found`。
  export GRADLE_OPTS="-Dhttp.proxyHost=$host -Dhttp.proxyPort=$port -Dhttps.proxyHost=$host -Dhttps.proxyPort=$port${GRADLE_OPTS:+ $GRADLE_OPTS}"
  echo "[apk] Gradle 走代理 $host:$port"
fi

restore() {
  local rc=$?
  if [ "$MODE" = release ]; then
    rm -f "$INIT_SCRIPT"
    if [ -f "$SNAP_DIR/pubspec.yaml" ]; then
      local expect now
      expect=$(cat "$SNAP_DIR/pubspec.sha" 2>/dev/null || echo "?")
      now=$(git hash-object pubspec.yaml 2>/dev/null || echo "?")
      if [ "$now" = "$expect" ]; then
        cp "$SNAP_DIR/pubspec.yaml" pubspec.yaml
        cp "$SNAP_DIR/pubspec.lock" pubspec.lock
        echo "[apk] pubspec.yaml / pubspec.lock 已按快照还原"
      else
        echo "[apk] ⚠️ pubspec.yaml 在本次构建期间被别人改过，未覆盖。" >&2
        echo "     我的版本在 $SNAP_DIR/pubspec.yaml，请人工合并。" >&2
      fi
    fi
  fi
  exit $rc
}

if [ "$MODE" = debug ]; then
  exec dart ./script/build_apk.dart debug
fi

mkdir -p "$SNAP_DIR"
cp pubspec.yaml pubspec.lock "$SNAP_DIR/"
python3 - <<'PY'
p = 'pubspec.yaml'
s = open(p, encoding='utf-8').read()
old = "  integration_test:\n    sdk: flutter\n"
if old not in s:
    raise SystemExit("pubspec.yaml 的 dev_dependencies 里没有 integration_test，锚点失效，请更新本脚本")
open(p, 'w', encoding='utf-8').write(s.replace(old, '', 1))
print("[apk] 临时摘掉 integration_test（构建后还原）")
PY
git hash-object pubspec.yaml > "$SNAP_DIR/pubspec.sha"

mkdir -p "$(dirname "$INIT_SCRIPT")"
cat > "$INIT_SCRIPT" <<EOF
// 由 script/build_apk_local.sh 生成，构建结束即删。
// 只对 $REPO 下的工程生效：把 release 的签名指到本机 debug keystore。
def repo = '$REPO'
allprojects { p ->
  // Flutter 的 Gradle 根是 <repo>/android，不是仓库根，所以按 projectDir 前缀判。
  if (!p.projectDir.absolutePath.startsWith(repo)) return
  p.afterEvaluate {
    def ext = p.extensions.findByName('android')
    if (ext == null) return
    def cfg = ext.signingConfigs.findByName('release')
    if (cfg == null) { println "[rossi-local-signing] \${p.path}: 没有 release signingConfig"; return }
    cfg.storeFile = new File(System.getProperty('user.home'), '.android/debug.keystore')
    cfg.storePassword = 'android'
    cfg.keyAlias = 'androiddebugkey'
    cfg.keyPassword = 'android'
    println "[rossi-local-signing] \${p.path}: release 签名 → ~/.android/debug.keystore"
  }
}
EOF
trap restore EXIT

flutter pub get >/dev/null || exit 1
flutter build apk --release \
  --target-platform=android-arm64 \
  --dart-define=sentry_dsn="${SENTRY_DSN:-}" \
  --split-debug-info=build/symbols/apk-release-local
rc=$?
echo "APK_BUILD_RC=$rc"
[ "$rc" -eq 0 ] || exit "$rc"

APK=build/app/outputs/flutter-apk/app-release.apk
[ -f "$APK" ] || { echo "构建报成功但没有 $APK" >&2; exit 1; }
# 判据打在产物上：release 包必须有 AOT 的 libapp.so，且 Rust 库要在 arm64 目录里。
# 先把清单读进变量再用 case 匹配：`unzip -l | grep -q` 在 pipefail 下会因为 grep 提前退出
# 让 unzip 吃 SIGPIPE，管道整体报非零 —— 命中了也会被当成「缺文件」（踩过一次）。
LISTING=$(unzip -l "$APK")
case "$LISTING" in
  *lib/arm64-v8a/libapp.so*) ;;
  *) echo "$APK 里没有 libapp.so —— 这不是 AOT 产物" >&2; exit 1 ;;
esac
case "$LISTING" in
  *lib/arm64-v8a/libwindcore.so*) ;;
  *) echo "$APK 里没有 arm64 的 libwindcore.so" >&2; exit 1 ;;
esac
ls -l "$APK"
shasum -a 256 "$APK"
BT=$(ls -d "${ANDROID_HOME:-$HOME/Library/Android/sdk}"/build-tools/* 2>/dev/null | tail -1)
if [ -n "$BT" ] && [ -x "$BT/apksigner" ]; then
  "$BT/apksigner" verify --print-certs "$APK" 2>&1 | sed -n '1,3p'
fi
echo "✅ 产物：$REPO/$APK"
