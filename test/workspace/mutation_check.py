#!/usr/bin/env python3
"""变异验证：把被测代码逐个改坏，确认判据真的会红。

判据全绿只说明「没发现错」，不说明「错了一定被发现」。这里对每条不变量造一个
变异体，要求对应判据失败；没失败的就是**形同虚设**的判据 —— 除非它被明确列进
`redundant=True`（那说明它是冗余兜底，删掉行为也不变，另有理由留在代码里）。

跑法（**必须解掉 `HTTP_PROXY`**，沙箱代理会劫持 `flutter_tester` 的 WebSocket 握手，
症状是 `Unable to connect to flutter_tester process: Invalid WebSocket upgrade request`）：

    python3 test/workspace/mutation_check.py

踩过的坑：`dart run` / `flutter test` 都会按文件 mtime 缓存编译产物，改完立刻跑可能
**跑到上一个变异体**（症状是「还原后基线」莫名其妙失败）。所以每次写盘后都等一下，
并把 FAIL 行整段抓出来，而不是只看最后一行。
"""
import os
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

# 写盘到跑之间的间隔：躲开编译缓存的 mtime 粒度
SETTLE_SECONDS = 1.6

# 沙箱代理会让 flutter_tester 起不来；跑判据一律不带它。
CLEAN_ENV = {
    k: v
    for k, v in os.environ.items()
    if k.lower() not in ("http_proxy", "https_proxy", "all_proxy")
}

SUITES = [
    {
        "name": "lane_dispatch（纯 Dart：推入落点记账）",
        "cmd": ["dart", "run", "test/workspace/lane_dispatch_check.dart"],
        "baseline_marker": "checks passed",
        "mutations": [
            (
                "M1 noteInteraction 不再要求「已登记」→ 隐藏面板抢走落点",
                "lib/workspace/router/workspace_lane_dispatch.dart",
                "    if (_live[host.laneId] == host) {\n      _lastInteracted = host;\n    }",
                "    _lastInteracted = host;",
                False,
            ),
            (
                "M2 resolveTarget 不与「仍活着」求交",
                "lib/workspace/router/workspace_lane_dispatch.dart",
                "    final host = _lastInteracted;\n    if (host == null) return null;\n"
                "    return _live[host.laneId] == host ? host : null;",
                "    return _lastInteracted;",
                True,
            ),
            (
                "M3 registerHost 不再作废旧记录 → 切回来旧记录复活",
                "lib/workspace/router/workspace_lane_dispatch.dart",
                "    if (_lastInteracted != null &&\n"
                "        _lastInteracted!.laneId == host.laneId &&\n"
                "        _lastInteracted != host) {\n"
                "      _lastInteracted = null;\n"
                "    }",
                "",
                False,
            ),
            (
                "M4 unregisterHost 无条件清泳道 → 迟到的 dispose 抹掉新面板",
                "lib/workspace/router/workspace_lane_dispatch.dart",
                "    if (_live[host.laneId] == host) {\n      _live.remove(host.laneId);\n    }",
                "    _live.remove(host.laneId);",
                False,
            ),
            (
                "M5 主机身份只比 panelId（不比泳道）",
                "lib/workspace/router/workspace_lane_dispatch.dart",
                "      other is WorkspaceLaneHost &&\n      other.laneId == laneId &&\n"
                "      other.panelId == panelId;",
                "      other is WorkspaceLaneHost && other.panelId == panelId;",
                False,
            ),
            (
                "M6 hashCode 只取 panelId",
                "lib/workspace/router/workspace_lane_dispatch.dart",
                "  int get hashCode => Object.hash(laneId, panelId);",
                "  int get hashCode => panelId.hashCode;",
                False,
            ),
            (
                "M7 debugKey 不含泳道",
                "lib/workspace/router/workspace_lane_dispatch.dart",
                "  String get debugKey => '$laneId/$panelId';",
                "  String get debugKey => panelId;",
                False,
            ),
        ],
    },
    {
        "name": "route_guard（widget test：页面开在哪儿）",
        "cmd": ["flutter", "test", "test/workspace/route_guard_test.dart"],
        "baseline_marker": "All tests passed",
        "mutations": [
            (
                "M8 守卫永不接管（工作台在场也放行全屏）",
                "lib/workspace/router/workspace_route_guard.dart",
                "    if (!bridge.isAttached) {",
                "    if (true) {",
                False,
            ),
            (
                "M9 pushInLane 谎报接管（返回 true 但没推）",
                "lib/workspace/router/workspace_navigation_bridge.dart",
                "    if (host == null) return false;",
                "    if (host == null) return true;",
                False,
            ),
            (
                "M10 attachLaneHost 不登记活主机",
                "lib/workspace/router/workspace_navigation_bridge.dart",
                "    _laneNavigators[host] = navigatorKey;\n"
                "    WorkspaceLaneDispatch.instance.registerHost(host);",
                "    _laneNavigators[host] = navigatorKey;",
                False,
            ),
            (
                "M11 指针交互不上报",
                "lib/workspace/widgets/containers/embedded_upstream_page.dart",
                "      onPointerDown: (_) =>\n"
                "          WorkspaceNavigationBridge.instance.noteLaneInteraction(widget.host),",
                "      onPointerDown: (_) {},",
                False,
            ),
            (
                "M12 容器无视 isVisible（隐藏面板也登记自己）",
                "lib/workspace/widgets/containers/embedded_upstream_page.dart",
                "    if (widget.isVisible) _attach();",
                "    _attach();",
                False,
            ),
        ],
    },
    {
        "name": "desktop_shell（widget test：窗口全屏时标题栏让位）",
        "cmd": ["flutter", "test", "test/desktop/desktop_shell_frame_test.dart"],
        "baseline_marker": "All tests passed",
        "mutations": [
            (
                "M13 服务不再听「窗口进了全屏」→ 就是用户报的那个 bug",
                "lib/service/reader/reader_desktop_fullscreen_service.dart",
                "  void onWindowEnterFullScreen() => _setFullscreen(true);",
                "  void onWindowEnterFullScreen() {}",
                False,
            ),
            (
                "M14 服务不再听「窗口退了全屏」→ 退出后标题栏回不来",
                "lib/service/reader/reader_desktop_fullscreen_service.dart",
                "  void onWindowLeaveFullScreen() => _setFullscreen(false);",
                "  void onWindowLeaveFullScreen() {}",
                False,
            ),
            (
                "M15 全屏时标题栏照旧建（`if` 恒真）",
                "lib/widgets/desktop/desktop_shell_frame.dart",
                "            if (!isFullscreen) const CustomTitleBar(),",
                "            if (true) const CustomTitleBar(),",
                False,
            ),
            (
                "M16 假让位：标题栏不建了，但那 40px 还占着",
                "lib/widgets/desktop/desktop_shell_frame.dart",
                "            if (!isFullscreen) const CustomTitleBar(),",
                "            if (isFullscreen) const SizedBox(height: 40),\n"
                "            if (!isFullscreen) const CustomTitleBar(),",
                False,
            ),
        ],
    },
]

REDUNDANT_NOTE = (
    "M2 是**冗余兜底**：registerHost 的作废 + unregisterHost 的清理已经保证了\n"
    "     「_lastInteracted 必是活主机」，所以单删求交这一行，行为与判据都不变\n"
    "     （M3 同理：两条互为兜底，单删任一条都测不出）。\n"
    "     留着它的价值是「将来改坏那两个入口时，最坏退化成不接管（= 全屏）」，\n"
    "     并在被测代码里就写着这句话。"
)

# 「红了」有强弱之分：**编译不过**也算红，但那证明不了判据抓得住这个错 ——
# 变异体要是把代码写成语法错，那是在验编译器，不是在验判据。这里把失败类型
# 分出来，只有「判据失败」才算证据。
COMPILE_MARKERS = ("error:", "Failed to load", "Compilation failed", "compilation failed")
ASSERT_MARKERS = ("[E]", "Expected:", "Test failed", "FAIL:")


def failure_kind(out):
    """→ (kind, 一行摘要)。kind ∈ {test, compile, other}。"""
    lines = out.splitlines()
    assert_lines = [ln.strip() for ln in lines if any(m in ln for m in ASSERT_MARKERS)]
    compile_lines = [ln.strip() for ln in lines if any(m in ln for m in COMPILE_MARKERS)]
    if assert_lines:
        # 把「哪条断言红的」也带出来：只说「判据失败」看不出抓的是不是这条不变量。
        expected = next((ln.strip() for ln in lines if ln.strip().startswith("Expected:")), "")
        actual = next((ln.strip() for ln in lines if ln.strip().startswith("Actual:")), "")
        why = " ".join(x for x in (expected, actual) if x)
        return "test", (f"{assert_lines[0]} ｜ {why}" if why else assert_lines[0])
    if compile_lines:
        return "compile", compile_lines[0]
    return "other", ""


def run(cmd):
    p = subprocess.run(
        cmd, cwd=ROOT, capture_output=True, text=True, env=CLEAN_ENV
    )
    out = p.stdout + p.stderr
    fails = [ln.strip() for ln in out.splitlines() if "FAIL:" in ln]
    return p.returncode, out, fails


def main():
    wanted = sys.argv[1] if len(sys.argv) > 1 else None
    suites = [s for s in SUITES if wanted is None or wanted in s["name"]]
    if not suites:
        print(f"没有匹配的判据组：{wanted}")
        sys.exit(1)
    all_rows = []

    for suite in suites:
        print(f"\n=== {suite['name']} ===")
        originals = {}
        rows = []
        try:
            for name, rel, find, repl, redundant in suite["mutations"]:
                # **每个变异体都从干净基线出发**：先把这套判据碰过的所有文件还原，
                # 再单独写这一个变异。
                #
                # 不这么做的话，跨文件的判据组会留下上一个变异体（比如「服务不听
                # 全屏事件」还留在 fileA 里），于是后一个变异体**因为别人的错**变红
                # —— 那是假红，和假绿一样有毒：它让「捕获」这个结论失去意义。
                for r, s in originals.items():
                    (ROOT / r).write_text(s)

                path = ROOT / rel
                if rel not in originals:
                    originals[rel] = path.read_text()
                src = originals[rel]
                if find not in src:
                    rows.append((name, "PATTERN-NOT-FOUND", "", redundant))
                    continue
                path.write_text(src.replace(find, repl, 1))
                time.sleep(SETTLE_SECONDS)
                code, out, _ = run(suite["cmd"])
                if code == 0:
                    rows.append(
                        (
                            name,
                            "SURVIVED(已备案)" if redundant else "*** SURVIVED ***",
                            "冗余兜底，见下" if redundant else "判据形同虚设",
                            redundant,
                        )
                    )
                    continue
                kind, detail = failure_kind(out)
                if kind == "test":
                    rows.append((name, "CAUGHT(判据失败)", detail, redundant))
                elif kind == "compile":
                    rows.append((name, "*** 只触发编译错 ***", detail, redundant))
                else:
                    rows.append((name, "*** 失败但原因不明 ***", detail or "非零退出", redundant))

            # 还原后复跑，确认被测代码与判据本身仍然全绿
            for rel, src in originals.items():
                (ROOT / rel).write_text(src)
            time.sleep(SETTLE_SECONDS)
            code, out, fails = run(suite["cmd"])
            marker = suite["baseline_marker"]
            ok_line = next((ln.strip() for ln in out.splitlines() if marker in ln), "")
            rows.append(
                (
                    "还原后基线",
                    "OK" if code == 0 else "*** BROKEN ***",
                    ok_line or (fails[0] if fails else ""),
                    False,
                )
            )
        finally:
            for rel, src in originals.items():
                (ROOT / rel).write_text(src)

        width = max(len(r[0]) for r in rows)
        for name, verdict, detail, _ in rows:
            print(f"{name.ljust(width)}  {verdict}")
            if detail:
                print(f'{"".ljust(width)}    └─ {detail}')
        all_rows += rows

    print("\nM2 为什么允许存活：")
    print(f"     {REDUNDANT_NOTE}")

    bad = [
        r
        for r in all_rows
        if "SURVIVED *" in r[1] or "BROKEN" in r[1] or "NOT-FOUND" in r[1] or "***" in r[1]
    ]
    caught = len([r for r in all_rows if r[1].startswith("CAUGHT")])
    print()
    if bad:
        print(f"变异验证未通过：{len(bad)} 项")
        sys.exit(1)
    print(f"变异验证通过：{caught} 个变异体被捕获（都是判据失败，不是编译错），1 个已备案的冗余兜底")


main()
