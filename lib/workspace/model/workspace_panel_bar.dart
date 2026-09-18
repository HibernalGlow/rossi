import 'dart:math' as math;

// 本文件**刻意不 import Flutter**（不 import `dart:ui`）：它要能 JSON 往返
// （持久化判据）并被 `dart run test/workspace/panel_bar_check.dart` 直接断言。
// 所以下面用的是自己的一小块矩形，而不是 `dart:ui` 的 `Rect`。

/// 面板操作栏的**停靠模式**（neoview `panelBarMode`）。
enum PanelBarMode {
  /// 钉在泳道的某条边上。
  pinned,

  /// 悬浮在某个相对位置上（自己带 x/y 百分比）。
  floating;

  static PanelBarMode parse(Object? value) =>
      value == 'floating' ? PanelBarMode.floating : PanelBarMode.pinned;

  String get wireName => name;
}

/// 面板操作栏钉在泳道的哪条边（neoview `panelBarDock`）。
enum PanelBarDock {
  left,
  right,
  top,
  bottom;

  /// 横向排布（顶 / 底）；纵向时页签条是竖轨。
  bool get isHorizontal => this == top || this == bottom;

  static PanelBarDock parse(Object? value, {required PanelBarDock fallback}) {
    for (final dock in PanelBarDock.values) {
      if (dock.name == value) return dock;
    }
    return fallback;
  }

  /// 泳道左右两条泳道的**默认**停靠点。
  ///
  /// neoview 的默认值是「自己那条边」（左泳道钉左、右泳道钉右，于是页签条是一根
  /// 贴边的**竖轨**）。Rossi 这里**有意不同**：默认钉在**顶部**，因为本项目的
  /// 面板页签一直长在泳道栏头里（`SwimlaneColumn` 的 `panelTabs`），
  /// 而且栏头那一条已经有标题/宽度/独占/折叠 —— 把页签塞在同一个横条里
  /// 才不额外占掉泳道的一整列宽度。改成竖轨是**用户拖得出来的**，
  /// 不该是升级后被迫接受的新版式。
  static PanelBarDock defaultDock() => PanelBarDock.top;
}

/// 一块矩形（只用于「面板栏能呆在哪儿」这一类几何，避免把 `dart:ui` 拖进来）。
class PanelBarBounds {
  final double left;
  final double top;
  final double width;
  final double height;

  const PanelBarBounds({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  double get right => left + width;
  double get bottom => top + height;

  bool containsPoint(double x, double y) =>
      x >= left && x <= right && y >= top && y <= bottom;
}

/// 面板操作栏的**布局记账**（neoview `panelBarMode` / `panelBarDock` /
/// `panelBarPositionX` / `panelBarPositionY` / `panelBarConstrained` 五项合一）。
///
/// 为什么四项要一起改：它们是**一次手势的两种结局**。把面板栏拖到泳道边上松手
/// → 变成「钉在那条边」；拖到泳道中间松手 → 变成「悬浮在这个位置」。
/// 分两次写账（先改模式再改位置）会让中间态被渲染出来 —— 用户会看到它
/// 先在旧位置闪一下、再跳到新位置。
class PanelBarLayout {
  final PanelBarMode mode;

  /// 钉在泳道的哪条边。
  ///
  /// 悬浮态下它**仍然有意义**：它是「钉回去该钉在哪条边」的记录
  /// （neoview 转悬浮时把当时的 dock 一起写回）。所以悬浮 + 任意停靠边
  /// 都是**合法**组合 —— 把它当非法值改写成别的，等于悄悄弄丢用户的选择。
  final PanelBarDock dock;

  /// 悬浮时的中心点，**按容器宽高的百分比**记（0–100）。
  ///
  /// 百分比而不是像素：泳道宽度是会被拖的、窗口也会改，记死像素的话
  /// 「上次把它放在中间」在换个窗口大小之后就不再是中间，甚至跑到泳道外面。
  final double positionX;
  final double positionY;

  /// 是否把它**限制在本泳道内**（neoview `panelBarConstrained`，默认 true）。
  ///
  /// 关掉之后它可以被拖到窗口的任何地方 —— 于是它就不再是「这条泳道的东西」，
  /// 而是工作台级别的浮层（契约里这是用户显式的选择，必须能持久化）。
  final bool constrained;

  const PanelBarLayout({
    this.mode = PanelBarMode.pinned,
    PanelBarDock? dock,
    this.positionX = 50,
    this.positionY = 50,
    this.constrained = true,
  }) : dock = dock ?? PanelBarDock.top;

  PanelBarLayout copyWith({
    PanelBarMode? mode,
    PanelBarDock? dock,
    double? positionX,
    double? positionY,
    bool? constrained,
  }) {
    return PanelBarLayout(
      mode: mode ?? this.mode,
      dock: dock ?? this.dock,
      positionX: positionX ?? this.positionX,
      positionY: positionY ?? this.positionY,
      constrained: constrained ?? this.constrained,
    );
  }

  /// 钉在顶上的**并且没在拖动**时，页签条被挂进泳道栏头（neoview `titleMounted`）。
  /// 只有这一档不额外占位、也不画自己的底板。
  bool get isTitleMounted =>
      mode == PanelBarMode.pinned && dock == PanelBarDock.top;

  Map<String, Object?> toJson() => <String, Object?>{
    'mode': mode.wireName,
    'dock': dock.name,
    'positionX': positionX,
    'positionY': positionY,
    'constrained': constrained,
  };

  factory PanelBarLayout.fromJson(Map<String, Object?> json) {
    return PanelBarLayout(
      mode: PanelBarMode.parse(json['mode']),
      dock: PanelBarDock.parse(
        json['dock'],
        fallback: PanelBarDock.defaultDock(),
      ),
      positionX: _clampPercent(json['positionX'], 50),
      positionY: _clampPercent(json['positionY'], 50),
      constrained: json['constrained'] is bool
          ? json['constrained']! as bool
          : true,
    );
  }

  static double _clampPercent(Object? value, double fallback) {
    if (value is! num) return fallback;
    return value.toDouble().clamp(0, 100).toDouble();
  }

  @override
  bool operator ==(Object other) =>
      other is PanelBarLayout &&
      other.mode == mode &&
      other.dock == dock &&
      other.positionX == positionX &&
      other.positionY == positionY &&
      other.constrained == constrained;

  @override
  int get hashCode =>
      Object.hash(mode, dock, positionX, positionY, constrained);
}

/// 拖动面板栏时「钉到哪条边」的判定（neoview `dockCandidate`）。
///
/// 规则：松手点必须在泳道内；到四条边的距离里取最小的那条，
/// 且必须**近到一定程度**（[threshold]）。不够近就返回 `null` ——
/// `null` 的含义是「不是要换停靠点」，调用方据此把它转成**悬浮**。
/// 这条「够近才算」的阈值是必须的：没有它，任何一次拖动都会把面板栏吸到最近那条边，
/// 用户永远拖不出悬浮态。
PanelBarDock? panelBarDockCandidate({
  required PanelBarBounds lane,
  required double x,
  required double y,
  double threshold = panelBarDockThreshold,
}) {
  if (!lane.containsPoint(x, y)) return null;
  final distances = <PanelBarDock, double>{
    PanelBarDock.left: x - lane.left,
    PanelBarDock.right: lane.right - x,
    PanelBarDock.top: y - lane.top,
    PanelBarDock.bottom: lane.bottom - y,
  };
  var best = PanelBarDock.left;
  var bestDistance = double.infinity;
  for (final dock in PanelBarDock.values) {
    final distance = distances[dock]!;
    if (distance < bestDistance) {
      bestDistance = distance;
      best = dock;
    }
  }
  return bestDistance <= threshold ? best : null;
}

/// 换停靠点的吸附距离（neoview `DOCK_THRESHOLD = 64`）。
const double panelBarDockThreshold = 64;

/// 悬浮位置：把「中心点百分比」翻译成容器内的左上角像素，并夹进容器。
///
/// 语义取自 neoview 的 `barStyle`：`left: p%` 配合 `translate(-50%, -50%)`，
/// 也就是**浮层的中心落在容器的 p% 处**。注意它**不等于** Flutter 的
/// `Align`：`Align` 是「把子节点的左边缘从容器左边扫到右边」，中心会随尺寸漂。
/// 两者在 50% 处重合，在 10% / 90% 处差半个浮层宽 —— 那是肉眼可见的错位，
/// 所以这里按 CSS 的语义写清楚，并由 widget 侧原样调用。
///
/// 夹取必须做在**这里**（而不是等布局阶段越界）：越界的浮层会被 `Stack` 裁掉，
/// 用户看到的是「拖到边上就少了一半」。严格说夹取只该在 `constrained` 时做；
/// 不约束时容器就是整个视口，由调用方把视口矩形传进来即可 ——
/// 于是两支走的是同一段算术。
({double left, double top}) panelBarFloatingOffset({
  required PanelBarBounds bounds,
  required double positionX,
  required double positionY,
  required double barWidth,
  required double barHeight,
}) {
  final centerX = bounds.left + bounds.width * positionX / 100;
  final centerY = bounds.top + bounds.height * positionY / 100;
  final maxLeft = math.max(bounds.left, bounds.right - barWidth);
  final maxTop = math.max(bounds.top, bounds.bottom - barHeight);
  return (
    left: (centerX - barWidth / 2).clamp(bounds.left, maxLeft).toDouble(),
    top: (centerY - barHeight / 2).clamp(bounds.top, maxTop).toDouble(),
  );
}

/// 把左上角像素换算回中心点百分比（松手时写账用）。
({double x, double y}) panelBarPercentFromOffset({
  required PanelBarBounds bounds,
  required double left,
  required double top,
  required double barWidth,
  required double barHeight,
}) {
  double percent(double value, double total) {
    if (total <= 0) return 50;
    return (value / total * 100).clamp(0, 100).toDouble();
  }

  return (
    x: percent(left + barWidth / 2 - bounds.left, bounds.width),
    y: percent(top + barHeight / 2 - bounds.top, bounds.height),
  );
}
