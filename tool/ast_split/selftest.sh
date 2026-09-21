#!/usr/bin/env bash
# ast_split 的自测：正向（干净搬家必须 PASS）+ 反向（篡改/重排必须 FAIL）。
# 用法：bash tool/ast_split/selftest.sh
set -uo pipefail
cd "$(dirname "$0")"
D='dart bin/ast_split.dart'
T=$(mktemp -d)
fails=0

ok()   { echo "  ✓ $1"; }
bad()  { echo "  ✗ $1"; fails=$((fails+1)); }

expect_pass() { $D "$@" >/dev/null 2>&1 && ok "$*" || bad "$* 应当 PASS"; }
expect_fail() { $D "$@" >/dev/null 2>&1 && bad "$* 应当 FAIL" || ok "$* 正确判负"; }

# ---------- 1) 独立库根上的 extract ----------
mkdir -p "$T/a/parts"
printf "import 'dart:async';\n\nclass Root {\n  void go() {}\n}\n\nclass _Keep { int k = 0; }\n\nclass _Move1 { int m = 1; }\n\nclass _Move2 { int m = 2; }\n\nvoid _helper() {}\n" > "$T/a/root.dart"
$D snapshot --file "$T/a/root.dart" --out "$T/a/s.json" >/dev/null
$D extract --file "$T/a/root.dart" --to "$T/a/parts/root_moved_part.dart" \
  --decls _Move1,_Move2,_helper >/dev/null
echo "[1] 顶层声明 -> part"
expect_pass audit --snapshot "$T/a/s.json" --file "$T/a/root.dart"
grep -q "^part 'parts/root_moved_part.dart';" "$T/a/root.dart" \
  && ok "库根已注册 part" || bad "库根缺少 part 指令"

# ---------- 2) 被拆文件本身就是 part ----------
mkdir -p "$T/b/parts"
printf "import 'dart:async';\n\npart 'tab.dart';\n\nclass Root { void go() {} }\n" > "$T/b/root.dart"
printf "part of 'root.dart';\n\nclass _Alpha { int a = 1; }\n\nclass _Beta { int b = 2; }\n\nvoid _gamma() {}\n" > "$T/b/tab.dart"
$D snapshot --file "$T/b/tab.dart" --out "$T/b/s.json" >/dev/null
$D extract --file "$T/b/tab.dart" --to "$T/b/parts/tab_bits_part.dart" \
  --decls _Beta,_gamma >/dev/null
echo "[2] part 文件里再拆 part"
expect_pass audit --snapshot "$T/b/s.json" --file "$T/b/tab.dart"
grep -q "^part 'parts/tab_bits_part.dart';" "$T/b/root.dart" \
  && ok "注册到了库根而不是 part" || bad "part 指令没写进库根"
grep -q "_Beta" "$T/b/tab.dart" && bad "宿主 part 没被摘除" || ok "宿主 part 已摘除"

# ---------- 3) extract-members -> extension ----------
mkdir -p "$T/c/parts"
cat > "$T/c/host.dart" <<'EOF'
class Counter {
  int n = 0;

  void bump() {
    n++;
  }

  void bumpTwice() {
    bump();
    bump();
  }

  int get value => n;

  void reset() {
    n = 0;
  }
}
EOF
$D snapshot --file "$T/c/host.dart" --out "$T/c/s.json" >/dev/null
$D extract-members --file "$T/c/host.dart" --class Counter \
  --to "$T/c/parts/host_ops_part.dart" --extension _CounterOps \
  --members bumpTwice,reset >/dev/null
echo "[3] 类成员 -> extension part"
expect_pass audit --snapshot "$T/c/s.json" --file "$T/c/host.dart"
grep -q "^extension _CounterOps on Counter {" "$T/c/parts/host_ops_part.dart" \
  && ok "生成了 extension 包装" || bad "缺少 extension 包装"

# ---------- 4) 护栏与反向用例 ----------
echo "[4] 护栏与篡改检测"
mkdir -p "$T/d"
cat > "$T/d/svc.dart" <<'EOF'
class Svc {
  final int k = 1;

  Svc();

  @override
  String toString() => 'svc';

  void tick() {
    k;
  }
}
EOF
$D extract-members --file "$T/d/svc.dart" --class Svc --to "$T/d/p.dart" \
  --extension _X --members toString >/dev/null 2>&1 \
  && bad "带 @override / 与基类同名的成员应被拦下" || ok "@override + 基类同名成员被拦下"
$D extract-members --file "$T/d/svc.dart" --class Svc --to "$T/d/p.dart" \
  --extension _X --members tick >/dev/null 2>&1 \
  && ok "普通方法可搬" || bad "普通方法不该被拦"
$D extract-members --file "$T/d/svc.dart" --class Svc --to "$T/d/p2.dart" \
  --extension _X --members nonexistent >/dev/null 2>&1 \
  && bad "空匹配不应写出文件" || ok "空匹配被拒，不写空 extension"

# 篡改已被搬走的一行 -> 必须判负
sed -i '' 's/    bump();$/    bump(); \/* tampered *\//' "$T/c/parts/host_ops_part.dart" 2>/dev/null || \
  perl -pi -e 's/^    bump\(\);$/    bump(); \/\/ tampered/' "$T/c/parts/host_ops_part.dart"
expect_fail audit --snapshot "$T/c/s.json" --file "$T/c/host.dart"

# 把类里两个成员交换位置（内容没变、顺序变了）-> 必须判负
mkdir -p "$T/e"
printf 'class C {\n  void a() {\n    print(1);\n  }\n\n  void b() {\n    print(2);\n  }\n}\n' > "$T/e/c.dart"
$D snapshot --file "$T/e/c.dart" --out "$T/e/s.json" >/dev/null
printf 'class C {\n  void b() {\n    print(2);\n  }\n\n  void a() {\n    print(1);\n  }\n}\n' > "$T/e/c.dart"
expect_fail audit --snapshot "$T/e/s.json" --file "$T/e/c.dart"

# ---------- 5) 语言无关文本审计（Rust 形态） ----------
echo "[5] text-snapshot / text-audit"
mkdir -p "$T/f"
python3 - "$T/f" <<'PY'
import sys, os
d = sys.argv[1]
body = "\n".join(f"pub fn f{i}() {{\n    let x = {i};\n    do_it(x);\n}}\n" for i in range(60))
open(os.path.join(d, "mod.rs"), "w").write(body)
PY
$D text-snapshot --files "$T/f/mod.rs" --out "$T/f/s.json" >/dev/null
python3 - "$T/f" <<'PY'
import sys, os
d = sys.argv[1]
L = open(os.path.join(d, "mod.rs")).read().split("\n")
moved = L[:30]
rest = L[30:]
os.makedirs(os.path.join(d, "moved"), exist_ok=True)
open(os.path.join(d, "moved", "half.rs"), "w").write("use super::*;\n\n" + "\n".join(moved))
open(os.path.join(d, "mod.rs"), "w").write("mod half;\n\n" + "\n".join(rest))
PY
expect_pass text-audit --snapshot "$T/f/s.json" --new "$T/f/moved/half.rs"
perl -pi -e 's/    let x = 0;/    let x = 999;/' "$T/f/moved/half.rs"
expect_fail text-audit --snapshot "$T/f/s.json" --new "$T/f/moved/half.rs"

rm -rf "$T"
echo
if [ "$fails" -eq 0 ]; then
  echo "SELFTEST PASS"
else
  echo "SELFTEST FAIL ($fails 项)"
  exit 1
fi
