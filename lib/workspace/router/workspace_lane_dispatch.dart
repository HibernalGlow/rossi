// 「这次推入该落到哪个面板里」的纯记账 —— **不 import Flutter**（见下面的理由）。
//
// 判据：`dart run test/workspace/lane_dispatch_check.dart`
//
// 为什么不写在 widget 里：这段判断决定「点开的东西开在哪儿」，而它错的方式
// 全是**静默**的 —— 页面开在一个已经不可见的面板里、或者干脆没接管（于是全屏
// 盖住整个工作台）。两种都不报错，只在界面上看出来。本机 `flutter test` 起不来
// （flutter_tester 的 WebSocket 握手失败），所以把这段判断抽成纯 Dart，
// 用 `dart run` 直接断言。代价：本文件不 import `package:flutter/**`
// （会拖进 `dart:ui`）。真正的 `Navigator` 由 widget 侧持有
// （`WorkspaceNavigationBridge` 里的 `GlobalKey<NavigatorState>`）。

/// 「泳道里的一个面板」的身份。
///
/// **两条泳道里可以有同名面板**，所以身份是 `(laneId, panelId)` 而不是 panelId。
class WorkspaceLaneHost {
  /// 泳道 id（`LaneId.left` / `LaneId.reader` / `LaneId.right`，四边栏模式复用同一份）。
  final String laneId;

  /// 面板 id（`WorkspacePanelId.*`）。
  final String panelId;

  const WorkspaceLaneHost(this.laneId, this.panelId);

  /// 日志 / 调试用的可读标识。
  String get debugKey => '$laneId/$panelId';

  @override
  bool operator ==(Object other) =>
      other is WorkspaceLaneHost &&
      other.laneId == laneId &&
      other.panelId == panelId;

  @override
  int get hashCode => Object.hash(laneId, panelId);

  @override
  String toString() => debugKey;
}

/// 「工作台里的推入落点」记账。
///
/// 两条输入，一条输出：
/// - **活着的主机**（[registerHost]）：某条泳道**当前可见的那个面板**在此登记。
///   每条泳道至多留一个 —— 后来的顶掉先前的。这条不变量是**结构性**的，
///   不靠调用方自觉：`IndexedStack` 会把访问过的面板都留在树里（切走不重建），
///   于是「哪个面板在屏幕上」不能由「谁还活着」推出来，必须由这里保证唯一。
/// - **最后一次交互**（[noteInteraction]）：用户**在这条泳道里按下指针**时上报。
///   只有已经登记的主机能写进来 —— 在不可见面板上发生的交互（理论上不该有，
///   但如果发生了）不能污染落点。
///
/// [resolveTarget] 是唯一的读取口：**记录 ∩ 仍然活着**，否则 `null` = 不接管。
/// 返回 `null` 时调用方必须原样放行全屏推入 —— 宁可全屏，也不要把页面开进
/// 一个用户看不见的地方（那比全屏更糟：看起来像「点了没反应」）。
class WorkspaceLaneDispatch {
  WorkspaceLaneDispatch._();

  static final WorkspaceLaneDispatch instance = WorkspaceLaneDispatch._();

  /// 泳道 id → 该泳道当前可见面板。**每条泳道至多一项**。
  final Map<String, WorkspaceLaneHost> _live = <String, WorkspaceLaneHost>{};

  WorkspaceLaneHost? _lastInteracted;

  /// 该泳道当前可见的面板（判据与调试用）。
  WorkspaceLaneHost? liveHostOfLane(String laneId) => _live[laneId];

  /// 最后一次交互落点（判据与调试用）。
  WorkspaceLaneHost? get lastInteracted => _lastInteracted;

  /// 一个面板**成为本泳道当前可见的那一个**时登记。
  ///
  /// 同一泳道换面板（别人顶掉它）时，上次的交互记录**作废**：那条记录指向的是
  /// 刚才那个面板，而它已经不在屏幕上了。留着它会把下一次推入开进隐藏面板。
  void registerHost(WorkspaceLaneHost host) {
    _live[host.laneId] = host;
    if (_lastInteracted != null &&
        _lastInteracted!.laneId == host.laneId &&
        _lastInteracted != host) {
      _lastInteracted = null;
    }
  }

  /// 面板不再可见 / 被卸载时注销。**只注销自己登记的那一个** ——
  /// 否则一个正在做退出动画的旧面板会把刚上来的新面板的登记抹掉。
  void unregisterHost(WorkspaceLaneHost host) {
    if (_live[host.laneId] == host) {
      _live.remove(host.laneId);
    }
    if (_lastInteracted == host) {
      _lastInteracted = null;
    }
  }

  /// 用户在这条泳道里按下指针时上报（左键、右键、滚轮按下都算）。
  ///
  /// 只有**已经登记的主机**能被记住。这条约束不是洁癖：`IndexedStack` 里
  /// 那些不可见的面板仍然会和指针发生关系（它们的 `Listener` 还挂在树上），
  /// 没有这条判断，隐藏面板就能偷偷把落点抢过去。
  void noteInteraction(WorkspaceLaneHost host) {
    if (_live[host.laneId] == host) {
      _lastInteracted = host;
    }
  }

  /// 这次推入该落进哪个面板；`null` = 不接管（调用方放行全屏）。
  ///
  /// 这里的「求交」是**冗余兜底**，不是唯一防线：[registerHost] 的作废与
  /// [unregisterHost] 的清理已经维护了「记录必是活主机」这条不变量，
  /// 所以单看行为，删掉这一行也测不出差别（变异验证实测如此，两者互为兜底）。
  /// 留着它是为了在**将来有人改那两个入口**时，最坏的结果也退化成「不接管」
  /// （= 全屏），而不是「把页面开进一个看不见的面板」。
  WorkspaceLaneHost? resolveTarget() {
    final host = _lastInteracted;
    if (host == null) return null;
    return _live[host.laneId] == host ? host : null;
  }

  /// 清空全部记账（工作台卸载时收尾用）。
  void reset() {
    _live.clear();
    _lastInteracted = null;
  }
}
