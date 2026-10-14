#!/usr/bin/env python3
"""设置页分组样式门禁：凡是画设置行的文件都必须用 M3E 分组，不留裸行。

覆盖面按**内容**取，不按文件名猜：`lib/page/setting/` 下（`common/` 除外，那是
外壳与分组组件自己）任何出现设置行或分隔线的 .dart，加上手机「更多」页那份设置
列表。这样 `*_body.dart`、`parts/*` 这类不叫 `_page.dart` 的正文也算在内。

判据（三条硬红线，不做豁免表）：
1. 自带 `Scaffold(` 又没有 `SettingPageShell(` —— 老壳；
2. 出现 `Divider(` —— 旧的「细线隔一段」，正是纯白底的成因；
3. **页面**（带 `@RoutePage()` 或 `SettingPageShell(`，外加手机「更多」那份设置列表）
   画了行（`ListTile` / `SwitchListTile` / `SettingGroup.switchTile`）却没有一张
   `SettingSectionCard(` 或 `SettingGroup(` —— 行直接坐在页面底色上。

第 3 条只管页面本体，不管「行工厂」（`global/widgets.dart` 之类返回一行给别的
页面摆的文件）与编辑器（按键绑定、图标挑选），那些不是设置项列表。它只看「有没有
分组」，不看嵌套；嵌套那半由 `test/setting/setting_group_style_test.dart`
在真页面上逐页 pump 验。

用法：
    python3 script/check_setting_group_style.py            # 列出还没迁的文件
    python3 script/check_setting_group_style.py --strict   # 有未迁文件就退出码 1
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

SEARCH_DIRS = [
    REPO / "lib/page/setting",
    # 从「外观与显示」跳出去的两次级页面也是设置项，风格跟着同一套走。
    REPO / "lib/page/font_setting",
    REPO / "lib/page/theme_color",
    REPO / "lib/page/about",
]
EXTRA_FILES = [REPO / "lib/page/more/widgets/settings.dart"]
# 明确不参与统一口径的文件：超分（RealSR）那一块按用户口径「没有特定风格」，
# 它的条件是自定义面板（阅读端与工作台共用），不套设置页分组。
# 排除是**写出来给人看的**，不是静默跳过 —— 每次运行都会打印这一份清单。
# 一级页（设置总入口）不许挂折叠大标题：它下面就是双栏总览卡。
ROOT_PAGE = "lib/page/setting/global/global_setting.dart"
EXCLUDED = {
    "lib/page/setting/real_sr/real_sr_setting_page.dart": "超分设置不做统一风格（用户口径）",
    "lib/page/setting/real_sr/widgets/real_sr_model_management_section.dart": "同上",
    "lib/page/setting/real_sr/widgets/upscale_conditions_card.dart": "同上（与阅读端共用的自定义面板）",
}
# 不是 @RoutePage，但确实是一屏设置项的正文（手机「更多」页那份列表）。
EXTRA_PAGE_PATHS = ["lib/page/more/widgets/settings.dart"]
SKIP_DIRS = {"common", "parts"}

SHELL_CALL = re.compile(r"SettingPageShell\(([^)]*)\)", re.S)
CARD_CALL = re.compile(r"Setting(?:SectionCard|Group)\(\s*title:\s*(t\.[\w.]+),")
KEY_RE = re.compile(r"title:\s*(t\.[\w.]+),")
ROW_WIDGET = re.compile(
    r"\bListTile\(|\bSwitchListTile\(|\bSettingGroup\.switchTile\("
)
GROUP_WIDGET = re.compile(r"\bSettingSectionCard\(|\bSettingGroup\(")
DIVIDER = re.compile(r"\bDivider\(")
SHELL = re.compile(r"\bSettingPageShell\(")
RAW_SCAFFOLD = re.compile(r"\bScaffold\(")
# 标题面归外壳：页面自己再搭一个 AppBar / NestedScrollView / CustomScrollView，
# 就等于绕开了折叠大标题那一条（实测溢出就是这么引出来的）。
OWN_BAR = re.compile(r"\bAppBar\(|\bNestedScrollView\(|\bCustomScrollView\(")
ROUTE_PAGE = re.compile(r"@RoutePage\(\)")
# 外壳必须真的提供折叠大标题。换实现（例如本地按字号定高的 sliver）时，
# 连同这一条与它下面的理由一起改，别让它悄悄退回实色小栏。
COLLAPSING_BAR = re.compile(r"\bNestedScrollView\(")
FLEXIBLE_SLIVER_BAR = re.compile(r"M3EAppBar\.sliver\(")
SHELL_FILE = "lib/page/setting/common/setting_ui.dart"


def strip_comments(source: str) -> str:
    """禁词尺要先剥注释：注释里提到 Divider 不该算这个文件用了 Divider。"""
    no_block = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    lines = []
    for line in no_block.splitlines():
        if line.strip().startswith("//"):
            continue
        lines.append(re.sub(r"//.*$", "", line))
    return "\n".join(lines)


def collect_files() -> list[Path]:
    found: list[Path] = []
    for base in SEARCH_DIRS:
        for path in sorted(base.rglob("*.dart")):
            if path.name.endswith((".g.dart", ".freezed.dart")):
                continue
            if SKIP_DIRS.intersection(path.parts):
                continue
            found.append(path)
    for path in EXTRA_FILES:
        if path.exists() and path not in found:
            found.append(path)
    kept = [p for p in found if _renders_rows(p)]
    excluded = [p for p in kept if str(p.relative_to(REPO)) in EXCLUDED]
    return [p for p in kept if p not in excluded], excluded


def _renders_rows(path: Path) -> bool:
    body = strip_comments(path.read_text(encoding="utf-8"))
    return bool(ROW_WIDGET.search(body) or DIVIDER.search(body))


def check(path: Path) -> list[str]:
    body = strip_comments(path.read_text(encoding="utf-8"))
    problems: list[str] = []

    is_page = bool(ROUTE_PAGE.search(body) or SHELL.search(body)) or path in [
        REPO / rel for rel in EXTRA_PAGE_PATHS
    ]

    if RAW_SCAFFOLD.search(body) and not SHELL.search(body):
        problems.append("自带 Scaffold 却没走 SettingPageShell（老壳）")
    if DIVIDER.search(body):
        problems.append("还有 Divider 分段（旧 MD3 的纯白底分隔线）")
    if is_page and OWN_BAR.search(body):
        problems.append("页面自己搭了 AppBar/滚动视图，绕开了外壳的折叠大标题")
    if is_page and ROW_WIDGET.search(body) and not GROUP_WIDGET.search(body):
        problems.append("有设置行但一张 SettingSectionCard/SettingGroup 都没有")
    if is_page:
        problems += _duplicate_titles(path, body)

    return problems


def _duplicate_titles(path: Path, body: str) -> list[str]:
    """卡片标题不许和页大标题同一句：外壳已经有折叠大标题了。

    页面自己那行 `title:` 只有取到词条表达式才比对（`webdav_sync_page` 传的是变量，跳过）。
    """
    shell = SHELL_CALL.search(body)
    if not shell:
        return []
    page_key_match = KEY_RE.search(shell.group(1))
    if not page_key_match:
        return []
    page_key = page_key_match.group(1)
    dups = [card for card in CARD_CALL.findall(body) if card == page_key]
    if not dups:
        return []
    return [
        f"{len(dups)} 张卡的标题与页大标题同一句（{page_key}）——"
        " 要么改成小节名，要么整张卡不给标题"
    ]


def check_root_page() -> list[str]:
    """一级页保持小标题栏：折叠大标题只给二级页。"""
    body = (REPO / ROOT_PAGE).read_text(encoding="utf-8")
    if "SettingPageShell(" not in body:
        return [f"{ROOT_PAGE} 不再使用 SettingPageShell，这把尺要跟着改"]
    if "collapsingTitle: false" not in body:
        return ["设置总入口（一级页）挂上了折叠大标题 —— 它下面已经有双栏总览卡"]
    return []


def check_shell() -> list[str]:
    """外壳自己那一条：折叠大标题不许被悄悄退回实色小栏。"""
    body = strip_comments((REPO / SHELL_FILE).read_text(encoding="utf-8"))
    problems = []
    if not COLLAPSING_BAR.search(body) or not FLEXIBLE_SLIVER_BAR.search(body):
        problems.append(
            f"{SHELL_FILE} 里找不到折叠大标题（NestedScrollView + M3EAppBar.sliver）；"
            " 换实现就连带改掉这把尺的理由"
        )
    return problems


def main() -> int:
    files, excluded = collect_files()
    if not files:
        print("没找到任何画设置行的文件 —— 目录结构变了，先修这把尺本身。", file=sys.stderr)
        return 2

    pending = [(path, check(path)) for path in files]
    pending = [(path, problems) for path, problems in pending if problems]
    shell_problems = check_shell() + check_root_page()

    print(f"扫描 {len(files)} 个画设置行的文件，已迁 {len(files) - len(pending)} 个。")
    for problem in shell_problems:
        print(f"  外壳不合格：{problem}")
    for path in excluded:
        reason = EXCLUDED[str(path.relative_to(REPO))]
        print(f"  不参与统一口径：{path.relative_to(REPO)} —— {reason}")
    for path, problems in pending:
        print(f"  {path.relative_to(REPO)}")
        for problem in problems:
            print(f"      - {problem}")

    if (pending or shell_problems) and "--strict" in sys.argv:
        print(
            f"还有 {len(pending)} 个文件未迁到分组样式，"
            f"外壳不合格 {len(shell_problems)} 条。",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
