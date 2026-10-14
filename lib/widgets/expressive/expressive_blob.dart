import 'dart:math' as math;

import 'package:material_new_shapes/material_new_shapes.dart';
import 'package:material_ui/material_ui.dart';

/// **按种子生成**的不规则圆角轮廓 —— MD3 Expressive 的「形状即状态」。
///
/// # 为什么不是「从表里挑一个」
///
/// 需求是「随机的不规则图形，不要写死」。写死的清单（这颗用 fan、那颗用 gem）
/// 只有几档可用，新增一档列表就得有人再挑一次；这里要的是**同一个生成入口**
/// 产出一片各不相同的形状。所以形状由 `seed` 决定：
///
/// * 边上点的有无与位置、每条边的内缩深度、每颗角的半径与连续曲率，
///   全部来自 `Random(seed)` 的一次走查；
/// * 同一个 seed 永远得到同一个形状（切回来不重排、热重载不跳形），
///   换一颗 seed 就换一个形状；
/// * 形状不来自任何固定枚举，所以新增一档列表不需要任何人再挑。
///
/// # 与 M3 Expressive 规范的对齐（逐条出处）
///
/// 摘要见本仓 skill `.agents/skills/material3-expressive-flutter/references/shape-guide.md`
/// 与 `rules/shape-morphing.md`：
///
/// 1. **角半径只取规范令牌**：`extra-small 4dp / small 8dp / medium 12dp`
///    （chip 一档规范给的就是 `small`；`none` 只作稀疏的「张力角」，
///    规范原文是 sharp corners sparingly）。这里用「占形状单位的比例」表达，
///    见 [_BlobPlan.kCornerTokens]：单位 = 40dp 时正好是 0 / 4 / 8 / 12dp。
/// 2. **连续曲率**：每颗角带 `smoothing ∈ [0.55, 1]`，即规范要的 squircle /
///    organic feel，而不是纯圆弧。
/// 3. **只在盒子内侧变形**：所有扰动都是**内缩**，轮廓不越出自己的矩形
///    （越界会压到相邻 chip，也会被祖先的 clip 切掉）。
/// 4. **选中态收成 stadium**：规范原文「Active states in navigation should
///    always use a pill/stadium shape」，所以 `progress = 1` 是胶囊；
///    未选中保留不规则，悬停落在两者之间。
/// 5. **流体变形**：rest 与 taut 两档**节点数与顺序逐点对应**，中间态由这两个
///    端点逐点插值得到 —— 不需要 `Morph` 的通用匹配，也就不会跳形。
///
/// # 尺度：形状按控件高度生成，变形量按文字安全区封顶
///
/// 多边形生成在 `y ∈ [0,1]`、`x ∈ [0, 宽高比]` 的空间里，出图时**等比**乘以控件
/// 高度 —— 于是角半径的「比例」就是真实 dp，胶囊端头是真正的半圆。控件越高
/// （字号放大）就把**不规则那一档**的变形量按比例缩一点（`restScale`，见
/// [ExpressiveBlob.path]），保证「最大角扫掠 ≤ safeInset」永远成立。
/// 这条不变量就是「文字不会被轮廓啃掉」的全部内容：形状只是不再那么夸张，
/// 而不是把标签切一半。若像 `ExpressiveMorphBorder` 那样把单位正方形
/// **非等比**拉成控件矩形，一颗 12dp 的圆角在宽 chip 上会被拉成几十 dp 宽的
/// 扁椭圆，正好啃掉文字区。
class ExpressiveBlob {
  ExpressiveBlob.ofSeed(this.seed) : _plan = _planOf(seed);

  final int seed;
  final _BlobPlan _plan;

  /// 变形里最深的那一档（最大角令牌），用来把不规则那一档封顶。
  static const double _kMaxDeformation = _BlobPlan.kMaxRadiusFraction;

  static final _plans = <int, _BlobPlan>{};

  static _BlobPlan _planOf(int seed) {
    final plan = _plans.putIfAbsent(seed, () => _BlobPlan.generate(seed));
    // 一档列表一颗形状；上限只是防止长会话里攒出几千条（Map 保持插入序）。
    if (_plans.length > 512) _plans.remove(_plans.keys.first);
    return plan;
  }

  /// 控件矩形 [rect] 上、进度 [progress]（0 不规则 → 1 胶囊）的那条轮廓。
  ///
  /// [safeInset] 是调用方给文字留的内缩（dp）：轮廓的任何一处变形都不会越过
  /// 这个距离，所以标签框一定整块在形状里。
  Path path({
    required Rect rect,
    required double progress,
    double safeInset = 11,
  }) {
    if (rect.isEmpty) return Path();
    final taut = progress.clamp(0.0, 1.0);
    // 不规则那一档的变形量按文字安全区封顶：控件越高（字号放大）比例越小，
    // 于是形状只是「不再那么夸张」，而不是把标签切一半。
    // 注意封顶只作用于 rest，`taut=1` 的胶囊帽仍然是半高 —— 规范要的就是
    // stadium，而半圆帽在竖直中线处正好贴到 x=0，文字带永远在里面。
    final restScale = math.min(
      1.0,
      safeInset / (_kMaxDeformation * rect.height),
    );
    final aspect = rect.width / rect.height;
    final polygon = _plan.polygon(
      taut: taut,
      aspect: aspect,
      restScale: restScale,
    );
    final toRect = Matrix4.identity()
      ..translateByDouble(rect.left, rect.top, 0, 1)
      ..scaleByDouble(rect.height, rect.height, 1, 1);
    return polygon.toPath().transform(toRect.storage);
  }
}

/// 盒子上的一颗节点：角（[onEdge] 为 false）或边上点（true）。
class _BlobNode {
  const _BlobNode({
    required this.edge,
    required this.onEdge,
    required this.tween,
    required this.dent,
    required this.restRadius,
    required this.restSmoothing,
  });

  /// 挂在「第 edge 条边的起点」还是「第 edge 条边之中」。
  final int edge;
  final bool onEdge;

  /// 边上点在这条边上的位置（0..1）。
  final double tween;

  /// 边上点朝圆心内缩多少（占单位比例）。角恒为 0。
  final double dent;

  /// 不规则那一档的半径（占单位比例）与连续曲率。
  final double restRadius;
  final double restSmoothing;
}

class _BlobPlan {
  _BlobPlan._(this.nodes);

  final List<_BlobNode> nodes;

  /// M3 Expressive 角令牌：单位 = 40dp 时正好是 0 / 4 / 8 / 12dp。
  static const List<double> kCornerTokens = [0.0, 0.10, 0.20, 0.30];

  /// 令牌上界，供 [ExpressiveBlob.path] 给不规则那一档封顶。边上点的内缩上界
  /// 是 0.17，比它小，所以封顶由角令牌决定 —— 改深内缩时别忘了这条。
  static const double kMaxRadiusFraction = 0.30;

  static _BlobPlan generate(int seed) {
    final rng = math.Random(seed);
    final nodes = <_BlobNode>[];
    for (var edge = 0; edge < 4; edge++) {
      nodes.add(
        _BlobNode(
          edge: edge,
          onEdge: false,
          tween: 0,
          dent: 0,
          restRadius: _pickRadius(rng),
          restSmoothing: 0.55 + rng.nextDouble() * 0.45,
        ),
      );
      // 每条边至多一颗边上点，约六成概率有。它把那条边往里拽一点，轮廓就不
      // 再是对称矩形 —— 而四角一定存在，「容器」的读感不丢。
      if (rng.nextDouble() < 0.62) {
        nodes.add(
          _BlobNode(
            edge: edge,
            onEdge: true,
            tween: 0.26 + rng.nextDouble() * 0.48,
            dent: 0.09 + rng.nextDouble() * 0.08,
            restRadius: 0.04 + rng.nextDouble() * 0.06,
            restSmoothing: 0.8,
          ),
        );
      }
    }
    return _BlobPlan._(nodes);
  }

  /// 角令牌抽样：`none` 只给约七分之一的角，其余在 4 / 8 / 12dp 里挑。
  static double _pickRadius(math.Random rng) {
    if (rng.nextDouble() < 0.14) return kCornerTokens[0];
    return kCornerTokens[1 + rng.nextInt(kCornerTokens.length - 1)];
  }

  /// taut=0 → 不规则原形，taut=1 → 收成胶囊（四角半径都到半单位高）。
  /// 两档节点数与顺序相同，所以中间态是**逐点线性插值**，不需要通用匹配。
  RoundedPolygon polygon({
    required double taut,
    required double aspect,
    double restScale = 1.0,
  }) {
    final vertices = <double>[];
    final rounding = <CornerRounding>[];
    // 胶囊那一档的半径不能超过半边长，否则窄控件上四段弧会互相重叠。
    final tautRadius = math.min(0.5, aspect / 2);
    for (final node in nodes) {
      final from = _corner(node.edge, aspect);
      final to = _corner(node.edge + 1, aspect);
      final restRadius = node.restRadius * restScale;
      final radius = restRadius + (tautRadius - restRadius) * taut;
      final smoothing = node.restSmoothing + (1.0 - node.restSmoothing) * taut;
      if (node.onEdge) {
        final point = Offset.lerp(from, to, node.tween)!;
        final inward = _towardCenter(aspect, point);
        final depth = node.dent * restScale * (1 - taut);
        vertices
          ..add(point.dx + inward.dx * depth)
          ..add(point.dy + inward.dy * depth);
      } else {
        vertices
          ..add(from.dx)
          ..add(from.dy);
      }
      rounding.add(CornerRounding(radius: radius, smoothing: smoothing));
    }
    return RoundedPolygon.fromVertices(
      vertices,
      perVertexRounding: rounding,
      centerX: aspect / 2,
      centerY: 0.5,
    );
  }

  /// 四个盒子角在「单位空间」里的位置（横向按宽高比走）。绕序与
  /// `RoundedPolygon.rectangle` 一致：右下 → 左下 → 左上 → 右上。
  static Offset _corner(int index, double aspect) => switch (index % 4) {
    0 => Offset(aspect, 1),
    1 => const Offset(0, 1),
    2 => Offset.zero,
    _ => Offset(aspect, 0),
  };

  static Offset _towardCenter(double aspect, Offset p) {
    final v = Offset(aspect / 2 - p.dx, 0.5 - p.dy);
    final len = v.distance;
    return len < 1e-6 ? const Offset(0, -1) : v / len;
  }
}

/// 由稳定标识（列表路径 / 名称）算出的种子。
///
/// 不用 `String.hashCode`：Dart 不承诺它跨编译稳定，AOT/JIT 或换版本就会让
/// 每一档的形状整体重排。FNV-1a 逐码元算，任何 VM 上都是同一个数。
int expressiveBlobSeed(String identity) {
  var hash = 0xcbf29ce484222325;
  const prime = 0x100000001b3;
  for (final unit in identity.codeUnits) {
    hash = ((hash ^ unit) * prime) & 0x7fffffffffffffff;
  }
  return hash;
}

/// [ExpressiveBlob] 的 `OutlinedBorder` 外壳，给 `Chip` / `Material` 用。
class ExpressiveBlobBorder extends OutlinedBorder {
  const ExpressiveBlobBorder({
    required this.seed,
    this.progress = 0,
    this.safeInset = 11,
    super.side,
  });

  final int seed;

  /// 0 = 不规则原形，1 = 收成胶囊。由外部弹簧驱动；悬停过冲会越过 1，
  /// 那里按 1 收 —— 过冲由缩放那一层表达，轮廓不跟着抖。
  final double progress;

  /// 文字安全区（dp）：见 [ExpressiveBlob.path]，这是「轮廓不啃字」的全部依据。
  final double safeInset;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  ExpressiveBlobBorder copyWith({BorderSide? side, double? progress}) =>
      ExpressiveBlobBorder(
        seed: seed,
        progress: progress ?? this.progress,
        safeInset: safeInset,
        side: side ?? this.side,
      );

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      ExpressiveBlob.ofSeed(
        seed,
      ).path(rect: rect, progress: progress, safeInset: safeInset);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect.deflate(side.width), textDirection: textDirection);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width <= 0) return;
    canvas.drawPath(getOuterPath(rect.deflate(side.width / 2)), side.toPaint());
  }

  @override
  ShapeBorder lerpFrom(ShapeBorder? a, double t) {
    if (a is ExpressiveBlobBorder && a.seed == seed) {
      return ExpressiveBlobBorder(
        seed: seed,
        progress: a.progress + (progress - a.progress) * t,
        safeInset: safeInset,
        side: BorderSide.lerp(a.side, side, t),
      );
    }
    // 不是同一种形状就没有「插值」可言：交回默认实现，拿不到结果时落在这颗上。
    return ShapeBorder.lerp(a, this, t) ?? this;
  }

  @override
  ShapeBorder lerpTo(ShapeBorder? b, double t) {
    if (b is ExpressiveBlobBorder && b.seed == seed) {
      return ExpressiveBlobBorder(
        seed: seed,
        progress: progress + (b.progress - progress) * t,
        safeInset: safeInset,
        side: BorderSide.lerp(side, b.side, t),
      );
    }
    return ShapeBorder.lerp(this, b, t) ?? this;
  }

  @override
  ExpressiveBlobBorder scale(double t) => copyWith(side: side.scale(t));
}
