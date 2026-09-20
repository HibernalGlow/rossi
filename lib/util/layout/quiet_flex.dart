// 不画「黄黑溢出斜纹」的 Flex 家族 —— 开关的**唯一**可执行的落点（另一半见
// `layout_overflow_guard.dart` 顶部那段说明：框架没有全局开关，能拦的只有
// 我们自己造的 Flex 与错误上报）。
//
// 用法：会**长期存在**、内容又来自插件 / 远端（长度不可控）的横向布局，用
// [QuietRow] / [QuietColumn] 代替 `Row` / `Column`。其余地方照旧用框架的 ——
// 这不是「另一个 Row」，它的意义只是「这一处溢出时不要拿条纹糊住内容」。
//
// 机制：`RenderFlex.paint` 里那段 assert 会无条件调用 `paintOverflowIndicator`，
// 而这个方法是 mixin 上的普通实例方法 ⇒ 子类覆写它即可整段跳过（连带
// `_reportOverflow` 的错误上报一起省掉，不会只关一半）。

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:zephyr/util/layout/layout_overflow_guard.dart';

/// 与 `Flex` 参数、行为完全一致，只是溢出时受 [layoutOverflowStripesEnabled] 约束。
class QuietFlex extends Flex {
  const QuietFlex({
    super.key,
    required super.direction,
    super.mainAxisAlignment,
    super.mainAxisSize,
    super.crossAxisAlignment,
    super.textDirection,
    super.verticalDirection,
    super.textBaseline,
    super.clipBehavior,
    super.spacing,
    super.children,
  });

  @override
  QuietRenderFlex createRenderObject(BuildContext context) {
    return QuietRenderFlex(
      direction: direction,
      mainAxisAlignment: mainAxisAlignment,
      mainAxisSize: mainAxisSize,
      crossAxisAlignment: crossAxisAlignment,
      textDirection: getEffectiveTextDirection(context),
      verticalDirection: verticalDirection,
      textBaseline: textBaseline,
      clipBehavior: clipBehavior,
      spacing: spacing,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant QuietRenderFlex renderObject,
  ) {
    renderObject
      ..direction = direction
      ..mainAxisAlignment = mainAxisAlignment
      ..mainAxisSize = mainAxisSize
      ..crossAxisAlignment = crossAxisAlignment
      ..textDirection = getEffectiveTextDirection(context)
      ..verticalDirection = verticalDirection
      ..textBaseline = textBaseline
      ..clipBehavior = clipBehavior
      ..spacing = spacing;
  }
}

/// [QuietFlex] 的横向版，参数与 `Row` 同形。
class QuietRow extends QuietFlex {
  const QuietRow({
    super.key,
    super.mainAxisAlignment,
    super.mainAxisSize,
    super.crossAxisAlignment,
    super.textDirection,
    super.verticalDirection,
    super.textBaseline,
    super.clipBehavior,
    super.spacing,
    super.children,
  }) : super(direction: Axis.horizontal);
}

/// [QuietFlex] 的纵向版，参数与 `Column` 同形。
class QuietColumn extends QuietFlex {
  const QuietColumn({
    super.key,
    super.mainAxisAlignment,
    super.mainAxisSize,
    super.crossAxisAlignment,
    super.textDirection,
    super.verticalDirection,
    super.textBaseline,
    super.clipBehavior,
    super.spacing,
    super.children,
  }) : super(direction: Axis.vertical);
}

/// `RenderFlex` 的子类，唯一的差别是 [paintOverflowIndicator] 可以什么都不做。
///
/// 注意：**布局**照旧溢出（`_overflow` 依旧非 0、内容依旧被挤出去），
/// 这个开关只决定「要不要在你脸上盖一条斜纹」。
class QuietRenderFlex extends RenderFlex {
  QuietRenderFlex({
    super.children,
    super.direction,
    super.mainAxisSize,
    super.mainAxisAlignment,
    super.crossAxisAlignment,
    super.textDirection,
    super.verticalDirection,
    super.textBaseline,
    super.clipBehavior,
    super.spacing,
  });

  @override
  void paintOverflowIndicator(
    PaintingContext context,
    Offset offset,
    Rect containerRect,
    Rect childRect, {
    List<DiagnosticsNode>? overflowHints,
  }) {
    if (!layoutOverflowStripesEnabled) {
      return;
    }
    super.paintOverflowIndicator(
      context,
      offset,
      containerRect,
      childRect,
      overflowHints: overflowHints,
    );
  }
}
