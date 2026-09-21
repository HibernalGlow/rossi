import 'dart:math' as math;

// 本文件**刻意不 import Flutter / dart:ui**：唤出区的夹取、镜像、命中与四角缩放
// 全是纯算术，判据要能 `dart run test/workspace/reveal_zones_check.dart` 直接断言
// （本机 `flutter test` 起不来，凡是能从 widget 里抽出来的判据都抽到这里来验）。
// 同一份纪律见 `workspace_layout_config.dart` / `workspace_strip_metrics.dart` 顶部。

/// 一块唤出区属于视口的哪条边。
///
/// 四条边各自独立可编辑，但**语义不是一类东西**：左右两条喂给泳道的「驻留揭示
/// 相邻泳道」，上下两条喂给顶栏与阅读器底栏的悬停唤出。把它们收进同一个模型，
/// 是因为它们在**用户眼里是同一件事**（「鼠标停在哪一块地方会把东西调出来」），
/// 而且共享同一套几何操作（画框、四角缩放、跨轴镜像）。
enum RevealEdge {
  left,
  right,
  top,
  bottom;

  static RevealEdge? tryParse(Object? value) {
    for (final edge in RevealEdge.values) {
      if (edge.name == value) return edge;
    }
    return null;
  }
}

/// 矩形四角 —— 拖拽缩放手柄的位置。
enum RevealCorner {
  nw,
  ne,
  sw,
  se;

  bool get isNorth => this == nw || this == ne;

  bool get isWest => this == nw || this == sw;
}

/// 把任意百分比夹进 `[0, 99]` 并**四舍五入到 0.1**。
///
/// 上限是 99 而不是 100：原点（x / y）留 1% 的余量，好让「宽 / 高最小 1%」
/// 这条下限永远有解 —— 允许 x=100 时，任何宽度都会越界，界面上表现为
/// 数值框里填得进去、松手却弹回别处。
double clampRevealPercent(double value) {
  // NaN 只能来自「0 除以 0」这类已经坏掉的输入，回 0（贴边）比往下传安全；
  // ±Infinity 却是**指针拖出画布**的正常结果，该贴着边界停住。
  if (value.isNaN) return 0;
  return (math.min(RevealZoneLimits.maxOrigin, math.max(0, value)) * 10)
          .round() /
      10;
}

/// 唤出区的取值边界（与 neoview 的 `revealZone` 校验一致）。
abstract final class RevealZoneLimits {
  static const double minExtent = 1;
  static const double maxOrigin = 99;
  static const double maxExtent = 100;
}

/// 一块**归一化**的矩形：单位是「视口宽 / 视口高的百分比」，不是像素。
///
/// 用百分比而不是像素是刻意的：唤出区要回答的问题是「指针离这条边**多远**算贴边」，
/// 而窗口一改尺寸，像素值就得跟着改。百分比让「调好一次、任意窗口大小都成立」
/// 成为默认，也让镜像（[mirror]）是「100 - x - width」这种一眼能验的算术。
class WorkspaceRevealZone {
  final double x;
  final double y;
  final double width;
  final double height;

  const WorkspaceRevealZone({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  double get right => x + width;

  double get bottom => y + height;

  WorkspaceRevealZone copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
  }) {
    return WorkspaceRevealZone(
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }

  /// 夹成一块**合法**的矩形：原点在 0..99，宽高至少 1 且不超过右 / 下边界。
  ///
  /// 这是所有写入口的必经之地（拖拽、四角缩放、数值框、读盘）。少夹一次，
  /// 非法值就会存进磁盘，而下次启动读到的就是一个画不出来的矩形。
  WorkspaceRevealZone clamped() {
    final nx = clampRevealPercent(x);
    final ny = clampRevealPercent(y);
    return WorkspaceRevealZone(
      x: nx,
      y: ny,
      width: clampRevealPercent(
        math.min(
          RevealZoneLimits.maxExtent - nx,
          math.max(RevealZoneLimits.minExtent, width),
        ),
      ),
      height: clampRevealPercent(
        math.min(
          RevealZoneLimits.maxExtent - ny,
          math.max(RevealZoneLimits.minExtent, height),
        ),
      ),
    );
  }

  /// 百分比坐标是否落在这块矩形里。
  bool contains(double xPercent, double yPercent) =>
      xPercent >= x && xPercent <= right && yPercent >= y && yPercent <= bottom;

  /// 沿某条轴**镜像**到对侧：贴边方向反过来，其余尺寸不变。
  ///
  /// 「左右联动」与「上下联动」就是它 —— 一条边调好的手感直接复制到对侧，
  /// 用户不必把同一个数字输入两遍。
  WorkspaceRevealZone mirrored({required bool horizontal}) {
    return horizontal
        ? copyWith(x: math.max(0, 100 - x - width)).clamped()
        : copyWith(y: math.max(0, 100 - y - height)).clamped();
  }

  /// 换算成像素矩形（[viewportWidth] / [viewportHeight] 是这块区域自己的尺寸）。
  ({double left, double top, double width, double height}) toPixels({
    required double viewportWidth,
    required double viewportHeight,
  }) {
    return (
      left: x / 100 * viewportWidth,
      top: y / 100 * viewportHeight,
      width: width / 100 * viewportWidth,
      height: height / 100 * viewportHeight,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };

  /// 从 JSON 还原：**四项各自**兜底，坏一项退回该项默认值。
  ///
  /// 与 `WorkspaceInteractionSettings.fromJson` 同一条纪律 —— 配置文件被手改坏
  /// 一个数字，不该让整块唤出区回到出厂。
  factory WorkspaceRevealZone.fromJson(
    Object? json, {
    required WorkspaceRevealZone fallback,
  }) {
    if (json is! Map) return fallback;
    final raw = json.cast<String, Object?>();
    return WorkspaceRevealZone(
      x: _percent(raw['x'], fallback.x),
      y: _percent(raw['y'], fallback.y),
      width: _percent(raw['width'], fallback.width),
      height: _percent(raw['height'], fallback.height),
    ).clamped();
  }

  static double _percent(Object? value, double fallback) {
    if (value is! num) return fallback;
    if (!value.isFinite) return fallback;
    return value.toDouble();
  }

  @override
  bool operator ==(Object other) =>
      other is WorkspaceRevealZone &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(x, y, width, height);

  @override
  String toString() =>
      'WorkspaceRevealZone(x: $x, y: $y, w: $width, h: $height)';
}

/// 拖拽画出的新矩形：两个对角点，与拖动的方向无关。
///
/// 宽 / 高至少 1%（[RevealZoneLimits.minExtent]）：一个零面积的唤出区
/// 永远命中不了，界面上却仍然占着一个选中态，用户会以为它坏了。
WorkspaceRevealZone drawnRevealZone({
  required double fromX,
  required double fromY,
  required double toX,
  required double toY,
}) {
  final x = math.min(fromX, toX);
  final y = math.min(fromY, toY);
  return WorkspaceRevealZone(
    x: x,
    y: y,
    width: math.max(RevealZoneLimits.minExtent, (toX - fromX).abs()),
    height: math.max(RevealZoneLimits.minExtent, (toY - fromY).abs()),
  ).clamped();
}

/// 拖动某个角得到的新矩形：**对角固定**，被拖的那个角跟着指针走。
WorkspaceRevealZone resizedRevealZone({
  required WorkspaceRevealZone zone,
  required RevealCorner corner,
  required double xPercent,
  required double yPercent,
}) {
  final right = zone.right;
  final bottom = zone.bottom;
  final x = corner.isWest ? math.min(xPercent, right - 1) : zone.x;
  final y = corner.isNorth ? math.min(yPercent, bottom - 1) : zone.y;
  final nextRight = corner.isWest ? right : math.max(xPercent, x + 1);
  final nextBottom = corner.isNorth ? bottom : math.max(yPercent, y + 1);
  return WorkspaceRevealZone(
    x: clampRevealPercent(x),
    y: clampRevealPercent(y),
    width: math.max(
      RevealZoneLimits.minExtent,
      math.min(100 - x, nextRight - x),
    ),
    height: math.max(
      RevealZoneLimits.minExtent,
      math.min(100 - y, nextBottom - y),
    ),
  ).clamped();
}

/// 改一条边，并按「联动」把对侧一起改掉。
///
/// 联动**只是编辑期的镜像**，不是持久化项：存下来的永远是四条各自完整的矩形。
/// 把它做成纯函数而不是 widget 里的一段 if，是因为「左右联动时改左会不会把右
/// 挤到画外」这类问题只有在这里才能一次断言干净。
WorkspaceRevealZones updateRevealZonesWithLink({
  required WorkspaceRevealZones zones,
  required RevealEdge edge,
  required WorkspaceRevealZone zone,
  required bool horizontalLinked,
  required bool verticalLinked,
}) {
  final next = zones.withZone(edge, zone);
  final horizontal = edge == RevealEdge.left || edge == RevealEdge.right;
  if (horizontal && horizontalLinked) {
    final mirrorEdge = edge == RevealEdge.left
        ? RevealEdge.right
        : RevealEdge.left;
    return next.withZone(mirrorEdge, next[edge].mirrored(horizontal: true));
  }
  if (!horizontal && verticalLinked) {
    final mirrorEdge = edge == RevealEdge.top
        ? RevealEdge.bottom
        : RevealEdge.top;
    return next.withZone(mirrorEdge, next[edge].mirrored(horizontal: false));
  }
  return next;
}

/// 视口四条边的唤出区。
class WorkspaceRevealZones {
  final WorkspaceRevealZone left;
  final WorkspaceRevealZone right;
  final WorkspaceRevealZone top;
  final WorkspaceRevealZone bottom;

  const WorkspaceRevealZones({
    required this.left,
    required this.right,
    required this.top,
    required this.bottom,
  });

  /// 出厂值：四条**又窄又长**的贴边带。
  ///
  /// 窄（1%）是为了不挡正常操作，长（80%）是为了「沿这条边随便找个位置都能
  /// 调出东西」。上下两条左右各留 10%，是因为两角与左右两条带重叠时，
  /// 命中判定要说清谁赢（见 [edgeAt] 的顺序）。
  static const WorkspaceRevealZones defaults = WorkspaceRevealZones(
    left: WorkspaceRevealZone(x: 0, y: 10, width: 1, height: 80),
    right: WorkspaceRevealZone(x: 99, y: 10, width: 1, height: 80),
    top: WorkspaceRevealZone(x: 10, y: 0, width: 80, height: 1),
    bottom: WorkspaceRevealZone(x: 10, y: 99, width: 80, height: 1),
  );

  WorkspaceRevealZone operator [](RevealEdge edge) => switch (edge) {
    RevealEdge.left => left,
    RevealEdge.right => right,
    RevealEdge.top => top,
    RevealEdge.bottom => bottom,
  };

  WorkspaceRevealZones withZone(RevealEdge edge, WorkspaceRevealZone zone) {
    final clamped = zone.clamped();
    return switch (edge) {
      RevealEdge.left => copyWith(left: clamped),
      RevealEdge.right => copyWith(right: clamped),
      RevealEdge.top => copyWith(top: clamped),
      RevealEdge.bottom => copyWith(bottom: clamped),
    };
  }

  WorkspaceRevealZones copyWith({
    WorkspaceRevealZone? left,
    WorkspaceRevealZone? right,
    WorkspaceRevealZone? top,
    WorkspaceRevealZone? bottom,
  }) {
    return WorkspaceRevealZones(
      left: left ?? this.left,
      right: right ?? this.right,
      top: top ?? this.top,
      bottom: bottom ?? this.bottom,
    );
  }

  /// 百分比坐标落在哪条边的唤出区里。
  ///
  /// 重叠时按 **左右 → 上下** 的顺序判：左右两条管的是「换泳道」，是更明确的
  /// 意图；顶栏与底栏在任何指针位置都还能靠剩下的边沿召出来。
  /// 这个顺序必须写在一处并被判据钉住 —— 两处各写一遍必然分叉。
  RevealEdge? edgeAt({required double xPercent, required double yPercent}) {
    for (final edge in const [
      RevealEdge.left,
      RevealEdge.right,
      RevealEdge.top,
      RevealEdge.bottom,
    ]) {
      if (this[edge].contains(xPercent, yPercent)) return edge;
    }
    return null;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'left': left.toJson(),
    'right': right.toJson(),
    'top': top.toJson(),
    'bottom': bottom.toJson(),
  };

  /// 从 JSON 还原：**一条边坏掉只影响那一条边**。
  factory WorkspaceRevealZones.fromJson(Object? json) {
    if (json is! Map) return defaults;
    final raw = json.cast<String, Object?>();
    return WorkspaceRevealZones(
      left: WorkspaceRevealZone.fromJson(raw['left'], fallback: defaults.left),
      right: WorkspaceRevealZone.fromJson(
        raw['right'],
        fallback: defaults.right,
      ),
      top: WorkspaceRevealZone.fromJson(raw['top'], fallback: defaults.top),
      bottom: WorkspaceRevealZone.fromJson(
        raw['bottom'],
        fallback: defaults.bottom,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WorkspaceRevealZones &&
      other.left == left &&
      other.right == right &&
      other.top == top &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, right, top, bottom);
}
