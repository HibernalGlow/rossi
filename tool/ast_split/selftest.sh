#!/usr/bin/env bash
# ast_split 的自测。两类断言：
#   正向 —— 合法搬家必须 PASS；
#   反向 —— 篡改、重排、以及工具该拦下的危险搬家必须判负。
# 反向断言是重点：一个不会失败的审计等于没有审计。
# 用法：bash tool/ast_split/selftest.sh
set -uo pipefail
cd "$(dirname "$0")"
BIN="$PWD/bin/ast_split.dart"
AS() { dart "$BIN" "$@"; }
T=$(mktemp -d)
fails=0
ok()  { echo "  ✓ $1"; }
bad() { echo "  ✗ $1"; fails=$((fails + 1)); }
expect_pass() { if AS "$@" >/dev/null 2>&1; then ok "$*"; else bad "$* 应当 PASS"; fi; }
expect_fail() { if AS "$@" >/dev/null 2>&1; then bad "$* 应当 FAIL"; else ok "$* 正确判负"; fi; }

# ---------------------------------------------------------------- 1) 顶层 -> part
mkdir -p "$T/a/parts"
cat > "$T/a/root.dart" <<'EOF'
import 'dart:async';

class Root {
  void go() {}
}

class _Keep { int k = 0; }

class _Move1 { int m = 1; }

class _Move2 { int m = 2; }

void _helper() {}
EOF
AS snapshot --file "$T/a/root.dart" --out "$T/a/s.json" >/dev/null
AS extract --file "$T/a/root.dart" --to "$T/a/parts/root_moved_part.dart" \
  --decls _Move1,_Move2,_helper --note 搬家测试 >/dev/null
echo "[1] 顶层声明 -> part"
expect_pass audit --snapshot "$T/a/s.json" --file "$T/a/root.dart"
grep -q "^part 'parts/root_moved_part.dart';" "$T/a/root.dart" \
  && ok "库根已注册 part" || bad "库根缺少 part 指令"

# ------------------------------------------------- 2) 目标文件自身是 part（三层）
mkdir -p "$T/b/parts"
printf "import 'dart:async';\n\npart 'mid.dart';\n\nclass Root { void go() {} }\n" \
  > "$T/b/root.dart"
printf "part of 'root.dart';\n\nclass _A { int a = 1; }\n\nclass _B { int b = 2; }\n\nvoid _c() {}\n" \
  > "$T/b/mid.dart"
AS snapshot --file "$T/b/mid.dart" --out "$T/b/s.json" >/dev/null
AS extract --file "$T/b/mid.dart" --to "$T/b/parts/mid_x_part.dart" \
  --decls _B,_c >/dev/null
echo "[2] 目标自身是 part 时，新 part 必须挂到库根"
if grep -q "part of '../root.dart';" "$T/b/parts/mid_x_part.dart"; then
  ok "part of 指向库根 root.dart"
else
  bad "part of 指错：$(head -1 "$T/b/parts/mid_x_part.dart")"
fi
grep -q "^part 'parts/mid_x_part.dart';" "$T/b/root.dart" \
  && ok "库根已注册" || bad "库根未注册新 part"
expect_pass audit --snapshot "$T/b/s.json" --file "$T/b/mid.dart"

# ------------------------------------- 3) 私有宿主类的私有成员 -> extension
mkdir -p "$T/c/parts"
cat > "$T/c/host.dart" <<'EOF'
class _Counter {
  static int pad = 0;

  int n = 0;

  void _bump() {
    n++;
  }

  void _bumpTwice() {
    _bump();
    _bump();
    pad++;
  }

  int get value => n;

  void _reset() {
    n = 0;
  }

  void _usesSuper() {
    super.toString();
  }

  @override
  String toString() => 'c';
}
EOF
AS snapshot --file "$T/c/host.dart" --out "$T/c/s.json" >/dev/null
echo "[3] 私有宿主类的私有成员"
if AS extract-members --file "$T/c/host.dart" --class _Counter \
  --to "$T/c/parts/host_ops_part.dart" --extension CounterOps \
  --members _reset >/dev/null 2>&1; then
  ok "干净的私有成员可搬"
else
  bad "合法搬家被拒"
fi
grep -q "^extension CounterOps on _Counter {" "$T/c/parts/host_ops_part.dart" \
  && ok "生成了 extension 包装" || bad "缺少 extension 包装"
expect_pass audit --snapshot "$T/c/s.json" --file "$T/c/host.dart"

# ---------------------------------------------------- 4) 工具必须拦下的危险搬家
echo "[4] 危险搬家必须被拦下"
expect_fail extract-members --file "$T/c/host.dart" --class _Counter \
  --to "$T/c/parts/no1.dart" --extension X1 --members _bumpTwice
echo "      ↑ _bumpTwice 引用了宿主静态成员 pad（extension 里裸用是编译错误）"
expect_fail extract-members --file "$T/c/host.dart" --class _Counter \
  --to "$T/c/parts/no2.dart" --extension X2 --members _usesSuper
expect_fail extract-members --file "$T/c/host.dart" --class _Counter \
  --to "$T/c/parts/no3.dart" --extension X3 --members toString
expect_fail extract-members --file "$T/c/host.dart" --class _Counter \
  --to "$T/c/parts/no4.dart" --extension X4 --members n
expect_fail extract-members --file "$T/c/host.dart" --class _Counter \
  --to "$T/c/parts/no5.dart" --extension X5 --members nosuchmember
mkdir -p "$T/p"
printf 'class Pub {\n  void go() {\n    print(1);\n  }\n}\n' > "$T/p/pub.dart"
expect_fail extract-members --file "$T/p/pub.dart" --class Pub \
  --to "$T/p/x.dart" --extension Xp --members go
echo "      ↑ 公有宿主类的公有成员：跨库 show 与多态都会坏"
if [ -f "$T/c/parts/no4.dart" ]; then bad "被拒的搬家不应写出文件"; else ok "拒绝时不写出文件"; fi

# ---------------------------------------------------- 5) 篡改与重排必须判负
echo "[5] 审计对篡改/重排要敏感"
cp "$T/c/parts/host_ops_part.dart" "$T/c/ops.bak"
perl -pi -e 's/    n = 0;/    n = 7;/' "$T/c/parts/host_ops_part.dart"
expect_fail audit --snapshot "$T/c/s.json" --file "$T/c/host.dart"
cp "$T/c/ops.bak" "$T/c/parts/host_ops_part.dart"

rm -rf "$T/e" && mkdir -p "$T/e"
printf 'class _C {\n  void a() {\n    print(1);\n  }\n\n  void b() {\n    print(2);\n  }\n}\n' \
  > "$T/e/c.dart"
AS snapshot --file "$T/e/c.dart" --out "$T/e/s.json" >/dev/null
printf 'class _C {\n  void b() {\n    print(2);\n  }\n\n  void a() {\n    print(1);\n  }\n}\n' \
  > "$T/e/c.dart"
expect_fail audit --snapshot "$T/e/s.json" --file "$T/e/c.dart"
expect_pass audit --snapshot "$T/c/s.json" --file "$T/c/host.dart"

# ---------------------------------------------- 6) 语言无关文本审计（Rust 形态）
echo "[6] text-snapshot / text-audit"
mkdir -p "$T/f"
python3 - "$T/f" <<'PY'
import sys, os
d = sys.argv[1]
body = "\n".join("pub fn f%d() {\n    let x = %d;\n    do_it(x);\n}\n" % (i, i)
                 for i in range(60))
open(os.path.join(d, "mod.rs"), "w").write(body)
PY
AS text-snapshot --files "$T/f/mod.rs" --out "$T/f/s.json" >/dev/null
python3 - "$T/f" <<'PY'
import sys, os
d = sys.argv[1]
p = os.path.join(d, "mod.rs")
L = open(p).read().split("\n")
os.makedirs(os.path.join(d, "moved"), exist_ok=True)
open(os.path.join(d, "moved", "half.rs"), "w").write(
    "use super::*;\n\n" + "\n".join(L[:30]))
open(p, "w").write("mod half;\n\n" + "\n".join(L[30:]))
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
