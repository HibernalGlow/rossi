import 'package:flutter/widgets.dart';

import 'package:zephyr/page/comic_info/action/comic_info_action_entry.dart';

/// 详情页交给动作层的能力：**这一屏能对这本书做什么**。
///
/// 实现者只有 `_ComicInfo`（页面 state）—— 这些方法本来就在那儿（`_startReading`、
/// `_toggleFollow`、`_toggleOrder`、`_handleExport` 与顶栏那两颗的行为），这个接口只是
/// 把它们命名成 id 找得到的样子。
///
/// 刻意不含带状态的那 6 条（收藏 / 点赞 / 评论 / 下载 / 挑章节 / 磁力），也不含
/// 关注 / 章节倒序 / 导出：前 6 条的状态挂在 `ComicOperationWidget` 自己的 `setState`
/// 上，要先把状态提到 Cubit 里（车道 C-2）；后 3 条虽然页面上有现成方法，但它们**不在
/// 口径 2 定的默认清单里**，现在就写进接口等于加三棵没人渲染的分支。等 C-2 把操作行
/// 并进来时一起接。
abstract interface class ComicInfoActionScope {
  /// 当前可用的条目（rail、底部条、操作行都渲染这同一份）。
  ///
  /// 由页面在 `build` 里现造，所以状态一变（加载完、关注成功）三个视图一起变，
  /// 不需要互相通知。
  List<ComicInfoActionEntry> comicInfoActionItems();

  /// 返回上一页。住在发现页标签里时关的是**那条标签**，不是压着详情页的那一整页
  /// —— 这条口径必须和左上角那颗箭头一致，实现处直接复用 `popTabOrClose`。
  void actionBack(BuildContext context);

  /// 回首页 / 工作台根。
  void actionHome(BuildContext context);

  /// 开始或继续阅读（有历史就是继续）。
  void actionRead(BuildContext context);
}

/// 按注册表 id 派发一条详情页动作。
///
/// **一处 switch** 是刻意的：注册表里登记了、这里没接 = 编译期看得见的一处漏，而不是
/// 用户按下去才发现的哑弹（同 `reader_action_dispatcher.dart` 的形状）。
/// 返回 `false` 表示这一条还没有执行体 —— 调用方**必须**提示，不许静默吞掉。
bool dispatchComicInfoAction(
  ComicInfoActionScope scope,
  String actionId,
  BuildContext context,
) {
  switch (actionId) {
    case ComicInfoActionIds.back:
      scope.actionBack(context);
      return true;
    case ComicInfoActionIds.home:
      scope.actionHome(context);
      return true;
    case ComicInfoActionIds.read:
      scope.actionRead(context);
      return true;
    default:
      return false;
  }
}

/// 车道 C-1 已接上执行端**且已被 rail 渲染**的条目 —— 注册表里的 `implemented` 就翻这几条
/// 成 `true`。
///
/// 判据是「端到端可达」而不是「switch 里有分支」：只有 rail 真画出来的那几颗，用户才点得到。
/// 翻早了会让设置页把一颗看不见也按不动的动作显示成「已支持」。
const List<String> wiredComicInfoActions = [
  ComicInfoActionIds.back,
  ComicInfoActionIds.home,
  ComicInfoActionIds.read,
];
