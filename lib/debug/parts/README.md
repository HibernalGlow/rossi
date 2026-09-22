# parts 目录索引

本目录的 part 全部属于同一个库（part of `../local_source_debug_page.dart`）。

| 文件 | 行数 | 内容 |
|---|---|---|
| `local_source_debug_load_part.dart` | 660 | `_LocalSourceDebugLoadPart`— |
| `local_source_debug_models_part.dart` | 175 | `_StageRow`、`_PrefetchedPage`、`_DecoderMode`、`sniffImageFormat`— |
| `local_source_debug_prefetch_part.dart` | 278 | `_LocalSourceDebugPrefetchPart`— |
| `local_source_debug_view_part.dart` | 572 | `_LocalSourceDebugViewPart`— |

## 各文件管什么

- `local_source_debug_load_part.dart`
  - `_LocalSourceDebugLoadPart` *(extension)*
- `local_source_debug_models_part.dart`
  - `_StageRow` — 一次翻页的分段记录。留着历史才能对比「全尺寸 vs 显示尺寸」。
  - `_PrefetchedPage` — 唯一能让翻页掉到 200 ms 以下的办法是**别在翻页时解码**。
  - `_DecoderMode` — 留着开关是为了让两条路径的耗时当场可比，而不是只能信文档里的数字。
  - `sniffImageFormat` — 44.8 MPix 的 JPEG 慢是必然的，跟读取路径无关。
- `local_source_debug_prefetch_part.dart`
  - `_LocalSourceDebugPrefetchPart` *(extension)*
- `local_source_debug_view_part.dart`
  - `_LocalSourceDebugViewPart` *(extension)*

## 搬家约定

- 新文件一律用 `tool/ast_split/bin/ast_split.dart` 的 `extract` / `extract-members`
  按 AST 区间整块搬，不要手改函数体；搬完跑 `audit`，再跑 `flutter analyze`。
- 上游已有的文件只允许搬本仓自己的行，判据是
  `git diff --numstat upstream/main -- <文件>` 的 `−` 不得变大。
- 上游代码不得搬动：`extract-members --upstream-file <上游版本>` 会拒绝
  上游已存在的同名成员。

<!-- 本索引由 tool/ast_split/gen_parts_readme.py 生成，改动代码后重跑即可。 -->
