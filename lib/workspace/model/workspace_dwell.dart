import 'dart:math' as math;

// 本文件**刻意不 import Flutter**，也**不自己起 Timer**：
// 时间由调用方以「毫秒数」传进来，于是判据（`dart run test/workspace/dwell_check.dart`）
// 可以把时间拨快拨慢、断言「到点前不发、到点发一次、离开就取消」，
// 而不是靠 `await Future.delayed` 去赌调度。widget 侧只负责喂真实时钟。

/// 一个「驻留到点就触发一次」的计时器（**纯逻辑**）。
///
/// 契约里所有「dwell」都是同一个形状：**指针进入 → 计时 → 到点触发一次；
/// 离开 / 取消 → 计时作废**。三处用它：
///
/// - Reader **悬停聚焦**（指针停在非激活的 Reader 泳道里）；
/// - **边缘揭示**（指针停在视口左右边缘）；
/// - 揭示之后的**恢复**（离开一条未被激活的揭示，等一会儿回到 Reader）——
///   它的「进入」事件是「离开揭示」，用一个固定 id 复用同一个原语。
///
/// 三条纪律写在类型里而不是散在调用点：
///
/// 1. **到点只触发一次**。[takeDue] 取值时就把待发项清掉，所以指针一直停在那儿
///    也不会反复激活 —— 否则每一帧都重新聚焦，画面会持续横跳。
/// 2. **换了目标就重新计时**。在 A 停了一会儿再挪到 B，不能把在 A 攒的时间
///    算给 B（那会让 B 一进去就触发，看起来像「B 比 A 灵」）。
/// 3. **被抑制时一律不发**，并且**进入抑制的瞬间就把待发项清掉**。
///    契约要求「指针捕获 / 正在拖动 / 输入法组合 / 弹层 / 浮动菜单」期间既不许
///    揭示也不许自动恢复；等到抑制解除时，那次驻留早已作废，不该补发。
class WorkspaceDwell {
  String? _pendingId;
  int _deadlineMs = 0;
  bool _suppressed = false;

  /// 正在计时的目标；`null` = 没有计时。
  String? get pendingId => _pendingId;

  bool get isPending => _pendingId != null;

  bool get isSuppressed => _suppressed;

  /// 开始（或重新开始）对 [id] 的驻留计时。
  ///
  /// [delayMs] 必须为正：0 延时等于「一进入就触发」，指针扫过时画面会横跳，
  /// 那不是「更快」而是「更坏」。非法值按 1ms 处理，把它变成一个「几乎是立刻」
  /// 但仍然过一次事件循环的延时。
  void enter(String id, {required int nowMs, required int delayMs}) {
    if (_pendingId == id) return;
    _pendingId = id;
    _deadlineMs = nowMs + math.max(1, delayMs);
  }

  /// [id] 的目标已经离开：只有**正在计时的就是它**才取消。
  ///
  /// 这条「只取消自己」的判断不是洁癖：指针从 A 移到 B 时，浏览器/引擎会先发
  /// A 的离开再发 B 的进入（顺序不保证）。若离开事件无条件取消，B 的计时会被
  /// A 的离开顺手抹掉 —— 表现为「鼠标划过好几个泳道才能聚焦一个」。
  void leave(String id) {
    if (_pendingId == id) _pendingId = null;
  }

  void cancel() {
    _pendingId = null;
  }

  /// 抑制期间不许触发（也不许自动恢复）。进入抑制会立刻清掉待发项。
  void setSuppressed(bool value) {
    if (_suppressed == value) return;
    _suppressed = value;
    if (value) _pendingId = null;
  }

  /// 到点了吗。抑制期间恒为假。
  bool isDue(int nowMs) =>
      !_suppressed && _pendingId != null && nowMs >= _deadlineMs;

  /// 取走到点的目标并清空计时（于是**只触发一次**）。没到点返回 `null`。
  String? takeDue(int nowMs) {
    if (!isDue(nowMs)) return null;
    final id = _pendingId;
    _pendingId = null;
    return id;
  }

  /// 还剩多少毫秒到点（没在计时返回 `null`）。只用于让判据看清中间状态。
  int? remainingMs(int nowMs) =>
      _pendingId == null ? null : math.max(0, _deadlineMs - nowMs);
}
