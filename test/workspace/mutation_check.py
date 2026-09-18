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
    # ── 本轮（泳道运行时 / 插入位 / 持久化 / 驻留） ─────────────────────────
    #
    # 这几组盯的是**7 件事**：激活泳道、非激活泳道第一下点击被吃掉、悬停驻留、
    # 边缘驻留揭示、面板栏的浮动与换边停靠、跨侧拖动的精确插入位、一切持久化。
    # 其中三组是 widget 判据（跑 `flutter test`），一组是纯 Dart（跑 `dart run`）。
    #
    # 纯模型那三个判据文件（`lane_focus_check` / `panel_bar_check` /
    # `layout_snapshot_check`）**没有**单独列组：它们算的那些函数
    # （`panelBarFloatingOffset` / 快照 JSON 往返）在下面 B、C 两组里被
    # 真的走了一遍（镶嵌在 widget 与存盘往返里），再单独列一组是重复计分。
    {
        "name": "swimlane_runtime（widget test：激活 / 吃点击 / 驻留揭示）",
        "cmd": ["flutter", "test", "test/workspace/swimlane_runtime_test.dart"],
        "baseline_marker": "All tests passed",
        "mutations": [
            (
                "M17 AbsorbPointer 不再吸收 → 第一下点击落到内容上",
                "lib/workspace/widgets/swimlane/swimlane_workspace.dart",
                "      absorbing: !isActive,",
                "      absorbing: false,",
                False,
            ),
            (
                "M18 吸收范围包住整列（含栏头）→ 非激活泳道的栏头按钮第一下哑掉",
                "lib/workspace/widgets/swimlane/swimlane_workspace.dart",
                "        child: _buildLaneDragTarget(context, cubit, laneId, column),",
                "        child: AbsorbPointer(\n"
                "          absorbing: !isActive,\n"
                "          child: _buildLaneDragTarget(context, cubit, laneId, column),\n"
                "        ),",
                False,
            ),
            (
                "M19 栏头里的页签条重新参与摆放（撑满约束）→ 栏头溢出",
                "lib/workspace/widgets/swimlane/swimlane_column.dart",
                "            PanelTabStrip(side: panelSide!, showHandle: false),",
                "            PanelTabStrip(\n"
                "              side: panelSide!,\n"
                "              bounds: const PanelBarBounds(\n"
                "                left: 0,\n"
                "                top: 0,\n"
                "                width: 400,\n"
                "                height: 900,\n"
                "              ),\n"
                "              laneBounds: const PanelBarBounds(\n"
                "                left: 0,\n"
                "                top: 0,\n"
                "                width: 400,\n"
                "                height: 900,\n"
                "              ),\n"
                "              showHandle: false,\n"
                "            ),",
                False,
            ),
            (
                "M20 悬停聚焦对**所有**泳道生效（不只 Reader）",
                "lib/workspace/widgets/swimlane/swimlane_workspace.dart",
                "    if (laneId != LaneId.reader) return;",
                "    if (false) return;",
                False,
            ),
            (
                "M21 悬停聚焦忽略开关",
                "lib/workspace/widgets/swimlane/swimlane_workspace.dart",
                "    if (!state.interaction.hoverFocusEnabled) return;",
                "    if (false) return;",
                False,
            ),
            (
                "M22 认了这次边缘揭示却不移动条带",
                "lib/workspace/widgets/swimlane/swimlane_workspace.dart",
                "    if (revealSide != null) {\n"
                "      setState(() => _revealedLaneId = revealSide);\n"
                "      _applyOffset();\n"
                "    }",
                "    if (revealSide != null) {\n      setState(() {});\n    }",
                False,
            ),
            (
                "M23 揭示再也不收回（瞬态变常驻）",
                "lib/workspace/widgets/swimlane/swimlane_workspace.dart",
                "    if (_restoreDwell.takeDue(now) != null) {\n"
                "      setState(() => _revealedLaneId = null);\n"
                "      _applyOffset();\n"
                "    }",
                "    if (_restoreDwell.takeDue(now) != null) {\n      setState(() {});\n    }",
                False,
            ),
        ],
    },
    {
        "name": "workspace_panels（widget test：插入位 / 面板栏摆放）",
        "cmd": ["flutter", "test", "test/workspace/workspace_panels_test.dart"],
        "baseline_marker": "All tests passed",
        "mutations": [
            (
                "M24 跨侧拖入固定追加到末尾（本轮之前的写法）",
                "lib/workspace/widgets/panels/panel_tab_strip.dart",
                "      insertIndex: target,",
                "      insertIndex: siblings.length,",
                False,
            ),
            (
                "M25 不可移动的页签不做落点（于是掉回「追加」）",
                "lib/workspace/widgets/panels/panel_tab_strip.dart",
                "    if (!panel.canMove) return dropBefore;",
                "    if (!panel.canMove) return button;",
                False,
            ),
            (
                "M26 同序列换位不扣掉自己那一格",
                "lib/workspace/widgets/panels/panel_tab_strip.dart",
                "    final target = currentIndex >= 0 && index > currentIndex\n"
                "        ? index - 1\n"
                "        : index;",
                "    final target = index;",
                False,
            ),
            (
                "M27 悬浮位置改用 `Align` 语义（子节点左边缘在 p% 处）",
                "lib/workspace/widgets/panels/panel_bar_positioner.dart",
                "      offset = Offset(floating.left, floating.top);",
                "      offset = Offset(\n"
                "        bounds.width * layout.positionX / 100,\n"
                "        bounds.height * layout.positionY / 100,\n"
                "      );",
                False,
            ),
            (
                "M28 拖动期间不让实时位置优先",
                "lib/workspace/widgets/panels/panel_bar_positioner.dart",
                "    if (live != null) {",
                "    if (live != null && false) {",
                False,
            ),
        ],
    },
    {
        "name": "layout_persistence（widget test：去抖 / 重置 / 页面接线）",
        "cmd": ["flutter", "test", "test/workspace/layout_persistence_test.dart"],
        "baseline_marker": "All tests passed",
        "mutations": [
            (
                "M29 还原时撤旗不排到「那次 emit 投递」之后 → 启动无端写一次盘",
                "lib/workspace/breeze_workspace_page.dart",
                "      scheduleMicrotask(() => _restoring = false);",
                "      _restoring = false;",
                False,
            ),
            (
                "M30 「重置布局」只重置状态，不作废磁盘（重启又变回来）",
                "lib/workspace/breeze_workspace_page.dart",
                "    scheduleMicrotask(\n"
                "      () => unawaited(_persistence?.reset() ?? Future<void>.value()),\n"
                "    );",
                "    unawaited(_persistence?.reset() ?? Future<void>.value());",
                False,
            ),
            (
                "M31 去抖窗口归零（每帧都写盘）",
                "lib/workspace/service/workspace_layout_store.dart",
                "    _timer = Timer(debounce, flush);",
                "    _timer = Timer(Duration.zero, flush);",
                False,
            ),
            (
                "M32 flush 不判空（没有改动也写一次）",
                "lib/workspace/service/workspace_layout_store.dart",
                "    final snapshot = _pending;\n    if (snapshot == null) return;",
                "    final snapshot = _pending ?? WorkspaceLayoutSnapshot.defaults();",
                False,
            ),
        ],
    },
    {
        "name": "dwell（纯 Dart：驻留到点只触发一次 / 离开只取消自己 / 抑制）",
        "cmd": ["dart", "run", "test/workspace/dwell_check.dart"],
        "baseline_marker": "checks passed",
        "mutations": [
            (
                "M33 takeDue 取值后不清待发项 → 每帧都重复触发",
                "lib/workspace/model/workspace_dwell.dart",
                "    final id = _pendingId;\n    _pendingId = null;\n    return id;",
                "    return _pendingId;",
                False,
            ),
            (
                "M34 leave 无条件取消 → 把别人的计时也抹掉",
                "lib/workspace/model/workspace_dwell.dart",
                "    if (_pendingId == id) _pendingId = null;",
                "    _pendingId = null;",
                False,
            ),
            (
                "M35 抑制期间照旧触发",
                "lib/workspace/model/workspace_dwell.dart",
                "      !_suppressed && _pendingId != null && nowMs >= _deadlineMs;",
                "      _pendingId != null && nowMs >= _deadlineMs;",
                False,
            ),
            (
                "M36 换了目标不重新计时（在 A 攒的时间算给 B）",
                "lib/workspace/model/workspace_dwell.dart",
                "    if (_pendingId == id) return;\n    _pendingId = id;",
                "    if (_pendingId != null) return;\n    _pendingId = id;",
                False,
            ),
        ],
    },
    # ── 顶栏两种形态（桌面悬停揭示 / 触摸屏常驻） ───────────────────────────
    #
    # 这一组盯的是**触摸屏上的那个出口**：工作台是 `Navigator.push` 上来的整页、
    # 没有系统返回按钮，桌面端靠「悬停揭示 + Esc」出去，而这两条在触摸屏上
    # 一条都成立不了。M37 就是用户会报的那个症状本身。
    #
    # 「可见」与「吃不吃鼠标」是两个独立机制（`AnimatedOpacity` /
    # `IgnorePointer`），所以 M41 与 M42 分别打这两处 —— 只验一个的话
    # 另一个坏掉判据照样绿。
    {
        "name": "top_chrome（widget test：桌面揭示 / 触摸屏常驻）",
        "cmd": ["flutter", "test", "test/workspace/top_chrome_test.dart"],
        "baseline_marker": "All tests passed",
        "mutations": [
            (
                "M37 平台映射恒为揭示 → 触摸屏上没有出口（就是用户会报的那个）",
                "lib/workspace/widgets/chrome/workspace_top_chrome.dart",
                "      case TargetPlatform.android:\n"
                "      case TargetPlatform.iOS:\n"
                "      case TargetPlatform.fuchsia:\n"
                "        return WorkspaceTopChromeMode.persistent;",
                "      case TargetPlatform.android:\n"
                "      case TargetPlatform.iOS:\n"
                "      case TargetPlatform.fuchsia:\n"
                "        return WorkspaceTopChromeMode.reveal;",
                False,
            ),
            (
                "M38 常驻顶栏浮在内容上、不给内容让位 → 内容第一行永远看不见",
                "lib/workspace/breeze_workspace_page.dart",
                "                          ? Column(\n"
                "                              children: [\n"
                "                                WorkspaceTopChrome(\n"
                "                                  mode: chromeMode,\n"
                "                                  onExit: _exitWorkspace,\n"
                "                                  onResetLayout: _resetLayout,\n"
                "                                ),\n"
                "                                Expanded(\n"
                "                                  child: SafeArea(top: false, child: content),\n"
                "                                ),\n"
                "                              ],\n"
                "                            )",
                "                          ? Stack(\n"
                "                              children: [\n"
                "                                Positioned.fill(\n"
                "                                  child: SafeArea(top: false, child: content),\n"
                "                                ),\n"
                "                                Positioned(\n"
                "                                  top: 0,\n"
                "                                  left: 0,\n"
                "                                  right: 0,\n"
                "                                  child: WorkspaceTopChrome(\n"
                "                                    mode: chromeMode,\n"
                "                                    onExit: _exitWorkspace,\n"
                "                                    onResetLayout: _resetLayout,\n"
                "                                  ),\n"
                "                                ),\n"
                "                              ],\n"
                "                            )",
                False,
            ),
            (
                "M39 常驻顶栏不给状态栏让位 → 状态栏那一条露出 Scaffold 底色",
                "lib/workspace/widgets/chrome/workspace_top_chrome.dart",
                "    final topInset = floating ? 0.0 : MediaQuery.paddingOf(context).top;",
                "    final topInset = 0.0;",
                False,
            ),
            (
                "M40 顶栏不再精确等于那一行高（交出去给内容撑）",
                "lib/workspace/widgets/chrome/workspace_top_chrome.dart",
                "    return SizedBox(\n"
                "      height: barHeight + topInset,\n"
                "      child: Container(\n",
                "    return SizedBox(\n"
                "      child: Container(\n",
                False,
            ),
            (
                "M41 揭示形态恒可见（浮层一直盖着内容顶部那一行）",
                "lib/workspace/widgets/chrome/workspace_top_chrome.dart",
                "                    opacity: _visible ? 1 : 0,",
                "                    opacity: 1,",
                False,
            ),
            (
                "M42 揭示形态恒吃鼠标（不可见也拦住内容顶部的点击）",
                "lib/workspace/widgets/chrome/workspace_top_chrome.dart",
                "                ignoring: !_visible,",
                "                ignoring: false,",
                False,
            ),
            (
                "M43 触发带高度归零 → 鼠标贴到窗口最顶端也唤不出来",
                "lib/workspace/widgets/chrome/workspace_top_chrome.dart",
                "  static const double triggerHeight = 10;",
                "  static const double triggerHeight = 0;",
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
    waived = len([r for r in all_rows if r[3] and r[1].startswith("SURVIVED")])
    tail = f"，{waived} 个已备案的冗余兜底" if waived else ""
    print(
        f"变异验证通过：{caught} 个变异体被捕获（都是判据失败，不是编译错）{tail}"
    )


main()
