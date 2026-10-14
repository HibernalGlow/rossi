#!/usr/bin/env python3
"""门禁：任何往队列里塞任务的入口，都必须先过那一道闸门。

objective 的第四条写着「不要为下载选择页单独再写一套排除已下载章节的逻辑」——
判据只此一份。这种约定编译器和测试都看不见：入口调 `startDownloadTasks(tasks)`
能编得过、跑起来也没错，直到某天两个入口对「这章下过没」给出不同答案。
所以这里按**函数**查：每个 `startDownloadTasks(X)` 调用点，X 的声明必须落在
闸门产出的类型上 —— 要么本函数里就调 `planDownloadEnqueue`，要么那个变量的声明
带 `DownloadEnqueuePlan` 类型或由 `plan…(...)` 那类返回计划函数赋值。
只查「文件里提没提闸门」是不够的：入口完全可以把没走过的列表直接递进去。

用法：
    python3 script/check_download_gate.py            # 检查，违例则退出 1
    python3 script/check_download_gate.py --root DIR # 换一棵树（阳性对照用）
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

SUBMIT = re.compile(r"\bstartDownloadTasks\s*\(")
GATE = "planDownloadEnqueue"
# 顶层 / 成员函数签名：缩进 0~6，行首到第一个左括号之间是返回类型与函数名。
FUNC = re.compile(r"^(?P<indent>[ ]{0,6})(?:[\w<>,?\s.]+\s+)?(?P<name>\w+)\s*\(")
# 控制流的圆括号长得和签名一样，认下来就把函数起点定歪了（实测栽在 `if (` 上）。
NOT_A_FUNCTION = {
    "if",
    "for",
    "while",
    "switch",
    "case",
    "catch",
    "return",
    "else",
    "do",
    "try",
    "finally",
    "assert",
    "await",
    "yield",
    "new",
}
# 定义/声明本身，不是调用点。
DEFINITION = re.compile(r"^\s*(?:Future<[^>]*>\s*)?startDownloadTasks\s*\(")


PLAN_ARG = re.compile(r"\bstartDownloadTasks\s*\(\s*(?P<var>[A-Za-z_]\w*)\.tasks\s*\)")
PLAN_SOURCE = re.compile(r"\bplan[A-Z][A-Za-z]*\s*\(|\bDownloadEnqueuePlan\b")


def violations_for(path: Path, text: str) -> list[str]:
    lines = text.splitlines()
    out: list[str] = []
    for index, line in enumerate(lines):
        if not SUBMIT.search(line) or DEFINITION.match(line):
            continue
        # 只看一件事：递进去的那个列表是从哪来的。
        # （曾经还加过一条「上面 25 行内出现过闸门名」的就近判据，实测被
        #  「只把 startDownloadTasks(plan.tasks) 换回 startDownloadTasks(tasks)」
        #  这种改法直接绕过 —— 闸门调用还在原地，但没人再读它的结果。删了。）
        match = PLAN_ARG.search(line)
        if match:
            identifier = match.group("var")
            declared = [
                prior
                for prior in lines[:index]
                if re.search(
                    rf"^\s*(?:final|var|const)\s+(?:[\w<>?,\s]+\s+)?{re.escape(identifier)}\s*=",
                    prior,
                )
            ]
            if declared and PLAN_SOURCE.search(declared[-1]):
                continue
        out.append(
            f"{path}:{index + 1}: {line.strip()} "
            "（递进去的不是闸门产出的计划：那个变量的声明里找不到 plan…()/DownloadEnqueuePlan）"
        )
    return out


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--root",
        default=None,
        help="仓库根目录（默认取脚本所在目录的上一级）",
    )
    args = parser.parse_args()

    root = Path(args.root) if args.root else Path(__file__).resolve().parent.parent
    lib = root / "lib"
    if not lib.is_dir():
        print(f"FAIL: 找不到 {lib}", file=sys.stderr)
        return 2

    files = [
        path
        for path in sorted(lib.rglob("*.dart"))
        if not (path.name.endswith(".g.dart") or path.name.endswith(".freezed.dart"))
    ]
    found: list[str] = []
    sites = 0
    for path in files:
        text = path.read_text(encoding="utf-8")
        sites += sum(
            1
            for line in text.splitlines()
            if SUBMIT.search(line) and not DEFINITION.match(line)
        )
        found.extend(violations_for(path, text))

    if found:
        print(f"FAIL: {len(found)} 处入队调用绕过了闸门（扫描 {len(files)} 个文件）")
        for item in found:
            print("  " + item)
        return 1

    print(
        f"PASS: {sites} 处 startDownloadTasks 调用点递的都是闸门产出的计划"
        f"（扫描 {len(files)} 个文件）"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
