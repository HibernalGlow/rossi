import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// 「某一项所在的那一行」在滚动内容里的真实位置，以及把它居中所需的滚动偏移。
///
/// 为什么要从渲染树量、而不是按视图模式写死行高：页面导航卡的三种模式，行高分别
/// 由网格的 `childAspectRatio` × **当前栏宽**、`ListTile`、`InkWell` 决定，而栏宽
/// 是用户可以拖着改的。原先写死的 136 / 72 / 38 与实测真值 162.9 / 56 / 32 全都对
/// 不上，差值还会随页码**线性放大** —— 360px 宽的泳道里翻到 151 页时，当前页已经被
/// 推到可视区下方一千四百多像素之外，「跟随阅读进度」于是表现为「什么都没动，
/// 或者停在偏下的位置」。
class PageListRowAnchor {
  const PageListRowAnchor({
    required this.rowTop,
    required this.rowExtent,
    required this.viewportExtent,
    required this.maxScrollExtent,
  });

  /// 这一行顶端在内容坐标系里的位置（scroll offset 为 0 时的那条原点线）。
  final double rowTop;

  /// 这一行连同行距占据的像素。
  final double rowExtent;

  /// 可视区在滚动方向上的长度。
  final double viewportExtent;

  /// 这份内容最多能滚到哪儿。
  final double maxScrollExtent;

  /// 让这一行的中心落在可视区正中；靠近书的首尾时夹紧到边界，不会滚过头。
  double get centeredOffset {
    final raw = rowTop + rowExtent / 2 - viewportExtent / 2;
    return raw.clamp(0.0, math.max(0.0, maxScrollExtent));
  }

  /// 量出 [itemIndex] 所在行（每行 [itemsPerRow] 项）的位置。
  ///
  /// 只在列表已经布局过之后有结果：还没布局、或者只布局出一行因而定不出行距时
  /// 返回 null，由调用方决定是放弃还是下一帧再试。
  static PageListRowAnchor? measure(
    ScrollPosition position, {
    required int itemIndex,
    required int itemsPerRow,
  }) {
    final adaptor = _boxAdaptorOf(position);
    if (adaptor == null) return null;

    // 已布局的行：行号 → 真实顶端。同一行的几列共用同一个顶端，取最小者即可；
    // 行高取这一行里最高的那块，居中时不会因为某列特别矮而偏。
    final tops = <int, double>{};
    final heights = <int, double>{};
    RenderBox? child = adaptor.firstChild;
    while (child != null) {
      final data = child.parentData! as SliverMultiBoxAdaptorParentData;
      final index = data.index;
      final top = _documentTop(child);
      if (index != null && top != null) {
        final row = index ~/ itemsPerRow;
        final known = tops[row];
        if (known == null || top < known) tops[row] = top;
        heights[row] = math.max(heights[row] ?? 0, child.size.height);
      }
      child = data.nextSibling;
    }
    if (tops.isEmpty) return null;

    final targetRow = itemIndex ~/ itemsPerRow;
    final builtTop = tops[targetRow];
    final double rowTop;
    final double rowExtent;
    if (builtTop != null) {
      rowTop = builtTop;
      rowExtent = heights[targetRow] ?? builtTop;
    } else {
      // 懒加载列表里目标行还没被建出来：用已布局行之间量出的真实行距外推。
      final step = _stepPerRow(tops);
      if (step == null) return null;
      final baseRow = tops.keys.reduce(math.min);
      rowTop = tops[baseRow]! + (targetRow - baseRow) * step;
      rowExtent = step;
    }

    return PageListRowAnchor(
      rowTop: rowTop,
      rowExtent: rowExtent,
      viewportExtent: position.viewportDimension,
      maxScrollExtent: position.maxScrollExtent,
    );
  }

  /// 相邻两行之间的真实间距（行高 + 行距），由最外侧两条已布局行摊出来。
  static double? _stepPerRow(Map<int, double> tops) {
    if (tops.length < 2) return null;
    final first = tops.keys.reduce(math.min);
    final last = tops.keys.reduce(math.max);
    final step = (tops[last]! - tops[first]!) / (last - first);
    return step > 0 ? step : null;
  }

  /// 滚动视图里那个「多盒子」sliver（[RenderSliverList] 与 [RenderSliverGrid] 都是）。
  static RenderSliverMultiBoxAdaptor? _boxAdaptorOf(ScrollPosition position) {
    final root = position.context.storageContext.findRenderObject();
    if (root == null) return null;
    RenderSliverMultiBoxAdaptor? found;
    void walk(RenderObject node) {
      if (found != null) return;
      if (node is RenderSliverMultiBoxAdaptor) {
        found = node;
        return;
      }
      node.visitChildren(walk);
    }
    walk(root);
    return found;
  }

  /// 这块内容在内容坐标系里的顶端 = 「把它的上边缘贴到可视区上边缘所需的滚动偏移」。
  ///
  /// 用视口自己的换算而不是 `parentData.layoutOffset`：后者只相对于所属 sliver，
  /// 还得自己再叠上 `SliverPadding` 的那一份，正是这类手工叠加容易漏。
  static double? _documentTop(RenderBox child) {
    if (!child.hasSize) return null;
    final viewport = RenderAbstractViewport.maybeOf(child);
    if (viewport == null) return null;
    return viewport.getOffsetToReveal(child, 0.0).offset;
  }
}
