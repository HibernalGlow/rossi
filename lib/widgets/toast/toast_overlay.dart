// 提示条（toast）的宿主：往根 Overlay 上挂一层「九宫格 + 多列堆叠」的浮层。
//
// 为什么不用现成的 toast 库：位置、宽度、透明度、堆叠数量这些都要让用户可配，
// 而常见库的宽度是**管理器级的固定值**（第一次弹过后就冻结），做不到。
// 这里自己控 OverlayEntry，规格全部来自 `resolveToastOverlaySpec(setting)`。
//
// 对外只暴露 [ToastOverlayController.instance.show]，调用点不必知道这些细节。

import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/util/toast/toast_style.dart';
import 'package:zephyr/widgets/toast/toast_card.dart';

/// 一条正在显示（或正在退场）的提示。
class ActiveToast {
  ActiveToast({
    required this.id,
    required this.type,
    required this.message,
    required this.spec,
    this.title,
  });

  final int id;
  final ToastType type;
  final String message;
  final String? title;
  final ToastOverlaySpec spec;

  /// 退场动画期间为 false。
  bool visible = true;

  /// 已经进入退场流程（避免重复排队移除）。
  bool exiting = false;
}

class ToastOverlayController extends ChangeNotifier {
  ToastOverlayController._();

  static final ToastOverlayController instance = ToastOverlayController._();

  final List<ActiveToast> _toasts = [];
  OverlayEntry? _entry;
  OverlayState? _overlay;
  int _nextId = 1;

  List<ActiveToast> get toasts => List.unmodifiable(_toasts);

  /// 弹一条提示。
  ///
  /// [duration] 非空时覆盖设置里的时长（调用点显式指定优先）；
  /// `Duration.zero` 表示常驻，此时强制保留关闭按钮。
  void show(
    BuildContext context, {
    required ToastType type,
    required String message,
    String? title,
    Duration? duration,
  }) {
    if (message.trim().isEmpty || !context.mounted) {
      return;
    }

    final overlay =
        Overlay.maybeOf(context, rootOverlay: true) ?? Overlay.maybeOf(context);
    if (overlay == null) {
      logger.w('toast: 当前上下文找不到 Overlay，丢弃提示「$message」');
      return;
    }
    _attach(overlay);

    var spec = resolveToastOverlaySpec(toastSetting);
    if (duration != null) {
      spec = spec.withDuration(duration);
    }

    final toast = ActiveToast(
      id: _nextId++,
      type: type,
      title: title,
      message: message,
      spec: spec,
    );
    _toasts.add(toast);

    // 超出同屏上限：最旧的先走（和其它退场走同一条动画路径）。
    final overflow = _toasts.length - spec.maxVisible;
    if (overflow > 0) {
      for (final stale in _toasts.take(overflow).toList()) {
        _beginExit(stale);
      }
    }

    notifyListeners();
  }

  void dismiss(int id) {
    for (final toast in _toasts) {
      if (toast.id == id) {
        _beginExit(toast);
        return;
      }
    }
  }

  void _beginExit(ActiveToast toast) {
    if (toast.exiting) return;
    toast.exiting = true;
    toast.visible = false;
    notifyListeners();

    final delay = toast.spec.animationDuration;
    Future.delayed(
      delay == Duration.zero ? const Duration(milliseconds: 1) : delay,
      () {
        if (_toasts.remove(toast)) {
          notifyListeners();
          if (_toasts.isEmpty) {
            _scheduleDetach();
          }
        }
      },
    );
  }

  void _attach(OverlayState overlay) {
    if (identical(_overlay, overlay) && _entry != null) return;
    // 换了 Overlay（Widget 测试里每个用例一棵新树；正式环境只在重建根节点时发生）
    // 必须重新挂，否则会往一棵已经拆掉的树上推重建。
    _releaseEntry();
    final entry = OverlayEntry(
      builder: (context) => ToastHostView(controller: this),
    );
    _overlay = overlay;
    _entry = entry;
    overlay.insert(entry);
  }

  /// 卸载必须排到帧末：`remove()` 在构建期调用会直接抛异常。
  void _scheduleDetach() {
    final entry = _entry;
    if (entry == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_toasts.isNotEmpty || !identical(_entry, entry)) return;
      _releaseEntry();
    });
  }

  void _releaseEntry() {
    final entry = _entry;
    _overlay = null;
    _entry = null;
    if (entry == null) return;
    try {
      if (entry.mounted) {
        entry.remove();
      }
      entry.dispose();
    } catch (_) {
      // 宿主 Overlay 已经跟着整棵树拆掉了 —— 这时候没有东西可卸，忽略即可。
    }
  }

  /// 每个 Widget 用例开始前清干净（单例跨用例会串味）。
  @visibleForTesting
  void resetForTest() {
    _toasts.clear();
    _releaseEntry();
  }
}

/// 浮层本体：按对齐方式分组，每组一个 Column。
class ToastHostView extends StatelessWidget {
  const ToastHostView({super.key, required this.controller});

  final ToastOverlayController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final groups = <Alignment, List<ActiveToast>>{};
        for (final toast in controller.toasts) {
          groups.putIfAbsent(toast.spec.alignment, () => []).add(toast);
        }
        if (groups.isEmpty) {
          return const SizedBox.shrink();
        }

        return SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              for (final group in groups.entries)
                _ToastGroup(
                  alignment: group.key,
                  toasts: group.value,
                  controller: controller,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ToastGroup extends StatelessWidget {
  const _ToastGroup({
    required this.alignment,
    required this.toasts,
    required this.controller,
  });

  final Alignment alignment;
  final List<ActiveToast> toasts;
  final ToastOverlayController controller;

  @override
  Widget build(BuildContext context) {
    final padding = EdgeInsets.all(toasts.last.spec.edgePadding);
    // 贴底的一组把「最新的一条」放在最靠边的位置，贴顶的顺着往下长。
    final ordered = alignment.y >= 0 ? toasts.reversed.toList() : toasts;

    return Padding(
      padding: padding,
      child: Align(
        alignment: alignment,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final toast in ordered)
              _ToastSlot(
                key: ValueKey(toast.id),
                toast: toast,
                controller: controller,
              ),
          ],
        ),
      ),
    );
  }
}

class _ToastSlot extends StatefulWidget {
  const _ToastSlot({super.key, required this.toast, required this.controller});

  final ActiveToast toast;
  final ToastOverlayController controller;

  @override
  State<_ToastSlot> createState() => _ToastSlotState();
}

class _ToastSlotState extends State<_ToastSlot> {
  /// 先以「收起」状态渲染一帧，再翻成展开 —— 否则隐式动画没有起点，进场会硬切。
  bool _entered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _entered = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final toast = widget.toast;
    final spec = toast.spec;
    final shown = toast.visible && _entered;
    final offset = Offset(
      spec.alignment.x == 0 ? 0 : (spec.alignment.x > 0 ? 0.06 : -0.06),
      spec.alignment.y == 0 ? 0 : (spec.alignment.y > 0 ? 0.22 : -0.22),
    );

    return AnimatedSlide(
      offset: shown ? Offset.zero : offset,
      duration: spec.animationDuration,
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: shown ? 1 : 0,
        duration: spec.animationDuration,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ToastCard(
            type: toast.type,
            title: toast.title,
            message: toast.message,
            spec: spec,
            onDismiss: () => widget.controller.dismiss(toast.id),
          ),
        ),
      ),
    );
  }
}
