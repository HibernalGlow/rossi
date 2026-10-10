import 'package:flutter/foundation.dart';

/// 工作台是否**在场**（`BreezeWorkspacePage` 已完成进场动画、盖在首页壳之上）。
///
/// 这是「进工作台时把底下那层休眠」的信号源。被一条不透明路由盖住的页面
/// 本来就不布局、不绘制（Offstage），但它的 State 与**已挂载的 Image widget**
/// 都还活着 —— 后者握着的解码位图（imageCache 里的 live images）清不掉。
/// 在场信号翻转后，首页壳把它内容里的图片换成纯色占位，widget 卸载、
/// 监听归零，live image 才真正释放；退场时占位换回图片，按文件重新解码。
///
/// 谁写它：[BreezeWorkspacePage]（进场动画结束时置真，`dispose` 置假）。
/// 谁读它：`NavigationBar`（包成 `WorkspaceImageSleepScope` 提给自己的页面栈）。
///
/// 范围约定：**没有 scope 的子树一律视为清醒**。工作台内嵌的上游页面、
/// 以及从工作台推到根栈上的页面（全屏看图等）都不在首页壳的 scope 里，
/// 不会跟着休眠。
abstract final class WorkspacePresence {
  /// true = 工作台在场（进场动画已结束）。
  static final ValueNotifier<bool> present = ValueNotifier<bool>(false);
}
