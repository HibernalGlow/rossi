import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/expressive/expressive_blob.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_gap_shape.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_presentation.dart';
import 'package:zephyr/workspace/widgets/library_view/library_entry.dart';

/// 展墙里**一块可以被填上的空隙**。
///
/// 两种来源：卡片比同行最矮的那块矮，剩下的竖向余量（[tile] 非空）；
/// 或者一行没排满，行尾剩下的横向余量（[tile] 为 null）。
/// 尺寸由布局算好后传进来，填充物只负责在给定矩形里画东西。
class LibraryGapSlot {
  const LibraryGapSlot({
    required this.row,
    required this.tile,
    required this.columnStart,
    required this.span,
    required this.width,
    required this.height,
  });

  final int row;

  /// 行内第几块卡片**下方**的余量；null = 行尾空隙。
  final int? tile;

  /// 这块空隙从第几格开始、跨几格（只用于标识与调试，宽度已经算好）。
  final int columnStart;
  final int span;
  final double width;
  final double height;

  bool get isTrailing => tile == null;

  /// 同一面墙内稳定唯一；与 scope 一起决定随机种子。
  String get id => 'r$row${tile == null ? 'x' : 't$tile'}';
}

/// 小于这个尺寸的空隙不填：填了也看不清，还会把卡片挤得更碎。
const double kLibraryGapMinFill = 64;

/// 扫描行布局，产出所有可填充槽位（自上而下、自左而右）。
List<LibraryGapSlot> libraryGapSlots({
  required List<LibraryCanvasRow> rows,
  required List<List<double>> heights,
  required double unit,
  required double gap,
  required int columns,
  double minFill = kLibraryGapMinFill,
}) {
  final slots = <LibraryGapSlot>[];
  for (var r = 0; r < rows.length; r++) {
    final row = rows[r];
    if (row.indices.isEmpty || r >= heights.length) continue;
    final rowHeight = heights[r].fold(0.0, math.max);
    var column = 0;
    for (var j = 0; j < row.indices.length && j < heights[r].length; j++) {
      final span = row.spans[j];
      final width = unit * span + (span - 1) * gap;
      // 竖向余量里再留一条 gap，填充物不会贴着上面的卡片。
      final remainder = rowHeight - heights[r][j] - gap;
      if (remainder >= minFill && width >= minFill) {
        slots.add(
          LibraryGapSlot(
            row: r,
            tile: j,
            columnStart: column,
            span: span,
            width: width,
            height: remainder,
          ),
        );
      }
      column += span;
    }
    final trailing = columns - column;
    if (trailing > 0) {
      final width = unit * trailing + (trailing - 1) * gap;
      if (width >= minFill && rowHeight >= minFill) {
        slots.add(
          LibraryGapSlot(
            row: r,
            tile: null,
            columnStart: column,
            span: trailing,
            width: width,
            height: rowHeight,
          ),
        );
      }
    }
  }
  return slots;
}

enum LibraryGapKind { shape, widget }

/// 某个槽位最终填什么。
class LibraryGapChoice {
  const LibraryGapChoice({
    required this.kind,
    required this.seed,
    this.widgetId,
    this.shapeStyle = LibraryGapShapeStyle.blob,
  });

  LibraryGapChoice.shape(
    this.seed, {
    this.shapeStyle = LibraryGapShapeStyle.blob,
  }) : kind = LibraryGapKind.shape,
       widgetId = null;

  LibraryGapChoice.widget(
    this.widgetId,
    this.seed, {
    this.shapeStyle = LibraryGapShapeStyle.blob,
  }) : kind = LibraryGapKind.widget;

  final LibraryGapKind kind;
  final String? widgetId;
  final int seed;

  /// 这一块如果退化成随机图形，用哪一款轮廓。
  final LibraryGapShapeStyle shapeStyle;

  bool get isShape => kind == LibraryGapKind.shape;
}

/// 小组件能看到的数据面：整面墙的条目、这块空隙的尺寸，以及槽位种子
/// （同一面墙里第 3 行的拼贴和第 7 行的拼贴不该抽到同一批封面）。
class LibraryGapSample {
  const LibraryGapSample({
    required this.entries,
    required this.slot,
    required this.seed,
  });

  final List<LibraryEntry> entries;
  final LibraryGapSlot slot;
  final int seed;
}

/// 一款空隙小组件。
///
/// [minWidth] / [minHeight] 是**能看清的下限**，不是占位尺寸：组件按槽位实际
/// 大小自适应，装不下的槽位不填它。[accepts] 判的是「这批数据有没有意义」，
/// 没有进度数据的一墙文件里不该冒出一张进度卡。
class LibraryGapWidgetSpec {
  const LibraryGapWidgetSpec({
    required this.id,
    required this.label,
    required this.glyph,
    required this.builder,
    this.minWidth = 88,
    this.minHeight = 56,
    this.accepts,
  });

  final String id;
  final String label;
  final Glyph glyph;
  final double minWidth;
  final double minHeight;
  final bool Function(LibraryGapSample sample)? accepts;
  final Widget Function(BuildContext context, LibraryGapSample sample) builder;

  bool fits(LibraryGapSample sample) =>
      (accepts?.call(sample) ?? true) &&
      sample.slot.width >= minWidth &&
      sample.slot.height >= minHeight;
}

/// 决定每个槽位填什么。
///
/// 三档口径（与设置页一一对应）：
/// * [LibraryGapFill.shapes]：全部填随机图形；
/// * [LibraryGapFill.widgets]：只填小组件，同一款可以重复（轮流挑用得最少的），
///   没有合适尺寸的组件就留空 —— 这一档的语义是「我不要图形」；
/// * [LibraryGapFill.both]：组件**每面墙各出现一次**，装不下或已经用过的槽位
///   退化成随机图形。用户要的「防止小组件重复出现」就是这一条。
Map<String, LibraryGapChoice> libraryGapChoices({
  required List<LibraryGapSlot> slots,
  required LibraryGapFill mode,
  required List<LibraryGapWidgetSpec> widgets,
  required List<LibraryEntry> entries,
  required String scope,
  List<LibraryGapShapeStyle> shapes = kLibraryGapShapeStyles,
}) {
  if (mode == LibraryGapFill.off || slots.isEmpty) return const {};
  final result = <String, LibraryGapChoice>{};
  final used = <String>{};
  final uses = <String, int>{};
  // 并列时按**套件顺序**裁决：清单本身就是优先级（封面拼贴 > 近 7 日 > …），
  // 按 id 排会把这套口径改成字典序。
  final rank = {for (var i = 0; i < widgets.length; i++) widgets[i].id: i};
  for (final slot in slots) {
    final seed = expressiveBlobSeed('$scope|${slot.id}');
    final shapeStyle = libraryGapShapeStyleFor(seed, shapes);
    if (mode == LibraryGapFill.shapes) {
      result[slot.id] = LibraryGapChoice.shape(seed, shapeStyle: shapeStyle);
      continue;
    }
    final sample = LibraryGapSample(entries: entries, slot: slot, seed: seed);
    final candidates = widgets.where((w) => w.fits(sample)).toList();
    if (mode == LibraryGapFill.widgets) {
      if (candidates.isEmpty) continue;
      candidates.sort((a, b) {
        final byUse = (uses[a.id] ?? 0).compareTo(uses[b.id] ?? 0);
        return byUse == 0 ? rank[a.id]!.compareTo(rank[b.id]!) : byUse;
      });
      final pick = candidates.first;
      uses[pick.id] = (uses[pick.id] ?? 0) + 1;
      result[slot.id] = LibraryGapChoice.widget(pick.id, seed);
      continue;
    }
    final fresh = candidates.where((w) => !used.contains(w.id)).toList();
    if (fresh.isEmpty) {
      result[slot.id] = LibraryGapChoice.shape(seed, shapeStyle: shapeStyle);
      continue;
    }
    used.add(fresh.first.id);
    result[slot.id] = LibraryGapChoice.widget(fresh.first.id, seed);
  }
  return result;
}

/// 总口径 + 「随机图形」单独开关 → 本次真正生效的口径。
///
/// 图形被单独关掉时：shapes 档等于不填（画不出别的东西），both 档退化成
/// 只放组件（装不下的位置留空）。
LibraryGapFill libraryGapMode({
  required LibraryGapFill fill,
  required bool shapes,
}) => switch ((fill, shapes)) {
  (LibraryGapFill.off, _) ||
  (LibraryGapFill.shapes, false) => LibraryGapFill.off,
  (LibraryGapFill.both, false) => LibraryGapFill.widgets,
  (final mode, _) => mode,
};

/// 单项开关过滤后的套件；表里缺键 = 开，于是新加的组件默认可见。
List<LibraryGapWidgetSpec> libraryGapKit(
  List<LibraryGapWidgetSpec> kit,
  Map<String, bool> toggles,
) => [
  for (final spec in kit)
    if (toggles[spec.id] ?? true) spec,
];
