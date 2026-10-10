// ignore_for_file: prefer_initializing_formals

import 'dart:math' as math;
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/model/workspace_grid_layout.dart';

typedef WrapBuilder = Widget Function(Widget child);

/// 核心二维网格组件，支持多跨度 (crossAxisCellCount / mainAxisCellCount)。
class Grid extends MultiChildRenderObjectWidget {
  final double mainAxisSpacing;
  final double crossAxisSpacing;
  final double? mainAxisExtent;
  final int crossAxisCount;
  final AxisDirection axisDirection;
  final TextDirection textDirection;

  const Grid({
    super.key,
    this.mainAxisSpacing = 0,
    this.crossAxisSpacing = 0,
    int? crossAxisCount,
    AxisDirection? axisDirection,
    TextDirection? textDirection,
    this.mainAxisExtent,
    super.children,
  })  : crossAxisCount = crossAxisCount ?? 1,
        axisDirection = axisDirection ?? AxisDirection.down,
        textDirection = textDirection ?? TextDirection.ltr;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderGrid(
      textDirection: textDirection,
      crossAxisCount: crossAxisCount,
      mainAxisSpacing: mainAxisSpacing,
      crossAxisSpacing: crossAxisSpacing,
      axisDirection: axisDirection,
      mainAxisExtent: mainAxisExtent,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderGrid renderObject) {
    renderObject
      ..mainAxisSpacing = mainAxisSpacing
      ..mainAxisExtent = mainAxisExtent
      ..crossAxisSpacing = crossAxisSpacing
      ..textDirection = textDirection
      ..axisDirection = axisDirection
      ..crossAxisCount = crossAxisCount;
  }
}

class RenderGrid extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, GridParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, GridParentData> {
  RenderGrid({
    required double mainAxisSpacing,
    required double crossAxisSpacing,
    required int crossAxisCount,
    required AxisDirection axisDirection,
    required TextDirection textDirection,
    double? mainAxisExtent,
  })  : _crossAxisCount = crossAxisCount,
        _crossAxisSpacing = crossAxisSpacing,
        _mainAxisSpacing = mainAxisSpacing,
        _axisDirection = axisDirection,
        _textDirection = textDirection,
        _mainAxisExtent = mainAxisExtent;

  int _crossAxisCount;
  int get crossAxisCount => _crossAxisCount;
  set crossAxisCount(int value) {
    if (_crossAxisCount != value) {
      _crossAxisCount = value;
      markNeedsLayout();
    }
  }

  double? _mainAxisExtent;
  double? get mainAxisExtent => _mainAxisExtent;
  set mainAxisExtent(double? value) {
    if (_mainAxisExtent != value) {
      _mainAxisExtent = value;
      markNeedsLayout();
    }
  }

  double _mainAxisSpacing;
  double get mainAxisSpacing => _mainAxisSpacing;
  set mainAxisSpacing(double value) {
    if (_mainAxisSpacing != value) {
      _mainAxisSpacing = value;
      markNeedsLayout();
    }
  }

  double _crossAxisSpacing;
  double get crossAxisSpacing => _crossAxisSpacing;
  set crossAxisSpacing(double value) {
    if (_crossAxisSpacing != value) {
      _crossAxisSpacing = value;
      markNeedsLayout();
    }
  }

  AxisDirection _axisDirection;
  AxisDirection get axisDirection => _axisDirection;
  set axisDirection(AxisDirection value) {
    if (_axisDirection != value) {
      _axisDirection = value;
      markNeedsLayout();
    }
  }

  TextDirection _textDirection;
  TextDirection get textDirection => _textDirection;
  set textDirection(TextDirection value) {
    if (_textDirection != value) {
      _textDirection = value;
      markNeedsLayout();
    }
  }

  Axis get mainAxis => axisDirectionToAxis(_axisDirection);

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! GridParentData) {
      child.parentData = GridParentData();
    }
  }

  @override
  void performLayout() {
    final requestedSize = _computeSize(constraints: constraints);
    size = constraints.constrain(requestedSize);
    _hasOverflow = size != requestedSize;
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_hasOverflow) {
      context.pushClipRect(
        needsCompositing,
        offset,
        Offset.zero & size,
        defaultPaint,
      );
    } else {
      defaultPaint(context, offset);
    }
  }

  bool participatesInLayout(RenderBox child) => true;

  GridParentData _getParentData(RenderBox child) {
    return child.parentData as GridParentData;
  }

  void _layoutChild(
    RenderBox child,
    BoxConstraints constraints, {
    bool parentUsesSize = false,
  }) {
    child.layout(constraints, parentUsesSize: parentUsesSize);
  }

  int _computeCrossAxisCellCount(
    GridParentData childParentData,
    int crossAxisCount,
  ) {
    return math.min(childParentData.crossAxisCellCount ?? 1, crossAxisCount);
  }

  Size _computeSize({required BoxConstraints constraints}) {
    final crossAxisExtent = mainAxis == Axis.vertical
        ? constraints.maxWidth
        : constraints.maxHeight;
    final stride = gridStride(
      crossAxisExtent: crossAxisExtent,
      crossAxisCount: crossAxisCount,
      crossAxisSpacing: crossAxisSpacing,
    );

    final children = <RenderBox>[];
    final crossAxisCellCounts = <int>[];
    final mainAxisExtents = <double>[];

    RenderBox? child = firstChild;
    while (child != null) {
      if (!participatesInLayout(child)) {
        child = childAfter(child);
        continue;
      }
      final childParentData = _getParentData(child);
      final crossAxisCellCount = _computeCrossAxisCellCount(
        childParentData,
        crossAxisCount,
      );
      final childCrossAxisExtent =
          stride * crossAxisCellCount - crossAxisSpacing;

      final double childMainAxisExtent;
      if (childParentData.mainAxisCellCount == null) {
        final childConstraints = mainAxis == Axis.vertical
            ? BoxConstraints.tightFor(width: childCrossAxisExtent)
            : BoxConstraints.tightFor(height: childCrossAxisExtent);
        _layoutChild(child, childConstraints, parentUsesSize: true);
        childMainAxisExtent = mainAxis == Axis.vertical
            ? child.size.height
            : child.size.width;
      } else {
        childMainAxisExtent =
            (mainAxisExtent ?? stride) *
                childParentData.mainAxisCellCount! -
            mainAxisSpacing;
        final childSize = mainAxis == Axis.vertical
            ? Size(childCrossAxisExtent, childMainAxisExtent)
            : Size(childMainAxisExtent, childCrossAxisExtent);
        _layoutChild(
          child,
          BoxConstraints.tight(childSize),
          parentUsesSize: true,
        );
      }

      childParentData.realMainAxisExtent = childMainAxisExtent;
      children.add(child);
      crossAxisCellCounts.add(crossAxisCellCount);
      mainAxisExtents.add(childMainAxisExtent);
      child = childAfter(child);
    }

    final geometry = packGridSlots(
      crossAxisCellCounts: crossAxisCellCounts,
      mainAxisExtents: mainAxisExtents,
      crossAxisCount: crossAxisCount,
      crossAxisExtent: crossAxisExtent,
      crossAxisSpacing: crossAxisSpacing,
      mainAxisSpacing: mainAxisSpacing,
    );

    for (int i = 0; i < children.length; i++) {
      final slot = geometry.slots[i];
      final crossAxisOffset = slot.crossAxisIndex * stride;
      _getParentData(children[i]).offset = mainAxis == Axis.vertical
          ? Offset(crossAxisOffset, slot.mainAxisOffset)
          : Offset(slot.mainAxisOffset, crossAxisOffset);
    }

    final totalMainAxisExtent = geometry.mainAxisExtent;

    if (axisDirectionIsReversed(axisDirection)) {
      for (int i = 0; i < children.length; i++) {
        final childParentData = _getParentData(children[i]);
        final offset = childParentData.offset;
        final crossAxisOffset =
            mainAxis == Axis.vertical ? offset.dx : offset.dy;
        final currentMainAxisOffset =
            mainAxis == Axis.vertical ? offset.dy : offset.dx;
        final revOffset =
            totalMainAxisExtent - currentMainAxisOffset - mainAxisExtents[i];
        childParentData.offset = mainAxis == Axis.vertical
            ? Offset(crossAxisOffset, revOffset)
            : Offset(revOffset, crossAxisOffset);
      }
    }

    if (mainAxis == Axis.vertical && textDirection == TextDirection.rtl) {
      for (int i = 0; i < children.length; i++) {
        final childParentData = _getParentData(children[i]);
        final childCrossAxisExtent =
            stride * crossAxisCellCounts[i] - crossAxisSpacing;
        final offset = childParentData.offset;
        childParentData.offset = Offset(
          crossAxisExtent - offset.dx - childCrossAxisExtent,
          offset.dy,
        );
      }
    }

    return mainAxis == Axis.vertical
        ? Size(crossAxisExtent, totalMainAxisExtent)
        : Size(totalMainAxisExtent, crossAxisExtent);
  }

  bool _hasOverflow = false;
}

class GridParentData extends ContainerBoxParentData<RenderBox> {
  int? crossAxisCellCount;
  num? mainAxisCellCount;
  double? realMainAxisExtent;

  @override
  String toString() =>
      'crossAxisCellCount=$crossAxisCellCount; mainAxisCellCount=$mainAxisCellCount;';
}

/// 放置在 [Grid] 内的网格项，用于指定跨轴与主轴跨度单元格数量。
class GridItem extends ParentDataWidget<GridParentData> {
  final int crossAxisCellCount;
  final num? mainAxisCellCount;

  const GridItem({
    super.key,
    required super.child,
    this.mainAxisCellCount,
    this.crossAxisCellCount = 1,
  });

  @override
  void applyParentData(RenderObject renderObject) {
    final parentData = renderObject.parentData;
    if (parentData is GridParentData) {
      bool needsLayout = false;
      if (parentData.crossAxisCellCount != crossAxisCellCount) {
        parentData.crossAxisCellCount = crossAxisCellCount;
        needsLayout = true;
      }

      if (parentData.mainAxisCellCount != mainAxisCellCount) {
        parentData.mainAxisCellCount = mainAxisCellCount;
        needsLayout = true;
      }

      if (needsLayout) {
        final targetParent = renderObject.parent;
        if (targetParent is RenderGrid) {
          targetParent.markNeedsLayout();
        }
      }
    }
  }

  @override
  Type get debugTypicalAncestorWidgetClass => GridItem;

  GridItem wrap({required WrapBuilder builder}) {
    return GridItem(
      key: key,
      mainAxisCellCount: mainAxisCellCount,
      crossAxisCellCount: crossAxisCellCount,
      child: builder(child),
    );
  }
}
