import 'package:material_ui/material_ui.dart';

import 'package:zephyr/workspace/model/shelf_timeline.dart';
import 'package:zephyr/workspace/widgets/library_view/library_entry.dart';
import 'package:zephyr/workspace/widgets/library_view/library_entry_surface.dart';
import 'package:zephyr/workspace/widgets/library_view/library_view_mode.dart';

/// 时间线：按本地日历日分段的书签 / 历史列表。
///
/// 与 `LibraryEntryList` 的分工：那一层管「六档视图怎么排行」，这一层管
/// 「把行按天分组、并在左边加一条轨道」。**行的内容一概不自己画** ——
/// 每条仍然交给 [LibraryEntrySurface]（固定用封面列表那一档），否则
/// 「三种数据源不该有三套行渲染」这条口径就被时间线破掉了：封面、标题、
/// 副标题、行尾那颗动作键会立刻开始与列表档长得不一样。
///
/// # 为什么是一档开关而不是第七种视图档
///
/// 见 `model/shelf_timeline.dart` 的库注释：`LibraryViewMode` 与 Rust 侧
/// `FileManagerViewMode` 一一对应，为书架专属的东西去动三家共用的枚举与
/// 映射不划算。
class ShelfTimelineView extends StatelessWidget {
  const ShelfTimelineView({
    super.key,
    required this.entries,
    required this.timeOf,
    required this.onTap,
    this.emptyText = '没有条目',
    this.wrapRow,
    this.enabled = true,
    this.busy = false,
    this.standalone = false,
  });

  final List<LibraryEntry> entries;

  /// 取一个条目的时间：书签是收藏时间，历史是最后阅读。
  ///
  /// 由数据源给而不是往 [LibraryEntry] 上加一个 `time` 字段：那一份是
  /// 文件管理器 / 书签 / 历史三家共用的行契约，时间线只前两家要。
  final DateTime Function(LibraryEntry entry) timeOf;

  final ValueChanged<LibraryEntry> onTap;
  final String emptyText;

  /// 与 `LibraryEntryList.wrapRow` 同一个用途：给每行套上右键菜单宿主。
  /// 时间线上少了它，条目就没法取消收藏 / 移除。
  final Widget Function(BuildContext context, LibraryEntry entry, Widget row)?
  wrapRow;

  final bool enabled;
  final bool busy;

  /// 独占整个面板时不再套 120~440 的高度限制，口径与 `LibraryEntryList` 一致。
  final bool standalone;

  static const double _borderRadius = 8;

  /// 左轨的宽度与圆点直径。轨道压在行上，不参与行高计算。
  static const double _railWidth = 24;
  static const double _dotSize = 10;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return _buildEmpty(context);

    final days = groupShelfTimelineByDay(
      entries.map(timeOf).toList(growable: false),
    );
    final cells = _flatten(days);
    final now = DateTime.now();

    final list = ListView.builder(
      primary: false,
      padding: EdgeInsets.zero,
      itemCount: cells.length,
      itemBuilder: (context, index) {
        final cell = cells[index];
        if (cell.dayIndex != null) {
          return _buildDayHeader(context, days[cell.dayIndex!], now);
        }
        final entry = entries[cell.entryIndex!];
        final row = LibraryEntrySurface(
          key: ValueKey('timeline:${entry.key}'),
          // 行内容固定用封面列表那一档：时间线要的是「一行一本」，
          // 而封面列表正是六档里唯一「缩略图 + 两行文字 + 行尾动作」的形状。
          mode: LibraryViewMode.coverList,
          entry: entry,
          onTap: enabled ? () => onTap(entry) : null,
        );
        return _buildRailRow(
          context,
          entry: entry,
          row: row,
          // 一组的第一行不画上延线、最后一行不画下延线，线才不会插进段头
          // 或者列表末尾的空白里。
          showTopLine: !cell.isGroupFirst,
          showBottomLine: !cell.isGroupLast,
        );
      },
    );

    final content = DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
        borderRadius: const BorderRadius.all(Radius.circular(_borderRadius)),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(_borderRadius)),
        child: list,
      ),
    );

    return Stack(
      fit: standalone ? StackFit.expand : StackFit.loose,
      children: [
        standalone
            ? content
            : ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 120, maxHeight: 440),
                child: content,
              ),
        if (busy)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x33000000),
              child: Center(
                child: SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final empty = Center(
      child: Text(emptyText, style: Theme.of(context).textTheme.bodySmall),
    );
    return standalone ? empty : SizedBox(height: 170, child: empty);
  }

  /// 把「段头 + 该段的行」摊平成一维单元格序列。
  ///
  /// 用摊平而不是 `ListView` 套 `Column`：一天几十条时嵌套定高列表会在
  /// 滚动条长度上撒谎，而段头也就不可能跟着滚出视口。
  List<_TimelineCell> _flatten(List<ShelfTimelineDay> days) {
    final cells = <_TimelineCell>[];
    for (var dayIndex = 0; dayIndex < days.length; dayIndex++) {
      final indexes = days[dayIndex].indexes;
      cells.add(_TimelineCell(dayIndex: dayIndex));
      for (var position = 0; position < indexes.length; position++) {
        cells.add(
          _TimelineCell(
            entryIndex: indexes[position],
            isGroupFirst: position == 0,
            isGroupLast: position == indexes.length - 1,
          ),
        );
      }
    }
    return cells;
  }

  Widget _buildDayHeader(
    BuildContext context,
    ShelfTimelineDay day,
    DateTime now,
  ) {
    final theme = Theme.of(context);
    return Container(
      // 段头坐在左轨那一列的右边，与行的文字对齐 —— 日期跟着圆点缩进去
      // 会读成「轨道的一部分」，而不是一段的主标题。
      padding: const EdgeInsets.only(
        left: _railWidth + 4,
        right: 12,
        top: 10,
        bottom: 6,
      ),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      child: Row(
        children: [
          Expanded(
            child: Text(
              shelfTimelineDayLabel(day.dayStart, now: now),
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${day.indexes.length}',
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRailRow(
    BuildContext context, {
    required LibraryEntry entry,
    required Widget row,
    required bool showTopLine,
    required bool showBottomLine,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final wrapped = wrapRow?.call(context, entry, row) ?? row;

    // 用 Stack 而不是 `Row(crossAxisAlignment: stretch)`：ListView 给行的
    // 垂直方向是**无界**的，stretch 会把这份无限高度压给轨道，直接
    // 「BoxConstraints forces an infinite height」。
    // Stack 的高度由非定位的那个孩子（行本体）决定，轨道再用
    // `Positioned(top/bottom: 0)` 铺满它 —— 轨道因此天然与行等高，
    // 不需要 `IntrinsicHeight` 那种两遍布局的东西。
    return Stack(
      children: [
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: _railWidth,
          child: CustomPaint(
            painter: _TimelineRailPainter(
              lineColor: scheme.outlineVariant,
              dotColor: scheme.primary,
              railWidth: _railWidth,
              dotSize: _dotSize,
              showTopLine: showTopLine,
              showBottomLine: showBottomLine,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: _railWidth),
          child: wrapped,
        ),
      ],
    );
  }
}

class _TimelineCell {
  const _TimelineCell({
    this.dayIndex,
    this.entryIndex,
    this.isGroupFirst = false,
    this.isGroupLast = false,
  });

  /// 非空 ⇒ 这一格是段头。
  final int? dayIndex;

  /// 非空 ⇒ 这一格是一条条目。
  final int? entryIndex;
  final bool isGroupFirst;
  final bool isGroupLast;
}

/// 左轨：一条竖线 + 一个圆点。
///
/// 用 `CustomPaint` 而不是 `Column` 拼 `Container`：行高由 `LibraryEntrySurface`
/// 决定（六档里封面列表那一档还会随副标题有无变高），拼盒子要在布局后才拿到高度，
/// 而圆点必须**始终**落在行的垂直中心。
class _TimelineRailPainter extends CustomPainter {
  const _TimelineRailPainter({
    required this.lineColor,
    required this.dotColor,
    required this.railWidth,
    required this.dotSize,
    required this.showTopLine,
    required this.showBottomLine,
  });

  final Color lineColor;
  final Color dotColor;
  final double railWidth;
  final double dotSize;
  final bool showTopLine;
  final bool showBottomLine;

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = railWidth / 2;
    final centerY = size.height / 2;
    final line = Paint()
      ..color = lineColor
      ..strokeWidth = 2;

    if (showTopLine) {
      canvas.drawLine(Offset(centerX, 0), Offset(centerX, centerY), line);
    }
    if (showBottomLine) {
      canvas.drawLine(
        Offset(centerX, centerY),
        Offset(centerX, size.height),
        line,
      );
    }
    // 圆点永远画：它是「这一条属于这一天的一个节点」，与线断不断无关。
    canvas.drawCircle(
      Offset(centerX, centerY),
      dotSize / 2,
      Paint()..color = dotColor,
    );
  }

  @override
  bool shouldRepaint(_TimelineRailPainter old) =>
      old.lineColor != lineColor ||
      old.dotColor != dotColor ||
      old.railWidth != railWidth ||
      old.dotSize != dotSize ||
      old.showTopLine != showTopLine ||
      old.showBottomLine != showBottomLine;
}
