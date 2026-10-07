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
///
/// 第四条是这一轮加的：**指针还在动就不算驻留**（[noteMotion] 一直推后到期点，
/// [settleMs] 静够之后才开始走 `delay` 那一段）。它换掉的口径是「进入即计时」——
/// 那个口径下延时一个人要干两件事（别误触 + 给反应时间），于是只能取很大的值，
/// 而真停住的人也一起等满它。
class WorkspaceDwell {
  String? _pendingId;
  int _armedMs = 0;
  int _deadlineMs = 0;
  int _delayMs = 0;
  bool _suppressed = false;

  /// 「停住」的判定窗口（毫秒）—— 最后一次指针运动之后要静多久，计时才开始走。
  ///
  /// 这条不是第四个旋钮，是**内部常量**：用户只需要回答「停住之后还要不要再等一下」
  /// （`hoverFocusDelayMs`），而「什么叫停住」不该由他对着表调。
  ///
  /// 为什么要有它：以前的计时是「进入即开始」，于是延时同时承担了两件事 ——
  /// 一是别把「路过」当成「要看这里」，二是给用户一点反应时间。一件事两个职责的结果
  /// 就是那个数必须很大（420ms）才不误触，而真停下来的人也得等满它，
  /// 主观感受是「移过去先卡一下，然后一起动」。拆开之后：路过由 [noteMotion]
  /// 不断推后到期点，永远轮不到触发；真停住的人只等 `settle + delay`。
  static const int settleMs = 60;

  /// 正在计时的目标；`null` = 没有计时。
  String? get pendingId => _pendingId;

  bool get isPending => _pendingId != null;

  bool get isSuppressed => _suppressed;

  /// 开始（或重新开始）对 [id] 的驻留计时。
  ///
  /// 到期点 = `nowMs + settleMs + delayMs`：先静够 [settleMs]（「确实停住了」），
  /// 再等 [delayMs]（「停住之后还要不要再看一会儿」）。
  ///
  /// [delayMs] 必须为正：0 延时等于「一停就触发」，指针扫过时画面会横跳，
  /// 那不是「更快」而是「更坏」。非法值按 1ms 处理，把它变成一个「几乎是立刻」
  /// 但仍然过一次事件循环的延时。
  void enter(
    String id, {
    required int nowMs,
    required int delayMs,
  }) {
    if (_pendingId == id) return;
    _pendingId = id;
    _delayMs = math.max(1, delayMs);
    _retime(nowMs);
  }

  /// 指针**又动了**：把到期点整体推后（先重新静够 `settle`，再等满 `delay`）。
  ///
  /// 只在有待发项时起作用，也不改目标 —— 目标换了是 [enter] 的事，
  /// 那条路径要**重新计时**（契约：换了目标不能把在上一条泳道攒的时间算给它）。
  void noteMotion(int nowMs) {
    if (_pendingId == null) return;
    _retime(nowMs);
  }

  void _retime(int nowMs) {
    _armedMs = nowMs + WorkspaceDwell.settleMs;
    _deadlineMs = _armedMs + _delayMs;
  }

  /// 已经「确实停住」了、正在等 `delay` 走完 —— 给界面一个**预备态**的落点。
  ///
  /// 这一档存在的意义是把手感里那 200 来毫秒变成「有回应」而不是「没反应」：
  /// 泳道先以边框表明「系统看见我停在这儿了」，稍后交互才真的交出来。
  /// 路过时永远走不到这里（运动一直把 [isArmed] 往后推），所以它不会闪。
  bool isArmed(int nowMs) =>
      !_suppressed && _pendingId != null && nowMs >= _armedMs;

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
