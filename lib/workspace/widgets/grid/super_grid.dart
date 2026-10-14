import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/model/workspace_grid_layout.dart';
import 'package:zephyr/widgets/motion/expressive_motion.dart';
import 'package:zephyr/workspace/widgets/grid/card_layout_scope.dart';
import 'package:zephyr/workspace/widgets/grid/card_resize_handle.dart';
import 'package:zephyr/workspace/widgets/grid/grid.dart';
import 'package:zephyr/workspace/widgets/grid/motion_grid.dart';
import 'package:zephyr/i18n/strings.g.dart';

typedef CardResizeCallback =
    void Function(Key key, int widthSpan, int heightSpan);
typedef CardRemoveCallback = void Function(Key key);

/// 标题拖动排序、卡片内尺寸手柄与局部尺寸预览。
class SuperGrid extends StatefulWidget {
  const SuperGrid({
    super.key,
    required this.children,
    this.editing = false,
    this.crossAxisCount = 4,
    this.mainAxisSpacing = 8,
    this.crossAxisSpacing = 8,
    this.mainAxisExtent = 96,
    this.onChanged,
    this.onResizeCard,
    this.onRemoveCard,
    this.canRemoveCard,
    this.minimumCardWidth,
    this.minimumCardHeight,
    this.maxHeightSpan,
    this.onToggleEditing,
    this.hiddenCards = const <HiddenCardEntry>[],
    this.onRestoreCard,
    this.isFillingRemainingHeight,
    this.onFillRemainingHeight,
  });

  final List<GridItem> children;
  final bool editing;
  final double mainAxisSpacing;
  final double crossAxisSpacing;
  final double mainAxisExtent;
  final int crossAxisCount;
  final ValueChanged<List<GridItem>>? onChanged;
  final CardResizeCallback? onResizeCard;
  final CardRemoveCallback? onRemoveCard;
  final bool Function(Key key)? canRemoveCard;
  final double Function(Key key)? minimumCardWidth;
  final double Function(Key key)? minimumCardHeight;
  final int Function(Key key)? maxHeightSpan;
  final VoidCallback? onToggleEditing;
  final List<HiddenCardEntry> hiddenCards;
  final ValueChanged<String>? onRestoreCard;
  final bool Function(Key key)? isFillingRemainingHeight;
  final ValueChanged<Key>? onFillRemainingHeight;

  @override
  State<SuperGrid> createState() => SuperGridState();
}

class SuperGridState extends State<SuperGrid> {
  List<GridItem> _items = [];
  final Map<Key, GlobalKey> _cardKeys = {};
  final GlobalKey _gridKey = GlobalKey();
  Key? _dragKey;
  Key? _hoverKey;
  Timer? _hoverTimer;
  Key? _resizeKey;
  Size? _resizeStart;
  Size? _previewSize;
  double _gridWidth = 0;
  double _resizeMaximumWidth = 0;
  Offset _resizeDelta = Offset.zero;

  List<GridItem> get items => List<GridItem>.unmodifiable(_items);

  @override
  void initState() {
    super.initState();
    _items = List.of(widget.children);
  }

  @override
  void didUpdateWidget(SuperGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameKeys(oldWidget.children, widget.children)) {
      _items = List.of(widget.children);
    } else {
      final latest = {for (final item in widget.children) item.key: item};
      _items = [for (final item in _items) latest[item.key] ?? item];
    }
    final keys = {for (final item in _items) item.key};
    _cardKeys.removeWhere((key, _) => !keys.contains(key));
    if (!keys.contains(_dragKey)) _dragKey = null;
    if (!widget.editing || !keys.contains(_resizeKey)) {
      _resizeKey = null;
      _previewSize = null;
    }
  }

  @override
  void dispose() {
    _hoverTimer?.cancel();
    super.dispose();
  }

  bool _sameKeys(List<GridItem> a, List<GridItem> b) =>
      a.length == b.length &&
      Iterable<int>.generate(a.length).every((i) => a[i].key == b[i].key);

  void _scheduleHover(Key key) {
    if (_dragKey == null || _dragKey == key || _hoverKey == key) return;
    _hoverKey = key;
    _hoverTimer?.cancel();
    _hoverTimer = Timer(const Duration(milliseconds: 100), () {
      if (!mounted || _dragKey == null) return;
      final from = _items.indexWhere((item) => item.key == _dragKey);
      final to = _items.indexWhere((item) => item.key == key);
      if (from < 0 || to < 0) return;
      setState(() {
        final moved = _items.removeAt(from);
        _items.insert(to, moved);
      });
    });
  }

  void _finishDrag() {
    _hoverTimer?.cancel();
    _hoverKey = null;
    if (!_sameKeys(_items, widget.children)) {
      widget.onChanged?.call(List.unmodifiable(_items));
    }
    if (mounted) setState(() => _dragKey = null);
  }

  int _widthSpan(GridItem item) =>
      item.logicalWidthSpan ??
      (item.crossAxisCellCount / widget.crossAxisCount * 4).round().clamp(1, 4);

  int _columnsFor(int span, [Key? key]) => resolveCrossAxisCellCount(
    widthSpan: span,
    band: switch (widget.crossAxisCount) {
      4 => WorkspaceGridBand.compact,
      8 => WorkspaceGridBand.medium,
      _ => WorkspaceGridBand.expanded,
    },
    availableWidth: _gridWidth,
    minimumWidth: key == null ? 0 : widget.minimumCardWidth?.call(key) ?? 0,
    spacing: widget.crossAxisSpacing,
  ).clamp(1, widget.crossAxisCount);

  double _widthForSpan(int span, [Key? key]) =>
      (_gridWidth + widget.crossAxisSpacing) *
          _columnsFor(span, key) /
          widget.crossAxisCount -
      widget.crossAxisSpacing;

  void _startResize(GridItem item) {
    final render = _cardKeys[item.key]?.currentContext?.findRenderObject();
    if (render is! RenderBox || !render.hasSize) return;
    final grid = _gridKey.currentContext?.findRenderObject();
    if (grid is! RenderBox) return;
    final origin = render.localToGlobal(Offset.zero, ancestor: grid);
    setState(() {
      // 右侧卡片只能拉到面板边缘，避免越过列边界时突然跳到下一行。
      _resizeMaximumWidth = math.max(render.size.width, _gridWidth - origin.dx);
      _resizeKey = item.key;
      _resizeStart = render.size;
      _previewSize = render.size;
      _resizeDelta = Offset.zero;
    });
  }

  void _updateResize(Offset delta) {
    final start = _resizeStart;
    if (_resizeKey == null || start == null) return;
    final minimumWidth = math.min(
      math.max(
        _widthForSpan(1, _resizeKey),
        widget.minimumCardWidth?.call(_resizeKey!) ?? 0,
      ),
      start.width,
    );
    final minimumHeight = math.min(
      widget.minimumCardHeight?.call(_resizeKey!) ?? widget.mainAxisExtent,
      start.height,
    );
    final maxSpan = widget.maxHeightSpan?.call(_resizeKey!) ?? 4;
    setState(() {
      _resizeDelta = delta;
      _previewSize = Size(
        (start.width + delta.dx).clamp(minimumWidth, _resizeMaximumWidth),
        (start.height + delta.dy).clamp(
          minimumHeight,
          math.max(start.height, widget.mainAxisExtent * maxSpan),
        ),
      );
    });
  }

  void _finishResize({bool cancelled = false}) {
    final key = _resizeKey;
    final preview = _previewSize;
    final item = _items.where((item) => item.key == key).firstOrNull;
    if (!cancelled &&
        key != null &&
        preview != null &&
        item != null &&
        _resizeDelta.distance > 1) {
      var span = _widthSpan(item);
      if (_resizeDelta.dx.abs() > 1) {
        var distance = (preview.width - _widthForSpan(span, key)).abs();
        for (var candidate = 1; candidate <= 4; candidate++) {
          final candidateWidth = _widthForSpan(candidate, key);
          final minimumWidth = math.min(
            widget.minimumCardWidth?.call(key) ?? 0,
            _gridWidth,
          );
          if (candidateWidth < minimumWidth) continue;
          final next = (preview.width - candidateWidth).abs();
          if (next < distance) {
            distance = next;
            span = candidate;
          }
        }
      }
      final maxSpan = widget.maxHeightSpan?.call(key) ?? 4;
      final height = _resizeDelta.dy.abs() > 1
          ? ((preview.height + widget.mainAxisSpacing) /
                    (widget.mainAxisExtent + widget.mainAxisSpacing))
                .round()
                .clamp(1, maxSpan)
          : (item.mainAxisCellCount ?? 1).round().clamp(1, maxSpan);
      widget.onResizeCard?.call(key, span, height);
    }
    if (mounted) {
      setState(() {
        _resizeKey = null;
        _resizeStart = null;
        _previewSize = null;
      });
    }
  }

  Widget _wrapCard(GridItem item) {
    final key = item.key!;
    final resizing = _resizeKey == key;
    final preview = resizing ? _previewSize : null;
    final cardKey = _cardKeys.putIfAbsent(key, GlobalKey.new);
    final fillingRemaining =
        widget.isFillingRemainingHeight?.call(key) ?? false;
    return DragTarget<Key>(
      onWillAcceptWithDetails: (details) {
        if (details.data == key) return false;
        _scheduleHover(key);
        return true;
      },
      onMove: (_) => _scheduleHover(key),
      onLeave: (_) {
        if (_hoverKey == key) {
          _hoverTimer?.cancel();
          _hoverKey = null;
        }
      },
      builder: (context, candidates, rejected) => Opacity(
        opacity: _dragKey == key ? .45 : 1,
        child: SizedBox(
          key: cardKey,
          child: CardLayoutScope(
            editing: widget.editing,
            resizing: resizing,
            previewSize: preview,
            dragging: _dragKey == key,
            widthSpan: _widthSpan(item),
            heightSpan: (item.mainAxisCellCount ?? 1).round(),
            onHide:
                widget.onRemoveCard == null ||
                    widget.canRemoveCard?.call(key) == false
                ? null
                : () => widget.onRemoveCard!(key),
            onResize: widget.onResizeCard == null
                ? null
                : (w, h) => widget.onResizeCard!(key, w, h),
            onToggleEditing: widget.onToggleEditing,
            hiddenCards: widget.hiddenCards,
            onRestoreCard: widget.onRestoreCard,
            fillRemainingHeight: fillingRemaining,
            onFillRemainingHeight: widget.onFillRemainingHeight == null
                ? null
                : () => widget.onFillRemainingHeight!(key),
            resizeHandle:
                widget.editing &&
                    item.mainAxisCellCount != null &&
                    widget.onResizeCard != null
                ? CardResizeHandle(
                    label: preview == null
                        ? t.workspace.dragToResize
                        : '${preview.width.round()} × ${preview.height.round()}',
                    onStart: () => _startResize(item),
                    onUpdate: _updateResize,
                    onEnd: () => _finishResize(),
                    onCancel: () => _finishResize(cancelled: true),
                  )
                : null,
            wrapHeader: (header) => _CardHeaderDragHandle(
              cardKey: key,
              onStart: () => setState(() => _dragKey = key),
              onEnd: _finishDrag,
              child: header,
            ),
            child: item.child,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _gridWidth = constraints.maxWidth;
      return MotionGrid(
        key: _gridKey,
        crossAxisCount: widget.crossAxisCount,
        crossAxisSpacing: widget.crossAxisSpacing,
        mainAxisSpacing: widget.mainAxisSpacing,
        mainAxisExtent: widget.mainAxisExtent + widget.mainAxisSpacing,
        // 预览直接跟手；松开后恢复重排和尺寸的收敛动画。
        duration: _resizeKey != null
            ? Duration.zero
            : ExpressiveMotion.duration(
                context,
                ExpressiveMotion.spatialDuration,
              ),
        children: [
          for (final item in _items)
            GridItem(
              key: item.key,
              crossAxisCellCount: _resizeKey == item.key && _previewSize != null
                  ? math.max(
                      item.crossAxisCellCount,
                      ((_previewSize!.width + widget.crossAxisSpacing) /
                              ((_gridWidth + widget.crossAxisSpacing) /
                                  widget.crossAxisCount))
                          .ceil()
                          .clamp(1, widget.crossAxisCount),
                    )
                  : item.crossAxisCellCount,
              crossAxisExtentOverride: _resizeKey == item.key
                  ? _previewSize?.width
                  : null,
              mainAxisCellCount: _resizeKey == item.key && _previewSize != null
                  ? (_previewSize!.height + widget.mainAxisSpacing) /
                        (widget.mainAxisExtent + widget.mainAxisSpacing)
                  : item.mainAxisCellCount,
              logicalWidthSpan: item.logicalWidthSpan,
              child: _wrapCard(item),
            ),
        ],
      );
    },
  );
}

class _CardHeaderDragHandle extends StatefulWidget {
  const _CardHeaderDragHandle({
    required this.cardKey,
    required this.onStart,
    required this.onEnd,
    required this.child,
  });
  final Key cardKey;
  final VoidCallback onStart;
  final VoidCallback onEnd;
  final Widget child;

  @override
  State<_CardHeaderDragHandle> createState() => _CardHeaderDragHandleState();
}

class _CardHeaderDragHandleState extends State<_CardHeaderDragHandle> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final child = AnimatedContainer(
      duration: ExpressiveMotion.duration(
        context,
        ExpressiveMotion.effectDuration,
      ),
      decoration: BoxDecoration(
        color: _pressed
            ? Theme.of(context).colorScheme.primaryContainer
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: widget.child,
    );
    return MouseRegion(
      cursor: _pressed ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
      child: Listener(
        onPointerDown: (_) => setState(() => _pressed = true),
        onPointerUp: (_) => setState(() => _pressed = false),
        onPointerCancel: (_) => setState(() => _pressed = false),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final feedback = Material(
              elevation: 8,
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(width: constraints.maxWidth, child: widget.child),
            );
            void start() {
              HapticFeedback.selectionClick();
              widget.onStart();
            }

            return Tooltip(
              message: t.workspace.dragTitleToReorder,
              child: LongPressDraggable<Key>(
                data: widget.cardKey,
                delay: const Duration(milliseconds: 200),
                maxSimultaneousDrags: 1,
                allowedButtonsFilter: (buttons) => buttons == kPrimaryButton,
                feedback: feedback,
                onDragStarted: start,
                onDragEnd: (_) => widget.onEnd(),
                child: child,
              ),
            );
          },
        ),
      ),
    );
  }
}
