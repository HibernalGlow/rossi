import 'package:flutter/widgets.dart';

/// 详情页一条动作的**渲染 + 执行**数据。
///
/// 存在的理由：rail（车道 E）、移动端底部条（车道 G）、封面下方那横排操作行
/// （`comic_operation.dart`）要渲染的是**同一份清单**。清单若各写一份，加一个动作
/// 就得改三处，而「哪些动作存在」的权威本来在 Rust 的 `ACTION_CATALOG`
/// （`docs/comic-info-action-rail.md` §7.5）—— 这里只是把那份权威配上**当前这本书**的
/// 状态（置灰、高亮、文案随 `hasHistory` 变）与执行闭包。
///
/// 与 `_OperationItemData` 的区别只有一个：这里带 [actionId]。没有 id 就没有单一真相 ——
/// 自定义配置（车道 D）存的、绑定表存的、派发时比对的，全都是这个 id。
///
/// **为什么不叫 `ComicInfoActionItem`**：那个名字已经被插件 JSON 里的一条动态动作占了
/// （`normal_comic_all_info.dart:38`，`{name, onTap, extern}`，走
/// `models/comic_info_action.dart` 的 `handleComicInfoAction`）。两件事同名，读代码的人
/// 会把「标签点下去开搜索」当成「rail 上那颗」。
@immutable
class ComicInfoActionEntry {
  const ComicInfoActionEntry({
    required this.actionId,
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.selected = false,
    this.accentColor,
    this.onLongPress,
    this.longPressTooltip,
    this.tooltip,
  });

  /// 注册表里的动作 id（`comic-info.back` 等）。
  ///
  /// 必须能在 `OperationBindingStore.actionCatalog()` 里找到；找不到就是两边分叉了，
  /// `test/operation_binding/comic_info_catalog_bridge_test.dart` 会红。
  final String actionId;

  final IconData icon;

  /// **当前状态下的**文字（「继续阅读」而不是注册表里中性的「开始或继续阅读」）。
  final String label;

  /// 执行体。为空 = 这一项这次**不该出现**（还没加载完、触摸端的阅读入口不落在操作行）：
  /// 由构造清单的一方直接不放这一条，而不是放一条永远点不动的。
  ///
  /// 与 [enabled] 是两件事：不可用是「看得见按不动」（图源不让点赞），不出现是
  /// 「这本书没有这件事」（插件没给磁力）。
  final VoidCallback? onTap;

  /// `false` = 这本图源不让做（`allowLike` / `allowComments` / `allowDownload`）。
  ///
  /// 渲染成置灰，**不是**不画：点了没反应和「这颗现在不能用」是两件事，后者才告诉用户
  /// 换一个图源就有了。
  final bool enabled;

  /// 已处于「做过」的状态（已收藏 / 已点赞 / 已关注）⇒ 高亮。
  final bool selected;

  final Color? accentColor;

  /// 长按的另一个动作（下载那颗：单击整本、长按挑章节）。
  final VoidCallback? onLongPress;

  final String? longPressTooltip;
  final String? tooltip;
}

/// 详情页动作 id —— 与 Rust `mod action` 里的 `COMIC_INFO_*` **逐字**一致。
///
/// 为什么 Dart 侧还要再写一遍字面量：Dart 引用不到 Rust 的常量（注册表走 JSON 字符串
/// 过桥，只有 `actionCatalog()` 这一份**数据**）。这一组常量的正确性由
/// `comic_info_catalog_bridge_test.dart` 按 id 清单逐条钉住，不是靠人对齐。
abstract final class ComicInfoActionIds {
  static const back = 'comic-info.back';
  static const home = 'comic-info.home';
  static const read = 'comic-info.read';
  static const collect = 'comic-info.collect';
  static const follow = 'comic-info.follow';
  static const like = 'comic-info.like';
  static const comments = 'comic-info.comments';
  static const download = 'comic-info.download';
  static const downloadChapters = 'comic-info.download-chapters';
  static const copyMagnet = 'comic-info.copy-magnet';
  static const toggleChapterOrder = 'comic-info.toggle-chapter-order';
  static const export = 'comic-info.export';
  static const more = 'comic-info.more';

  /// 车道 A 登记的全部 id，顺序与 `ACTION_CATALOG` 一致。
  static const all = <String>[
    back,
    home,
    read,
    collect,
    follow,
    like,
    comments,
    download,
    downloadChapters,
    copyMagnet,
    toggleChapterOrder,
    export,
    more,
  ];

  /// **页面自己就能执行**的那一族（车道 C-1）：不依赖 `ComicOperationWidget` 的局部
  /// 状态，所以不需要先把 handler 搬出来。
  ///
  /// 剩下 7 条要等 C-2：6 条（[stateful]）的收藏 / 点赞 / 下载状态挂在那个 widget 的
  /// `setState` 上，得先把状态提到 Cubit 里；`more` 要先把顶栏那颗的选项表提出来
  /// （否则 rail 上的「更多」是个空弹层）。分两步是为了让操作行的行为在整个过程中
  /// 一步都不变（口径 5）。
  static const pageOwned = <String>[
    back,
    home,
    read,
    follow,
    toggleChapterOrder,
    export,
  ];

  /// 状态挂在 `ComicOperationWidget` 的 `setState` 上、要等 C-2 的那 6 条。
  static const stateful = <String>[
    collect,
    like,
    comments,
    download,
    downloadChapters,
    copyMagnet,
  ];
}
