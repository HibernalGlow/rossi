# parts 目录索引

本目录的 part 全部属于同一个库（part of `../file_manager_card_test.dart`）。

| 文件 | 行数 | 内容 |
|---|---|---|
| `file_manager_card_test_fakes_part.dart` | 130 | `_TestGlobalSettingCubit`、`_FileManagerApi`— |
| `file_manager_card_test_fixture_part.dart` | 255 | `_treeSnapshot`、`_tab`、`_entry`、`_snapshot`、`_opsSnapshot`、`_opsReport`— |
| `file_manager_card_test_helper_part.dart` | 86 | `_homeRegion`、`_homeRegionPoint`、`_tapHomeRegion`、`_longPressHomeRegion`、`_padPoint`、`_pumpCard` 等 7 项 |

## 各文件管什么

- `file_manager_card_test_fakes_part.dart`
  - `_TestGlobalSettingCubit` — 于是「卡片确实把主页写进了全局设置」仍然可断言。
  - `_FileManagerApi` *(class)*
- `file_manager_card_test_fixture_part.dart`
  - `_treeSnapshot` *(顶层符号)*
  - `_tab` *(顶层符号)*
  - `_entry` *(顶层符号)*
  - `_snapshot` *(顶层符号)*
  - `_opsSnapshot` — 会话那一次问，测试里不会凭空多出一串待收的问询。
  - `_opsReport` — 怎么刷新，而不是替身自己编一份结果。
- `file_manager_card_test_helper_part.dart`
  - `_homeRegion` — 自己算一个落在梯形里的点，直接 `tester.tap(finder)` 会点到刷新。
  - `_homeRegionPoint` — 主页热区（掌形下部的梯形）里的一个点：宽度的中间、高度的 85%。
  - `_tapHomeRegion` *(顶层符号)*
  - `_longPressHomeRegion` *(顶层符号)*
  - `_padPoint` — 掌形里某个方向的落点：把归一化坐标映射到掌的矩形上。
  - `_pumpCard` *(顶层符号)*
  - `_openTree` — 工具栏横向滚动，窄卡片下「文件树」那颗按钮先要滚进视口才点得到。

## 搬家约定

- 新文件一律用 `tool/ast_split/bin/ast_split.dart` 的 `extract` / `extract-members`
  按 AST 区间整块搬，不要手改函数体；搬完跑 `audit`，再跑 `flutter analyze`。
- 上游已有的文件只允许搬本仓自己的行，判据是
  `git diff --numstat upstream/main -- <文件>` 的 `−` 不得变大。
- 上游代码不得搬动：`extract-members --upstream-file <上游版本>` 会拒绝
  上游已存在的同名成员。

<!-- 本索引由 tool/ast_split/gen_parts_readme.py 生成，改动代码后重跑即可。 -->
