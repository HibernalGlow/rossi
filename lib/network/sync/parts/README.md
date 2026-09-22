# parts 目录索引

本目录的 part 全部属于同一个库（part of `../sync_service.dart`）。

| 文件 | 行数 | 内容 |
|---|---|---|
| `sync_service_rossi_part.dart` | 337 | `_shellBlockName`、`_toastBlockName`、`_fileManagerBlockName`、`_operationBindingBlockName`、`_workspaceBlockName`、`_settingsStateBlockNames` 等 19 项 |

## 各文件管什么

- `sync_service_rossi_part.dart`
  - `_shellBlockName` *(顶层符号)*
  - `_toastBlockName` *(顶层符号)*
  - `_fileManagerBlockName` *(顶层符号)*
  - `_operationBindingBlockName` *(顶层符号)*
  - `_workspaceBlockName` — 读文件 / 改写文件的路（[_applyWorkspaceBlockData]）。
  - `_settingsStateBlockNames` — 上面那张表里**住在 `GlobalSettingState` 内**的块名。
  - `_factoryEqualBlockTimestamp` — 沿用「本机 = 现在」的老口径，不去动它们（那是另一件事，见 `docs/settings-sync-scope.md`）。
  - `_workspaceFactoryHash` — 换一个编码方式去比，等于两边对「出厂」的定义悄悄分叉，判据就永远不成立。
  - `_appendLocalWorkspaceBlock` — （这时本地同样没有 meta）仍然按「本机说了算」走，不会被他自己的云端旧值盖掉。
  - `_resolveWorkspaceBlockUpdatedAt` — 3. 内容变了 ⇒ 现在。
  - `_buildLocalWorkspaceBlockData` — 而原因只是一次读盘失败），后者才该让云端说了算（那由块时间戳 0 表达）。
  - `_applyWorkspaceBlockData` — 现象是「同步说明明成功了，界面纹丝不动」。这条路收在 `WorkspaceLayoutBridge`。
  - …另有 7 项，见文件

## 搬家约定

- 新文件一律用 `tool/ast_split/bin/ast_split.dart` 的 `extract` / `extract-members`
  按 AST 区间整块搬，不要手改函数体；搬完跑 `audit`，再跑 `flutter analyze`。
- 上游已有的文件只允许搬本仓自己的行，判据是
  `git diff --numstat upstream/main -- <文件>` 的 `−` 不得变大。
- 上游代码不得搬动：`extract-members --upstream-file <上游版本>` 会拒绝
  上游已存在的同名成员。

<!-- 本索引由 tool/ast_split/gen_parts_readme.py 生成，改动代码后重跑即可。 -->
