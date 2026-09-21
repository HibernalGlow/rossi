# config/global parts 维护笔记

`global_setting.dart` 里 rossi 自己新增的设置状态，按职责拆到了本目录的 4 个 part。
拆的目的是**减小与上游 Breeze 的合并冲突面**：上游继续改 `global_setting.dart` 时，
rossi 的这些块不会再混在同一文件末尾。

## 快速索引

- `global_setting_toast_part.dart`
  - 提示条：`ToastPosition`（九宫格停靠位）与 `label`/`alignment` 映射、`ToastSettingState`、
    `toastSetting` 快照；切换提示 `SwitchToastSettingState` 与 `switchToastSetting`。
- `global_setting_favorite_part.dart`
  - 喜欢画师 `FavoriteArtistSettingState`；收藏 tag 的 `FavoriteTag`（每条自带别名）、
    `FavoriteTagSettingState`，以及三个私有工具函数：按下标找 tag 的 `_indexOfFavoriteTag`、
    清洗别名的 `_cleanTagAliases`、按 nameKey 去重合并的 `_dedupeFavoriteTags`。
    这三个私有助手被 `GlobalSettingState` 里 rossi 加的 add/remove/toggle 方法调用，
    所以必须留在**同一个库**内（这也是本目录用 part 而不是独立库的原因）。
- `global_setting_workspace_part.dart`
  - 文件管理器卡片 `FileManagerSettingState`；发现页 `DiscoverTabBarSide` 与
    `DiscoverSettingState`；操作绑定 `OperationBindingSettingState`；
    漫画卡片的未读角标样式 `ComicUnreadIndicatorStyle`、`ComicCardSettingState` 与 `comicCardSetting`。
- `global_setting_read_extras_part.dart`
  - 不经 Bloc 的阅读设置快照 `readSettingSnapshot`（GPU 呈现器这类拿不到 BuildContext 的地方用），
    以及环境光暗度滑条的三个常量 `readerAmbientDimPercentMin/Max/Default`。

## 约定

- 生成物仍是 `global_setting.freezed.dart` 与 `global_setting.g.dart`，它们是 `global_setting.dart`
  这个库的 part；本目录的 part 里声明的 `@freezed` 类，其生成代码照样落在那两个文件里。
  改完这些文件后要跑一次代码生成。
- 新增 rossi 专属设置时，优先放进本目录对应的 part，或新建一个 part 并在
  `global_setting.dart` 里加一行 `part 'parts/xxx.dart';` —— 不要再往 `global_setting.dart`
  末尾追加。上游同名文件的冲突通常就出在那个位置。
