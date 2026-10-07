part of '../reader_settings_sheet.dart';

/// 面板在**泳道之外**的那一片空白里的出口。
///
/// # 为什么遮罩不够用
///
/// 阅读设置挂在阅读器泳道自己的局部 `Navigator` 上（`workspace_reader_host.dart:111`，
/// 给这条泳道单独一条路由栈是为了「返回」不被凭空插出来、弹层只作用在本泳道）。
/// 代价是这条路由的遮罩只盖住**本泳道的 Overlay**：泳道以外（别的泳道、工作台顶栏、
/// 空画布）那一片没有任何东西接住这一下，点上去面板纹丝不动 —— 实测三条：
/// 框内上方空白能收、泳道内侧边遮罩能收、泳道外**不能**收。
///
/// # 为什么走全局指针路由而不是在窗口上盖一层
///
/// 在 `GestureBinding.instance.pointerRouter` 上挂全局路由，拿到的是**每一次**
/// 指针事件，且完全不参与命中测试：不需要在谁的树上加 `Listener`，也不用挑
/// 「哪个祖先能看见所有泳道」。盖一层 `Positioned.fill` 反而是灾难 ——
/// `HitTestBehavior.translucent` 的填充层会让同层 Stack 里它下面的兄弟节点
/// 再也收不到指针。
///
/// # 为什么只管「Overlay 之外」
///
/// Overlay 之内由路由自己的遮罩/框内点击层负责。两边都动手就会 pop **两次**，
/// 第二次退掉的就不是面板，而是底下的阅读器页。所以这里只在「按下与抬起都落在
/// 本 Overlay 之外」时接手，其余一律不碰。
class _ReaderSettingsOutsideTapScope extends StatefulWidget {
  final Widget child;

  const _ReaderSettingsOutsideTapScope({required this.child});

  @override
  State<_ReaderSettingsOutsideTapScope> createState() =>
      _ReaderSettingsOutsideTapScopeState();
}

class _ReaderSettingsOutsideTapScopeState
    extends State<_ReaderSettingsOutsideTapScope> {
  /// 这一下的起点是否落在本 Overlay 之外；null = 没在观察。
  bool? _downOutside;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    super.dispose();
  }

  /// 承载这条面板的 Overlay 在窗口里的矩形 —— 也就是「面板够得着的那一片」。
  Rect? _hostRect() {
    final box = Overlay.maybeOf(context)?.context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _onPointer(PointerEvent event) {
    if (_closing) return;
    if (event is PointerDownEvent) {
      final host = _hostRect();
      if (host == null) return;
      _downOutside = !host.contains(event.position);
      return;
    }
    if (event is PointerUpEvent) {
      final startedOutside = _downOutside ?? false;
      _downOutside = null;
      if (!startedOutside) return;
      final host = _hostRect();
      if (host == null || host.contains(event.position)) return;
      _closing = true;
      // 与 Esc 那条同一口径：先让焦点失焦，pop 推到下一帧，
      // 免得在指针事件的派发过程中同步改路由栈。
      FocusManager.instance.primaryFocus?.unfocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
      return;
    }
    if (event is PointerCancelEvent) _downOutside = null;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
