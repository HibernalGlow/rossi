import 'package:zephyr/workspace/model/workspace_reader_target.dart';

/// 工作台与**全局导航**之间的窄接口。
///
/// # 为什么需要这一层
///
/// neoview 的契约是「中央泳道就是 Reader」；而 Rossi 的泳道里跑的是**上游原版页面**
/// （书架、发现、历史……），它们打开漫画的方式是 `context.pushRoute(ComicReadRoute)`。
/// 要让这些推入落进中央泳道、又不许改动上游任何一个文件，只能在**导航这一层**接住它：
/// 工作台挂载时登记一个回调，根路由的守卫把 `ComicReadRoute` 的推入改派到这里，
/// 并中止原本的全屏推入。
///
/// 所以这里的语义只有两条，必须保持：
/// - **工作台没挂载 → 什么都没发生**（回调为空），全屏阅读器照旧；
/// - **工作台挂载 → 泳道接管**，返回 `true`，调用方放弃自己的导航。
class WorkspaceReaderBridge {
  WorkspaceReaderBridge._();

  static final WorkspaceReaderBridge instance = WorkspaceReaderBridge._();

  void Function(WorkspaceReaderTarget target)? _openInLane;

  /// 当前是否有工作台挂载（守卫据此决定要不要接管）。
  bool get isAttached => _openInLane != null;

  /// 工作台挂载时登记「在阅读器泳道里打开」的回调。
  void attach(void Function(WorkspaceReaderTarget target) openInLane) {
    _openInLane = openInLane;
  }

  /// 工作台卸载时注销。只注销自己登记的那个回调，
  /// 避免把后来者（例如重建后的另一个工作台实例）的回调抹掉。
  void detach(void Function(WorkspaceReaderTarget target) openInLane) {
    if (identical(_openInLane, openInLane)) {
      _openInLane = null;
    }
  }

  /// 交给工作台打开；没有工作台时返回 `false`（调用方应继续自己的导航）。
  bool openInLane(WorkspaceReaderTarget target) {
    final open = _openInLane;
    if (open == null) return false;
    open(target);
    return true;
  }
}
