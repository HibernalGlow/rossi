# parts 目录索引

本目录的 part 全部属于同一个库（part of `../collect_comic.dart`）。

| 文件 | 行数 | 内容 |
|---|---|---|
| `collect_comic_rossi_part.dart` | 139 | `ensureLocalComicCollected`、`autoFavoriteComicOnDownloadIfEnabled`— |

## 各文件管什么

- `collect_comic_rossi_part.dart`
  - `ensureLocalComicCollected` — 返回 true 表示新添加了收藏，false 表示此前已收藏。
  - `autoFavoriteComicOnDownloadIfEnabled` — 当开启了“点击下载自动收藏”时，在下载时自动将漫画加入本地收藏。

## 搬家约定

- 新文件一律用 `tool/ast_split/bin/ast_split.dart` 的 `extract` / `extract-members`
  按 AST 区间整块搬，不要手改函数体；搬完跑 `audit`，再跑 `flutter analyze`。
- 上游已有的文件只允许搬本仓自己的行，判据是
  `git diff --numstat upstream/main -- <文件>` 的 `−` 不得变大。
- 上游代码不得搬动：`extract-members --upstream-file <上游版本>` 会拒绝
  上游已存在的同名成员。

<!-- 本索引由 tool/ast_split/gen_parts_readme.py 生成，改动代码后重跑即可。 -->
