import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/widgets/spring_lens/spring_lens_value.dart';

/// 保留面板状态，位移和透明度共用应用的可重定向弹簧。
/// 连续切换承接当前值和速度，正文只在切换时构建，动画只更新图层。
class RetainedPanelSwitcher extends StatefulWidget {
  const RetainedPanelSwitcher({
    super.key,
    required this.selectedId,
    required this.children,
    this.axis = Axis.horizontal,
  });

  final String selectedId;
  final Map<String, Widget> children;
  final Axis axis;

  @override
  State<RetainedPanelSwitcher> createState() => _RetainedPanelSwitcherState();
}

class _RetainedPanelSwitcherState extends State<RetainedPanelSwitcher>
    with TickerProviderStateMixin {
  final Map<String, _PanelMotion> _panels = {};
  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = eInkInstantRoutes || MediaQuery.disableAnimationsOf(context);
    _syncPanels();
    if (_reduced) {
      for (final entry in _panels.entries) {
        entry.value.alpha.jumpTo(entry.key == widget.selectedId ? 1 : 0);
        entry.value.offset.jumpTo(0);
      }
    }
  }

  void _syncPanels({String? initialSelection}) {
    for (final id in _panels.keys.toList()) {
      if (!widget.children.containsKey(id)) _panels.remove(id)!.dispose();
    }
    for (final id in widget.children.keys) {
      _panels.putIfAbsent(id, () {
        final panel = _PanelMotion(
          this,
          id == (initialSelection ?? widget.selectedId),
        );
        panel.alpha.addListener(_hideSettledPanels);
        return panel;
      });
    }
  }

  @override
  void didUpdateWidget(RetainedPanelSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPanels(initialSelection: oldWidget.selectedId);
    if (widget.selectedId == oldWidget.selectedId) return;
    final ids = widget.children.keys.toList();
    final direction =
        ids.indexOf(widget.selectedId) >= ids.indexOf(oldWidget.selectedId)
        ? 1.0
        : -1.0;
    for (final entry in _panels.entries) {
      final selected = entry.key == widget.selectedId;
      final panel = entry.value;
      if (_reduced) {
        panel.alpha.jumpTo(selected ? 1 : 0);
        panel.offset.jumpTo(0);
        continue;
      }
      if (selected && panel.alpha.value == 0) {
        panel.offset.jumpTo(.045 * direction);
      }
      panel.alpha.springTo(selected ? 1 : 0, LensMetrics.fade);
      panel.offset.springTo(
        selected ? 0 : -.025 * direction,
        LensMetrics.settle,
      );
    }
  }

  void _hideSettledPanels() {
    // 隐藏只发生在退出弹簧抵达零时，不逐帧重建正文。
    if (mounted &&
        !_reduced &&
        _panels.entries.any(
          (entry) =>
              entry.key != widget.selectedId &&
              entry.value.alpha.value == 0 &&
              entry.value.visible,
        )) {
      setState(() {
        for (final entry in _panels.entries) {
          if (entry.key != widget.selectedId && entry.value.alpha.value == 0) {
            entry.value.visible = false;
          }
        }
      });
    }
  }

  @override
  void dispose() {
    for (final panel in _panels.values) {
      panel.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRect(
    child: Stack(
      fit: StackFit.expand,
      children: [
        for (final entry in widget.children.entries)
          _panel(entry.key, entry.value),
      ],
    ),
  );

  Widget _panel(String id, Widget child) {
    final selected = id == widget.selectedId;
    final motion = _panels[id]!;
    motion.visible = selected || motion.alpha.value > 0;
    return Offstage(
      key: ValueKey(id),
      offstage: !motion.visible,
      child: TickerMode(
        enabled: selected,
        child: IgnorePointer(
          ignoring: !selected,
          child: ExcludeSemantics(
            excluding: !selected,
            child: SlideTransition(
              position: motion.position(widget.axis),
              child: FadeTransition(
                opacity: motion.opacity,
                child: RepaintBoundary(child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PanelMotion {
  _PanelMotion(TickerProvider vsync, bool selected)
    : alpha = SpringLensValue(vsync, selected ? 1 : 0),
      offset = SpringLensValue(vsync, 0);
  final SpringLensValue alpha;
  final SpringLensValue offset;
  bool visible = false;
  late final opacity = Animation<double>.fromValueListenable(
    alpha,
    transformer: (value) => value.clamp(0, 1),
  );
  Animation<Offset> position(Axis axis) =>
      Animation<double>.fromValueListenable(offset).drive(
        Tween<Offset>(
          begin: Offset.zero,
          end: axis == Axis.vertical ? const Offset(0, 1) : const Offset(1, 0),
        ),
      );
  void dispose() {
    alpha.dispose();
    offset.dispose();
  }
}
