# parts 目录索引

本目录的 part 全部属于同一个库（part of `../file_manager_card.dart`）。

| 文件 | 行数 | 内容 |
|---|---|---|
| `file_manager_card_file_ops_part.dart` | 457 | `_FileManagerCardFileOpsPart`— |
| `file_manager_card_model_part.dart` | 62 | `FileManagerViewModeX`、`fileManagerLibraryMode`、`_ErrorState`、`_HomeAction`— |
| `file_manager_card_navigation_part.dart` | 473 | `_FileManagerCardNavigationPart`— |
| `file_manager_card_open_part.dart` | 105 | `_FileManagerCardOpenPart`— |
| `file_manager_card_search_part.dart` | 304 | `_FileManagerCardSearchPart`— |
| `file_manager_card_session_part.dart` | 259 | `_FileManagerCardSessionPart`— |
| `file_manager_card_toolbar_part.dart` | 340 | `_FileManagerCardToolbarPart`— |
| `file_manager_card_tree_part.dart` | 164 | `_FileManagerCardTreePart`— |
| `file_manager_card_view_part.dart` | 178 | `_FileManagerCardViewPart`— |

## 各文件管什么

- `file_manager_card_file_ops_part.dart`
  - `_FileManagerCardFileOpsPart` *(extension)*
- `file_manager_card_model_part.dart`
  - `FileManagerViewModeX` *(extension)*
  - `fileManagerLibraryMode` *(顶层符号)*
  - `_ErrorState` *(class)*
  - `_HomeAction` — 主页键长按 / 右键菜单的三个动作。
- `file_manager_card_navigation_part.dart`
  - `_FileManagerCardNavigationPart` *(extension)*
- `file_manager_card_open_part.dart`
  - `_FileManagerCardOpenPart` *(extension)*
- `file_manager_card_search_part.dart`
  - `_FileManagerCardSearchPart` *(extension)*
- `file_manager_card_session_part.dart`
  - `_FileManagerCardSessionPart` *(extension)*
- `file_manager_card_toolbar_part.dart`
  - `_FileManagerCardToolbarPart` *(extension)*
- `file_manager_card_tree_part.dart`
  - `_FileManagerCardTreePart` *(extension)*
- `file_manager_card_view_part.dart`
  - `_FileManagerCardViewPart` *(extension)*

## 搬家约定

- 新文件一律用 `tool/ast_split/bin/ast_split.dart` 的 `extract` / `extract-members`
  按 AST 区间整块搬，不要手改函数体；搬完跑 `audit`，再跑 `flutter analyze`。
- 上游已有的文件只允许搬本仓自己的行，判据是
  `git diff --numstat upstream/main -- <文件>` 的 `−` 不得变大。
- 上游代码不得搬动：`extract-members --upstream-file <上游版本>` 会拒绝
  上游已存在的同名成员。

<!-- 本索引由 tool/ast_split/gen_parts_readme.py 生成，改动代码后重跑即可。 -->
