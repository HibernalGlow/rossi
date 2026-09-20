import 'package:flutter/widgets.dart';
import 'package:zephyr/page/search/cubit/search_cubit.dart';

/// 发现页发给**标签内容**的把手：「你现在住在一个标签里，要开东西请开成标签」。
///
/// 为什么是 InheritedWidget 而不是全局单例：这件事的答案跟着**位置**走 ——
/// 同一张漫画卡片，摆在书架里点了该推详情页，摆在发现页的标签里点了该开一条标签。
/// 单例只能回答「发现页在不在」，回答不了「这一下是不是在标签里点的」。
///
/// 为什么让卡片显式问一句，而不是在根路由上拦推入：拦要回答「这次推入是谁发起的」，
/// 而一次按下会同时命中泳道面板与标签两层监听，谁赢取决于派发顺序 ——
/// 那是个不该依赖的东西（见 `DiscoverTabs` 的类注释）。
class DiscoverTabScope extends InheritedWidget {
  const DiscoverTabScope({
    super.key,
    required this.actions,
    required super.child,
  });

  final DiscoverTabActions actions;

  /// 当前标签体系里的那份把手；不在标签里（书架、工作台别的泳道……）返回 `null`。
  static DiscoverTabActions? maybeOf(BuildContext context) {
    final element = context
        .getElementForInheritedWidgetOfExactType<DiscoverTabScope>();
    return (element?.widget as DiscoverTabScope?)?.actions;
  }

  @override
  bool updateShouldNotify(covariant DiscoverTabScope oldWidget) =>
      !identical(oldWidget.actions, actions);
}

abstract class DiscoverTabActions {
  /// 在标签体系里打开一本漫画的详情。
  ///
  /// [title] 由调用方给（卡片手上就有漫画名）—— 路由参数里没有，
  /// 而标签标题正是靠它区分「同一插件开的第二个详情」。
  /// 两个 collection 参数原样转给详情页：卡片带着「收进哪个合集」的上下文时，
  /// 开成标签不该把那份上下文丢掉。
  void openComicInfo({
    required String comicId,
    required String from,
    required String title,
    String? collectionTargetId,
    String? collectionTargetName,
  });

  /// 「回到这一屏的搜索输入页」。
  ///
  /// 结果页那颗伪装的搜索框干的就是这件事：不在标签里时它读根路由栈决定
  /// 「弹回去」还是「换一页」；在标签里时那两件事都不成立（根栈上只有导航栏，
  /// `stack.length > 1` 直接落空，`replaceRoute` 会去换掉根路由）。
  /// 所以这里开一条搜索标签。
  void openSearchInput(SearchStates state, {required bool aggregateMode});

  /// 详情页里那颗「返回」：住在这套标签体系里时它关的是**当前这条标签**。
  void closeCurrentTab();

  /// 通用出口：把一整页开成一条新标签。
  ///
  /// 给「上游页面自己推下一屏」那些场合 —— 搜索页提交之后开结果页就是这类。
  /// 那些页面推的是路由，而路由一旦推出去就落在标签条**外面**（泳道里落在面板的
  /// 局部栈、手机上落在根栈），把整条标签条盖掉。让它们显式走这里，
  /// 才不必靠「猜这次推入是谁发起的」。
  void openPage({
    required String label,
    required String source,
    required WidgetBuilder content,
    IconData? icon,
  });

  /// 详情页里那颗「主页」：切回首页标签，而不是把根路由栈弹到底。
  void goHome();
}

/// 标签里 ⇒ 关掉当前这条标签；不在标签里 ⇒ 走 [otherwise]（原样的路由弹栈）。
///
/// 每个「这一屏的返回」都写这一行，是为了让**漏接**这件事在 review 里看得见：
/// 这些页面（搜索、结果、聚合结果、详情、插件设置）都能同时出现在标签里和
/// 根路由上，只在一处做判断等于在别处忘了做。
void popTabOrClose(BuildContext context, {required VoidCallback otherwise}) {
  final tabs = DiscoverTabScope.maybeOf(context);
  if (tabs == null) {
    otherwise();
    return;
  }
  tabs.closeCurrentTab();
}
