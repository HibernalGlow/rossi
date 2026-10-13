#!/usr/bin/env python3
"""门禁：`Switch.adaptive` / `SwitchListTile.adaptive` 必须显式给选中时的轨道色。

为什么需要这一把尺（判据本身在 `material_ui-1.6.0/lib/src/switch.dart:948`）：

    effectiveActiveTrackColor =
        widget.trackColor                  // 1
     ?? _widgetTrackColor                  // 2  ← activeTrackColor 落在这里
     ?? (applyCupertinoTheme ? cupertinoPrimaryColor
                             : switchTheme.trackColor)   // 3
     ?? _widgetThumbColor?.withAlpha(0x80) // 4
     ?? defaults.trackColor                // 5  ← Cupertino 分支 = systemGreen

在 macOS / iOS 上 `Switch.adaptive` 走的是第 5 步的 `_SwitchDefaultsCupertino`，
底色是 **`CupertinoColors.systemGreen`**；而第 3 步在 `applyCupertinoTheme` 为
false 时读 `switchTheme`，第 5 步又排在它后面 —— 也就是说**全局 `SwitchThemeData`
救不了它**，只有调用点自己给 `activeTrackColor`（或 `trackColor`）才会吃到主题色。

漏给参数不会有任何编译错误或 lint 报告，只会画成一颗绿开关 ——
所以这里用源码扫描兜住，并给非零退出码。

注意 `SwitchListTile(...)`（不带 `.adaptive`）**不在**本尺范围内：
它在 material_ui 里走 `_SwitchListTileType.material` → `_SwitchDefaultsM3`
→ `colorScheme.primary`，本来就跟着主题。

用法：
    python3 script/check_adaptive_switch_tint.py              # 扫 lib/
    python3 script/check_adaptive_switch_tint.py --self-test  # 验这把尺本身看得见违规
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "lib"
SKIP_SUFFIXES = (".g.dart", ".freezed.dart", ".gr.dart")
SITE_PAT = re.compile(r"\b(?:Switch|SwitchListTile)\.adaptive\s*\(")
TINT_PAT = re.compile(r"\b(?:activeTrackColor|trackColor)\s*:")


def strip_comments(src: str) -> str:
    """剥掉 `//` 与 `/* */` 注释，但**不碰字符串字面量里的 `//`**。

    两头都要防：
    - 不剥注释 → 文档注释里提到的 `Switch.adaptive(` 会被当成调用点（假阳性）；
    - 乱剥 → `'https://…'` 这类串会把行尾的真代码吃掉（假阴性，比报错更坏）。
    """
    out: list[str] = []
    i, n = 0, len(src)
    while i < n:
        ch = src[i]
        # --- 字符串（含三引号与 raw 前缀）---
        if ch in "\"'":
            raw = i > 0 and src[i - 1] == "r"
            quote = ch
            triple = src[i : i + 3] * (3 if src[i : i + 3] == quote * 3 else 1)
            if src[i : i + 3] == quote * 3:
                end = src.find(quote * 3, i + 3)
                end = n if end == -1 else end + 3
            else:
                j = i + 1
                while j < n:
                    if src[j] == "\\" and not raw:
                        j += 2
                        continue
                    if src[j] == quote:
                        break
                    if src[j] == "\n":  # 单引号串不跨行
                        break
                    j += 1
                end = j + 1
            out.append(src[i:end])
            i = end
            continue
        # --- 行注释 ---
        if ch == "/" and src.startswith("//", i):
            nl = src.find("\n", i)
            i = n if nl == -1 else nl
            continue
        # --- 块注释（Dart 允许嵌套）---
        if ch == "/" and src.startswith("/*", i):
            depth = 0
            j = i
            while j < n:
                if src.startswith("/*", j):
                    depth += 1
                    j += 2
                elif src.startswith("*/", j):
                    depth -= 1
                    j += 2
                    if depth == 0:
                        break
                else:
                    j += 1
            out.append("".join("\n" if c == "\n" else " " for c in src[i:j]))
            i = j
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def call_body(src: str, open_paren: int) -> str:
    """从 `(` 起按括号配平取到调用结束（含字符串里的括号已被 strip 保留，够用）。"""
    depth = 0
    for j in range(open_paren, len(src)):
        if src[j] == "(":
            depth += 1
        elif src[j] == ")":
            depth -= 1
            if depth == 0:
                return src[open_paren : j + 1]
    return src[open_paren:]


def scan(src: str) -> list[int]:
    """返回违规调用点的**行号**（1 基，按传入 src 的行计）。"""
    bad = []
    for m in SITE_PAT.finditer(src):
        body = call_body(src, m.end() - 1)
        if not TINT_PAT.search(body):
            bad.append(src[: m.start()].count("\n") + 1)
    return bad


def _self_test() -> int:
    """阳性对照：尺必须**报得出**违规，也**不能**把注释/URL 里的东西当调用点。"""
    cases = [
        (
            "违规：没给轨道色",
            "Widget a() => const Switch.adaptive(value: true, onChanged: null);\n",
            [1],
        ),
        (
            "合规：给了 activeTrackColor",
            "Widget b() => const Switch.adaptive(\n"
            "  value: true,\n"
            "  activeTrackColor: Color(0xFFFF0000),\n"
            "  onChanged: null,\n"
            ");\n",
            [],
        ),
        (
            "合规：给了 trackColor（WidgetStateProperty 版）",
            "Widget c() => const SwitchListTile.adaptive(\n"
            "  value: true,\n"
            "  trackColor: WidgetStatePropertyAll(Color(0xFF00FF00)),\n"
            "  onChanged: null,\n"
            ");\n",
            [],
        ),
        (
            "假阳性对照：文档注释里提到的 Switch.adaptive( 不算调用点",
            "/// 见 [Switch.adaptive] 与 `Switch.adaptive(` 的说明。\n"
            "Widget d() => const SizedBox();\n",
            [],
        ),
        (
            "假阴性对照：串里的 // 不能吃掉头上的真调用点",
            "final url = 'https://example.com/x';\n"
            "Widget e() => const Switch.adaptive(value: true, onChanged: null);\n",
            [2],
        ),
        (
            "多站点：只报漏给色的那一处",
            "Widget f() => Row(children: [\n"
            "  const Switch.adaptive(value: true, activeTrackColor: null),\n"
            "  const Switch.adaptive(value: false, onChanged: null),\n"
            "]);\n",
            [3],
        ),
    ]
    failed = 0
    for name, src, want in cases:
        got = scan(strip_comments(src))
        ok = got == want
        print(f"  {'ok  ' if ok else 'FAIL'}  {name}: 期望 {want} 实得 {got}")
        failed += 0 if ok else 1
    print(f"self-test: {len(cases) - failed}/{len(cases)} 通过")
    return 1 if failed else 0


def main(argv: list[str]) -> int:
    if "--self-test" in argv:
        return _self_test()
    if not ROOT.is_dir():
        print(f"找不到 {ROOT}", file=sys.stderr)
        return 2
    found: list[str] = []
    for path in sorted(ROOT.rglob("*.dart")):
        if path.name.endswith(SKIP_SUFFIXES):
            continue
        rel = path.relative_to(ROOT.parent).as_posix()
        src = strip_comments(path.read_text(encoding="utf-8"))
        for line in scan(src):
            found.append(
                f"{rel}:{line}: Switch.adaptive 缺 activeTrackColor"
                "（macOS/iOS 上会画成 Cupertino 绿，不吃主题色）"
            )
    if found:
        print(f"发现 {len(found)} 处没跟主题色的自适应开关：")
        for line in found:
            print(f"  {line}")
        print("修法：加 `activeTrackColor: colorScheme.primary`（全局 SwitchThemeData 无效）。")
        return 1
    print("所有 Switch.adaptive / SwitchListTile.adaptive 调用点都显式给了轨道色。")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
