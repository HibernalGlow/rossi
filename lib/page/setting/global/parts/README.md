# parts 目录索引

本目录的 part 全部属于同一个库（part of `../workspace_layout_setting_page.dart`）。

| 文件 | 行数 | 内容 |
|---|---|---|
| `workspace_layout_delay_controls_part.dart` | 159 | `_DelayTile`、`_NumberBox`、`_NumberBoxState`— |
| `workspace_layout_reveal_zone_part.dart` | 568 | `_RevealZoneCard`、`_edgeLabel`、`_ZoneDrag`、`_RevealZoneEditor`、`_RevealZoneEditorState`、`RevealZoneField` 等 10 项 |

## 各文件管什么

- `workspace_layout_delay_controls_part.dart`
  - `_DelayTile` — 想复现另一个候选的取值反而做不到。
  - `_NumberBox` — 就生效一次（100 → 1 → 10 → 100 中间那几步都是无意义的抖动）。
  - `_NumberBoxState` *(class)*
- `workspace_layout_reveal_zone_part.dart`
  - `_RevealZoneCard` *(class)*
  - `_edgeLabel` *(顶层符号)*
  - `_ZoneDrag` — 一次拖拽：要么在空处**画框**，要么抓住选中的那块**拖某个角**。
  - `_RevealZoneEditor` *(class)*
  - `_RevealZoneEditorState` *(class)*
  - `RevealZoneField` — 唤出区的四个可编辑量。
  - `_LabeledNumberField` — 画布下方的小数字框（X / Y / 宽 / 高）。
  - `_PercentBox` — 百分比数字框：0..99，0.1 步进，同样只在回车 / 失焦时提交。
  - `_PercentBoxState` *(class)*
  - `_RevealZonePainter` — `IgnorePointer` 反而更啰嗦。

## 搬家约定

- 新文件一律用 `tool/ast_split/bin/ast_split.dart` 的 `extract` / `extract-members`
  按 AST 区间整块搬，不要手改函数体；搬完跑 `audit`，再跑 `flutter analyze`。
- 上游已有的文件只允许搬本仓自己的行，判据是
  `git diff --numstat upstream/main -- <文件>` 的 `−` 不得变大。
- 上游代码不得搬动：`extract-members --upstream-file <上游版本>` 会拒绝
  上游已存在的同名成员。

<!-- 本索引由 tool/ast_split/gen_parts_readme.py 生成，改动代码后重跑即可。 -->
