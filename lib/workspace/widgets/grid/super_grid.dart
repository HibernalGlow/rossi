import 'dart:async';
import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/workspace/widgets/grid/defer_pointer.dart';
import 'package:zephyr/workspace/widgets/grid/grid.dart';
import 'package:zephyr/workspace/widgets/grid/motion_grid.dart';
import 'package:zephyr/icons/icons.dart';

typedef CardResizeCallback = void Function(
  Key key,
  int widthSpan,
  int heightSpan,
);
typedef CardRemoveCallback = void Function(Key key);

/// 具备编辑排版、自由拖拽调整大小、快捷预设尺寸以及拖拽重排的交互式网格。
class SuperGrid extends StatefulWidget {
  final List<GridItem> children;
  final bool editing;
  final double mainAxisSpacing;
  final double crossAxisSpacing;
  final int crossAxisCount;
  final ValueChanged<List<GridItem>>? onChanged;
  final CardResizeCallback? onResizeCard;
  final CardRemoveCallback? onRemoveCard;

  const SuperGrid({
    super.key,
    required this.children,
    this.editing = false,
    this.crossAxisCount = 4,
    this.mainAxisSpacing = 8,
    this.crossAxisSpacing = 8,
    this.onChanged,
    this.onResizeCard,
    this.onRemoveCard,
  });

  @override
  State<SuperGrid> createState() => SuperGridState();
}

class _Flight {
  final AnimationController controller;
  final Rect from;
  OverlayEntry? entry;

  _Flight(this.controller, this.from);

  void dispose() {
    entry?.remove();
    entry?.dispose();
    entry = null;
    controller.dispose();
  }
}

class SuperGridState extends State<SuperGrid> with TickerProviderStateMixin {
  static const _shakeDuration = Duration(milliseconds: 3600);
  static const _shakeSwingsPerLoop = [6, 7, 5];
  static const _shakeReach = 2.0;
  static const _hoverDelay = Duration(milliseconds: 120);

  List<GridItem> _items = [];
  final Map<Key, _Flight?> _flights = {};
  Key? _dragKey;
  final ValueNotifier<Size> _dragSize = ValueNotifier(Size.zero);
  Timer? _hoverTimer;
  late final AnimationController _shakeController;

  List<GridItem> get items => List<GridItem>.unmodifiable(_items);

  @override
  void initState() {
    super.initState();
    _items = List<GridItem>.of(widget.children);
    _shakeController = AnimationController(
      vsync: this,
      duration: _shakeDuration,
    );
    _syncShake();
  }

  @override
  void didUpdateWidget(SuperGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameKeys(oldWidget.children, widget.children)) {
      _items = List<GridItem>.of(widget.children);
      if (_dragKey != null && _indexOf(_dragKey!) < 0) {
        _dragKey = null;
      }
    } else if (!identical(oldWidget.children, widget.children)) {
      final latest = {for (final item in widget.children) item.key: item};
      _items = [for (final item in _items) latest[item.key] ?? item];
    }
    if (oldWidget.editing != widget.editing) {
      _dragKey = null;
      _hoverTimer?.cancel();
      _syncShake();
    }
  }

  void _syncShake() {
    if (widget.editing) {
      _shakeController.repeat();
    } else {
      _shakeController.stop();
      _shakeController.reset();
    }
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _hoverTimer?.cancel();
    _dragSize.dispose();
    for (final flight in _flights.values) {
      flight?.dispose();
    }
    super.dispose();
  }

  bool _sameKeys(List<GridItem> a, List<GridItem> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].key != b[i].key) return false;
    }
    return true;
  }

  int _indexOf(Key key) => _items.indexWhere((item) => item.key == key);

  void _commit(List<GridItem> items) {
    widget.onChanged?.call(List<GridItem>.unmodifiable(items));
  }

  void _handleHover(Key key) {
    final dragKey = _dragKey;
    if (!mounted || dragKey == null || dragKey == key) return;
    final from = _indexOf(dragKey);
    final to = _indexOf(key);
    if (from < 0 || to < 0) return;
    final items = List<GridItem>.of(_items);
    items.insert(to, items.removeAt(from));
    setState(() {
      _items = items;
    });
  }

  void _scheduleHover(Key key) {
    _hoverTimer?.cancel();
    _hoverTimer = Timer(_hoverDelay, () => _handleHover(key));
  }

  Widget _buildShake(Widget child, int index) {
    final cycles = _shakeSwingsPerLoop[index % _shakeSwingsPerLoop.length];
    final phase = index * 1.7;
    return AnimatedBuilder(
      animation: _shakeController,
      builder: (_, child) {
        final turn = _shakeController.value * 2 * math.pi * cycles + phase;
        return Transform.translate(
          offset: Offset(0, math.cos(turn) * _shakeReach / 2),
          child: Transform.rotate(
            angle: math.sin(turn) * 0.015,
            child: child,
          ),
        );
      },
      child: child,
    );
  }

  Widget _buildLiftedSurface(Widget child) {
    return Material(
      color: Colors.transparent,
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      child: child,
    );
  }

  Widget _buildEditableWrapper(GridItem item, int index) {
    final key = item.key!;
    final theme = Theme.of(context);

    Widget content = item.child;

    if (widget.editing) {
      content = Stack(
        clipBehavior: Clip.none,
        children: [
          content,
          // 右上角删除/隐藏按钮
          Positioned(
            top: -6,
            right: -6,
            child: DeferPointer(
              child: GestureDetector(
                onTap: () => widget.onRemoveCard?.call(key),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: GlyphIcon(
                    AppGlyphs.close,
                    size: 14,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ),
          ),
          // 尺寸快捷预设胶囊（悬浮在卡片顶部中间）
          Positioned(
            top: 6,
            right: 28,
            child: DeferPointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color:
                        theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _PresetButton(
                      label: '1×1',
                      onTap: () => widget.onResizeCard?.call(key, 1, 1),
                    ),
                    const SizedBox(width: 2),
                    _PresetButton(
                      label: '2×1',
                      onTap: () => widget.onResizeCard?.call(key, 2, 1),
                    ),
                    const SizedBox(width: 2),
                    _PresetButton(
                      label: '2×2',
                      onTap: () => widget.onResizeCard?.call(key, 2, 2),
                    ),
                    const SizedBox(width: 2),
                    _PresetButton(
                      label: '全宽',
                      onTap: () => widget.onResizeCard?.call(key, 4, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 右下角拖拽拉伸尺寸手柄
          Positioned(
            bottom: -6,
            right: -6,
            child: DeferPointer(
              child: _ResizeHandle(
                onDeltaResize: (deltaX, deltaY) {
                  final currentSpanW = item.crossAxisCellCount;
                  final currentSpanH = (item.mainAxisCellCount ?? 1).round();
                  var newSpanW = currentSpanW;
                  var newSpanH = currentSpanH;

                  if (deltaX > 40) newSpanW = math.min(4, currentSpanW + 1);
                  if (deltaX < -40) newSpanW = math.max(1, currentSpanW - 1);
                  if (deltaY > 40) newSpanH = math.min(4, currentSpanH + 1);
                  if (deltaY < -40) newSpanH = math.max(1, currentSpanH - 1);

                  if (newSpanW != currentSpanW || newSpanH != currentSpanH) {
                    widget.onResizeCard?.call(key, newSpanW, newSpanH);
                  }
                },
              ),
            ),
          ),
        ],
      );

      content = _buildShake(content, index);

      final dragTarget = DragTarget<Key>(
        builder: (_, _, _) => content,
        onWillAcceptWithDetails: (details) {
          if (details.data != key) {
            _scheduleHover(key);
          }
          return false;
        },
      );

      return LongPressDraggable<Key>(
        key: ValueKey('draggable:$key'),
        data: key,
        feedback: SizedBox(
          width: 280,
          child: _buildLiftedSurface(item.child),
        ),
        childWhenDragging: Opacity(opacity: 0.3, child: content),
        onDragStarted: () {
          setState(() {
            _dragKey = key;
          });
        },
        onDragEnd: (details) {
          _hoverTimer?.cancel();
          setState(() {
            _dragKey = null;
          });
          if (!_sameKeys(_items, widget.children)) {
            _commit(_items);
          }
        },
        child: dragTarget,
      );
    }

    return content;
  }

  @override
  Widget build(BuildContext context) {
    return DeferredPointerHandler(
      child: MotionGrid(
        crossAxisCount: widget.crossAxisCount,
        crossAxisSpacing: widget.crossAxisSpacing,
        mainAxisSpacing: widget.mainAxisSpacing,
        children: [
          for (int i = 0; i < _items.length; i++)
            _items[i].wrap(
              builder: (child) => _buildEditableWrapper(_items[i], i),
            ),
        ],
      ),
    );
  }
}

class _PresetButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PresetButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _ResizeHandle extends StatefulWidget {
  final void Function(double deltaX, double deltaY) onDeltaResize;

  const _ResizeHandle({required this.onDeltaResize});

  @override
  State<_ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<_ResizeHandle> {
  double _accumulatedX = 0;
  double _accumulatedY = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onPanStart: (_) {
        _accumulatedX = 0;
        _accumulatedY = 0;
      },
      onPanUpdate: (details) {
        _accumulatedX += details.delta.dx;
        _accumulatedY += details.delta.dy;
        if (_accumulatedX.abs() > 40 || _accumulatedY.abs() > 40) {
          widget.onDeltaResize(_accumulatedX, _accumulatedY);
          _accumulatedX = 0;
          _accumulatedY = 0;
        }
      },
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: theme.colorScheme.primary,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 4,
            ),
          ],
        ),
        child: GlyphIcon(
          AppGlyphs.openInFull,
          size: 13,
          color: theme.colorScheme.onPrimary,
        ),
      ),
    );
  }
}
