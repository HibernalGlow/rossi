# parts 目录索引

本目录的 part 全部属于同一个库（part of `../reader_settings_sheet.dart`）。

| 文件 | 行数 | 内容 |
|---|---|---|
| `reader_settings_super_resolution_part.dart` | 139 | `_SuperResolutionSection`、`_SuperResolutionSectionState`— |
| `reader_settings_video_part.dart` | 256 | `_VideoSection`、`_VideoSectionState`、`_StringListTile`— |

## 各文件管什么

- `reader_settings_super_resolution_part.dart`
  - `_SuperResolutionSection` — 阅读器设置里的「AI 超分辨率」。
  - `_SuperResolutionSectionState` *(class)*
- `reader_settings_video_part.dart`
  - `_VideoSection` — 写盘同样是「先 setState 再 await」——设置界面卡顿比晚 100 ms 落盘难看得多。
  - `_VideoSectionState` *(class)*
  - `_StringListTile` — 留在旧名字下会让人以为「图片格式不该走这颗」。

## 搬家约定

- 新文件一律用 `tool/ast_split/bin/ast_split.dart` 的 `extract` / `extract-members`
  按 AST 区间整块搬，不要手改函数体；搬完跑 `audit`，再跑 `flutter analyze`。
- 上游已有的文件只允许搬本仓自己的行，判据是
  `git diff --numstat upstream/main -- <文件>` 的 `−` 不得变大。
- 上游代码不得搬动：`extract-members --upstream-file <上游版本>` 会拒绝
  上游已存在的同名成员。

<!-- 本索引由 tool/ast_split/gen_parts_readme.py 生成，改动代码后重跑即可。 -->
