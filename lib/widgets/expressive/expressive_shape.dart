import 'dart:math' as math;

import 'package:material_new_shapes/material_new_shapes.dart';
import 'package:material_ui/material_ui.dart';

/// 完整形状目录。具体控件按用途选择，列表与标签仍使用柔和矩形。
/// 几何和路径匹配来自 material_new_shapes 的 MaterialShapes / Morph。
enum ExpressiveButtonShape {
  roundedSquare,
  circle,
  slanted,
  arch,
  semiCircle,
  oval,
  pill,
  triangle,
  arrow,
  fan,
  diamond,
  clamShell,
  pentagon,
  gem,
  sunny,
  verySunny,
  cookie4Sided,
  cookie6Sided,
  cookie7Sided,
  cookie9Sided,
  cookie12Sided,
  clover4Leaf,
  clover8Leaf,
  burst,
  softBurst,
  boom,
  softBoom,
  flower,
  puffy,
  puffyDiamond,
  ghostish,
  pixelCircle,
  pixelTriangle,
  bun,
  heart;

  RoundedPolygon get polygon => switch (this) {
    roundedSquare => MaterialShapes.square,
    circle => MaterialShapes.circle,
    slanted => MaterialShapes.slanted,
    arch => MaterialShapes.arch,
    semiCircle => MaterialShapes.semiCircle,
    oval => MaterialShapes.oval,
    pill => MaterialShapes.pill,
    triangle => MaterialShapes.triangle,
    arrow => MaterialShapes.arrow,
    fan => MaterialShapes.fan,
    diamond => MaterialShapes.diamond,
    clamShell => MaterialShapes.clamShell,
    pentagon => MaterialShapes.pentagon,
    gem => MaterialShapes.gem,
    sunny => MaterialShapes.sunny,
    verySunny => MaterialShapes.verySunny,
    cookie4Sided => MaterialShapes.cookie4Sided,
    cookie6Sided => MaterialShapes.cookie6Sided,
    cookie7Sided => MaterialShapes.cookie7Sided,
    cookie9Sided => MaterialShapes.cookie9Sided,
    cookie12Sided => MaterialShapes.cookie12Sided,
    clover4Leaf => MaterialShapes.clover4Leaf,
    clover8Leaf => MaterialShapes.clover8Leaf,
    burst => MaterialShapes.burst,
    softBurst => MaterialShapes.softBurst,
    boom => MaterialShapes.boom,
    softBoom => MaterialShapes.softBoom,
    flower => MaterialShapes.flower,
    puffy => MaterialShapes.puffy,
    puffyDiamond => MaterialShapes.puffyDiamond,
    ghostish => MaterialShapes.ghostish,
    pixelCircle => MaterialShapes.pixelCircle,
    pixelTriangle => MaterialShapes.pixelTriangle,
    bun => MaterialShapes.bun,
    heart => MaterialShapes.heart,
  };

  /// 本应用的交互配对；形状目录本身不规定每个按钮必须如何变形。
  /// 按压与展开分别选择目标，保留各轮廓的特征。
  ExpressiveButtonShape get pressedShape => switch (this) {
    arrow => diamond,
    arch => semiCircle,
    slanted => gem,
    puffy => puffyDiamond,
    fan => triangle,
    cookie4Sided => clover4Leaf,
    cookie6Sided => flower,
    gem => pentagon,
    sunny || verySunny => cookie12Sided,
    flower || clover4Leaf || clover8Leaf => cookie6Sided,
    heart => bun,
    boom || burst => softBurst,
    roundedSquare => roundedSquare,
    circle => roundedSquare,
    semiCircle => arch,
    oval || pill => bun,
    triangle => fan,
    diamond => puffyDiamond,
    clamShell => cookie4Sided,
    pentagon => gem,
    cookie7Sided || cookie9Sided || cookie12Sided => sunny,
    softBurst => burst,
    softBoom => boom,
    puffyDiamond => puffy,
    ghostish => arch,
    pixelCircle => cookie12Sided,
    pixelTriangle => triangle,
    bun => pill,
  };

  ExpressiveButtonShape get expandedShape => switch (this) {
    arrow || arch || slanted || gem => roundedSquare,
    puffy => cookie6Sided,
    fan => arch,
    cookie4Sided || cookie6Sided => circle,
    sunny || verySunny => flower,
    heart => puffy,
    roundedSquare => roundedSquare,
    circle => puffy,
    semiCircle || oval || pill || bun => roundedSquare,
    triangle || pixelTriangle => gem,
    diamond || puffyDiamond => puffy,
    clamShell || ghostish => arch,
    pentagon => circle,
    cookie7Sided || cookie9Sided || cookie12Sided => verySunny,
    flower || clover4Leaf || clover8Leaf => circle,
    burst || softBurst => softBoom,
    boom || softBoom => cookie12Sided,
    pixelCircle => circle,
  };
}

/// 两条闭合轮廓以曲线特征匹配后连续插值；归一化路径按控件矩形缩放。
class ExpressiveMorphBorder extends OutlinedBorder {
  const ExpressiveMorphBorder({
    required this.from,
    required this.to,
    this.progress = 0,
    this.rotation = 0,
    super.side,
  });

  final ExpressiveButtonShape from;
  final ExpressiveButtonShape to;
  final double progress;
  final double rotation;

  static final _morphs =
      <(ExpressiveButtonShape, ExpressiveButtonShape), Morph>{};

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  ExpressiveMorphBorder copyWith({BorderSide? side}) => ExpressiveMorphBorder(
    from: from,
    to: to,
    progress: progress,
    rotation: rotation,
    side: side ?? this.side,
  );

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final morph = _morphs.putIfAbsent((
      from,
      to,
    ), () => Morph(from.polygon, to.polygon));
    var path = morph.toPath(progress: progress.clamp(0.0, 1.0));
    if (rotation != 0) {
      final rotate = Matrix4.identity()
        ..translateByDouble(.5, .5, 0, 1)
        ..rotateZ(rotation)
        ..translateByDouble(-.5, -.5, 0, 1);
      path = path.transform(rotate.storage);
    }
    // 保持归一化轮廓比例；中间态不重新拉伸包围盒，避免大小跳动。
    final transform = Matrix4.identity()
      ..translateByDouble(rect.left, rect.top, 0, 1)
      ..scaleByDouble(rect.width, rect.height, 1, 1);
    return path.transform(transform.storage);
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect.deflate(side.width), textDirection: textDirection);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.solid && side.width > 0) {
      canvas.drawPath(
        getOuterPath(rect.deflate(side.width / 2)),
        side.toPaint(),
      );
    }
  }

  @override
  ShapeBorder scale(double t) => copyWith(side: side.scale(t));
}

/// 0 = 静止，1 = 按压，2 = 展开；同一条状态轨迹支持中途反向。
OutlinedBorder expressiveButtonBorder(
  ExpressiveButtonShape shape,
  double phase,
  double size,
) {
  final state = phase.clamp(0.0, 2.0);
  if (shape == ExpressiveButtonShape.roundedSquare) {
    return RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(size * (.28 - .08 * state / 2)),
    );
  }
  final firstLeg = state <= 1 || shape.pressedShape == shape.expandedShape;
  return ExpressiveMorphBorder(
    from: firstLeg ? shape : shape.pressedShape,
    to: firstLeg ? shape.pressedShape : shape.expandedShape,
    progress: firstLeg ? state.clamp(0.0, 1.0) : state - 1,
    rotation: shape == ExpressiveButtonShape.arrow ? math.pi : 0,
  );
}
