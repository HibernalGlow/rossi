import 'dart:math' as math;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/workspace/cubit/workspace_cubit.dart';
import 'package:zephyr/workspace/cubit/workspace_state.dart';
import 'package:zephyr/workspace/model/workspace_board_layout.dart';
import 'package:zephyr/workspace/model/workspace_layout_config.dart';
import 'package:zephyr/workspace/model/workspace_workhole.dart';
import 'package:zephyr/workspace/widgets/edges/workhole_panel.dart';
import 'package:zephyr/workspace/widgets/reader/workspace_reader_host.dart';
import 'package:zephyr/i18n/strings.g.dart';

/// Workhole 沉浸容器：中央阅读器保持原位，左右资源以浮层形式出现。
///
/// 左右浮层共享泳道模式的面板注册表和导航状态；Workhole 改变的是呈现方式，
/// 不会因为打开或调整尺寸而重建当前阅读页面。
class ControlledEdgeShell extends StatefulWidget {
  const ControlledEdgeShell({super.key, this.debugLaneContentBuilder});

  /// 布局测试只替换实际内容，手势、浮层和状态记账仍走生产路径。
  /// 与泳道容器使用同一接口，避免测试依赖 ObjectBox 和插件初始化。
  @visibleForTesting
  final Widget Function(String laneId)? debugLaneContentBuilder;

  @override
  State<ControlledEdgeShell> createState() => _ControlledEdgeShellState();
}

class _ControlledEdgeShellState extends State<ControlledEdgeShell> {
  WorkspacePanelSide? _draggingSide;
  double? _dragWidth;
  bool _dragStartedOpen = false;

  static const double _edgeInset = 18;
  static const double _verticalInset = 20;
  static const double _minWidth = 220;
  static const double _closedThreshold = 56;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WorkspaceCubit, WorkspaceState>(
      builder: (context, state) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final viewportWidth = constraints.maxWidth;
            final cubit = context.read<WorkspaceCubit>();
            final leftWidth = _displayWidth(
              WorkspacePanelSide.left,
              state.layout,
              viewportWidth,
            );
            final rightWidth = _displayWidth(
              WorkspacePanelSide.right,
              state.layout,
              viewportWidth,
            );
            final leftVisible = _isVisible(
              WorkspacePanelSide.left,
              state.layout,
            );
            final rightVisible = _isVisible(
              WorkspacePanelSide.right,
              state.layout,
            );

            return Stack(
              children: [
                Positioned.fill(
                  child:
                      widget.debugLaneContentBuilder?.call(LaneId.reader) ??
                      WorkspaceReaderHost(target: state.readerTarget),
                ),
                _buildWorkhole(
                  context,
                  side: WorkspacePanelSide.left,
                  width: leftWidth,
                  visible: leftVisible,
                  layout: state.layout,
                  viewportWidth: viewportWidth,
                  cubit: cubit,
                ),
                _buildWorkhole(
                  context,
                  side: WorkspacePanelSide.right,
                  width: rightWidth,
                  visible: rightVisible,
                  layout: state.layout,
                  viewportWidth: viewportWidth,
                  cubit: cubit,
                ),
                _buildHandle(
                  context,
                  side: WorkspacePanelSide.left,
                  width: leftWidth,
                  visible: leftVisible,
                  layout: state.layout,
                  viewportWidth: viewportWidth,
                ),
                _buildHandle(
                  context,
                  side: WorkspacePanelSide.right,
                  width: rightWidth,
                  visible: rightVisible,
                  layout: state.layout,
                  viewportWidth: viewportWidth,
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildWorkhole(
    BuildContext context, {
    required WorkspacePanelSide side,
    required double width,
    required bool visible,
    required WorkspaceLayoutConfig layout,
    required double viewportWidth,
    required WorkspaceCubit cubit,
  }) {
    final position = side == WorkspacePanelSide.left
        ? <String, double>{
            'left': visible ? _edgeInset : -width - _edgeInset,
            'top': _verticalInset,
            'bottom': _verticalInset,
          }
        : <String, double>{
            'right': visible ? _edgeInset : -width - _edgeInset,
            'top': _verticalInset,
            'bottom': _verticalInset,
          };
    final child = SizedBox(
      width: width,
      child: WorkholePanel(
        side: side,
        size: _sizeFor(side, layout),
        onClose: () => cubit.setEdgeWorkholeOpen(side, false),
        onSizeChanged: (size) => cubit.setEdgeWorkholeSize(side, size),
        onResetSize: () => cubit.resetEdgeWorkholeSize(side),
        debugContent: widget.debugLaneContentBuilder?.call(side.laneId),
      ),
    );
    // 固定 AnimatedPositioned 的身份；拖拽期间仅关掉动画，内容宿主不重挂。
    return AnimatedPositioned(
      duration: _draggingSide == side
          ? Duration.zero
          : const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      left: position['left'],
      right: position['right'],
      top: position['top'],
      bottom: position['bottom'],
      width: width,
      child: IgnorePointer(
        ignoring: !visible,
        child: ExcludeSemantics(excluding: !visible, child: child),
      ),
    );
  }

  Widget _buildHandle(
    BuildContext context, {
    required WorkspacePanelSide side,
    required double width,
    required bool visible,
    required WorkspaceLayoutConfig layout,
    required double viewportWidth,
  }) {
    final cubit = context.read<WorkspaceCubit>();
    final isLeft = side == WorkspacePanelSide.left;
    final offset = visible ? _edgeInset + width - 17 : 0.0;
    // 同一个 GestureDetector 从边缘跟随到面板内沿，整个手势始终归它。
    return AnimatedPositioned(
      key: ValueKey('workhole-handle-${side.name}'),
      duration: _draggingSide == side
          ? Duration.zero
          : const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      left: isLeft ? offset : null,
      right: isLeft ? null : offset,
      top: _verticalInset,
      bottom: _verticalInset,
      width: 34,
      child: Center(
        child: _WorkholeHandle(
          side: side,
          open: visible,
          onTap: () => visible
              ? cubit.setEdgeWorkholeOpen(side, false)
              : cubit.setEdgeWorkholeSize(
                  side,
                  WorkspaceWorkholeSize.workbench,
                ),
          onDragStart: () => _startDrag(
            side,
            _isOpen(side, layout) ? width : 0,
            _isOpen(side, layout),
          ),
          onDragUpdate: (delta) => _updateDrag(side, delta, viewportWidth),
          onDragEnd: () => _finishDrag(context, side, viewportWidth),
          onDragCancel: _cancelDrag,
        ),
      ),
    );
  }

  void _cancelDrag() {
    if (_draggingSide == null) return;
    setState(() {
      _draggingSide = null;
      _dragWidth = null;
      _dragStartedOpen = false;
    });
  }

  void _startDrag(WorkspacePanelSide side, double width, bool wasOpen) {
    setState(() {
      _draggingSide = side;
      _dragWidth = width;
      _dragStartedOpen = wasOpen;
    });
  }

  void _updateDrag(
    WorkspacePanelSide side,
    double delta,
    double viewportWidth,
  ) {
    if (_draggingSide != side || _dragWidth == null) return;
    final direction = side == WorkspacePanelSide.left ? 1 : -1;
    final next = _dragWidth! + delta * direction;
    final maxWidth = _availableWidth(viewportWidth);
    // 保留关闭态的真实拖动距离，才能从边缘拉出后吸附到 peek；
    // 展开态也允许向外拖过关闭阈值，形成「拖回去收起」的连续手势。
    setState(() {
      _dragWidth = next.clamp(0.0, maxWidth);
    });
  }

  void _finishDrag(
    BuildContext context,
    WorkspacePanelSide side,
    double viewportWidth,
  ) {
    final width = _dragWidth ?? 0;
    final startedOpen = _dragStartedOpen;
    final cubit = context.read<WorkspaceCubit>();
    final presets = _presetWidths(viewportWidth);

    setState(() {
      _draggingSide = null;
      _dragWidth = null;
      _dragStartedOpen = false;
    });

    if (width <= _closedThreshold) {
      cubit.setEdgeWorkholeOpen(side, false);
      return;
    }

    if (!startedOpen) {
      final size = width < 150
          ? WorkspaceWorkholeSize.peek
          : width < 420
          ? WorkspaceWorkholeSize.workbench
          : WorkspaceWorkholeSize.takeover;
      cubit.setEdgeWorkholeSize(side, size);
      return;
    }

    WorkspaceWorkholeSize? nearest;
    var nearestDistance = double.infinity;
    for (final entry in presets.entries) {
      final distance = (entry.value - width).abs();
      if (distance < nearestDistance) {
        nearest = entry.key;
        nearestDistance = distance;
      }
    }
    final snapDistance = math.max(42.0, width * 0.14);
    if (nearest != null && nearestDistance <= snapDistance) {
      cubit.setEdgeWorkholeSize(side, nearest);
    } else {
      cubit.setEdgeWorkholeSize(
        side,
        WorkspaceWorkholeSize.custom,
        width: width,
      );
    }
  }

  bool _isVisible(WorkspacePanelSide side, WorkspaceLayoutConfig layout) {
    if (_draggingSide == side) return (_dragWidth ?? 0) > _closedThreshold;
    return switch (side) {
      WorkspacePanelSide.left => layout.edgeLeftOpen,
      WorkspacePanelSide.right => layout.edgeRightOpen,
    };
  }

  double _displayWidth(
    WorkspacePanelSide side,
    WorkspaceLayoutConfig layout,
    double viewportWidth,
  ) {
    if (_draggingSide == side) {
      final width = _dragWidth ?? 0;
      return _clampWidth(math.max(_minWidth, width), viewportWidth);
    }
    final size = _sizeFor(side, layout);
    if (!_isOpen(side, layout)) {
      return _presetWidths(viewportWidth)[WorkspaceWorkholeSize.peek]!;
    }
    if (size == WorkspaceWorkholeSize.custom) {
      final width = side == WorkspacePanelSide.left
          ? layout.edgeLeftWidth
          : layout.edgeRightWidth;
      if (width != null) return _clampWidth(width, viewportWidth);
    }
    return _presetWidths(viewportWidth)[size] ??
        _presetWidths(viewportWidth)[WorkspaceWorkholeSize.workbench]!;
  }

  WorkspaceWorkholeSize _sizeFor(
    WorkspacePanelSide side,
    WorkspaceLayoutConfig layout,
  ) => switch (side) {
    WorkspacePanelSide.left => layout.edgeLeftSize,
    WorkspacePanelSide.right => layout.edgeRightSize,
  };

  bool _isOpen(WorkspacePanelSide side, WorkspaceLayoutConfig layout) =>
      switch (side) {
        WorkspacePanelSide.left => layout.edgeLeftOpen,
        WorkspacePanelSide.right => layout.edgeRightOpen,
      };

  Map<WorkspaceWorkholeSize, double> _presetWidths(double viewportWidth) {
    final maxWidth = math.min(
      _availableWidth(viewportWidth),
      viewportWidth * 0.92,
    );
    double fit(double ratio, double cap) => math.min(
      maxWidth,
      math.max(_minWidth, math.min(viewportWidth * ratio, cap)),
    );

    return {
      WorkspaceWorkholeSize.peek: fit(0.34, 470),
      WorkspaceWorkholeSize.workbench: fit(0.57, 760),
      WorkspaceWorkholeSize.takeover: fit(0.86, 1220),
    };
  }

  double _availableWidth(double viewportWidth) =>
      math.max(0.0, viewportWidth - _edgeInset * 2);

  double _clampWidth(double width, double viewportWidth) {
    final available = _availableWidth(viewportWidth);
    return width.clamp(math.min(_minWidth, available), available);
  }
}

class _WorkholeHandle extends StatelessWidget {
  const _WorkholeHandle({
    required this.side,
    required this.open,
    required this.onTap,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDragCancel,
  });

  final WorkspacePanelSide side;
  final bool open;
  final VoidCallback onTap;
  final VoidCallback onDragStart;
  final ValueChanged<double> onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onDragCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = open
        ? AppGlyphs.dragHandle
        : side == WorkspacePanelSide.left
        ? AppGlyphs.chevronForward
        : AppGlyphs.chevronBack;
    return Tooltip(
      message: open ? t.workspace.dragResizeWorkhole : t.workspace.openWorkhole,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onHorizontalDragStart: (_) => onDragStart(),
        onHorizontalDragUpdate: (details) =>
            onDragUpdate(details.primaryDelta ?? 0),
        onHorizontalDragEnd: (_) => onDragEnd(),
        onHorizontalDragCancel: onDragCancel,
        child: Container(
          width: 30,
          height: open ? 72 : 64,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.92,
            ),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: GlyphIcon(
            icon,
            size: open ? 17 : 18,
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}
