import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:zephyr/reader/ambient_palette.dart';

/// 阅读背景「自适应取色」的唯一一份共享状态。
///
/// # 为什么是单例而不是挂在阅读页 State 上
///
/// 取色的**产生方**在呈现链路里（`GpuPresentController.present` 之后读一次探针），
/// 而**消费方**是阅读器最底层的背景层 —— 两者在 widget 树上的距离很远，
/// 中间隔着阅读模式、翻页容器、图片节点好几层。把它们连起来有三条路：
///
/// 1. 一路 `InheritedWidget` 往下传：要穿过每一层的构造参数，改动面最大；
/// 2. 挂在本页的 State 上：**换书即重置**，而且背景层要拿它得先能拿到那个 State；
/// 3. 一份阅读器级的共享状态（这里）。
///
/// 选 3 的理由与 `LocalReadSession` / `UpscaledImageCache.replacements` 同源：
/// 这类状态的生命周期本来就跟"当前这一个阅读会话"绑定，而不是跟某一棵子树绑定。
///
/// # 它必须是**独立于呈现器**的 ValueNotifier
///
/// `GpuPresentController` 本身是个 `ChangeNotifier`，而 `ImageSurface` 正在监听它
/// （一收到通知就 `setState`，随后可能再走一次 `present`）。把颜色并进那个通知里，
/// 每次取色到达都会让**图片节点重建一次** —— 那正是「不能影响阅读」要防的事。
/// 分开一个 notifier 之后，颜色变化只惊动背景层那一棵子树。
///
/// 另外它还是**非本平台（Linux / 移动端 / 在线漫画）**的兜底：那些情况下没人往里写，
/// `value` 恒为 `null`，背景层照常画静态底色，功能自然失效而不是报错。
class ReaderAmbientStore {
  ReaderAmbientStore._();

  /// 只给判据用：独立实例，避免与全局 [instance] 串测试状态。
  @visibleForTesting
  ReaderAmbientStore.forTest();

  static final ReaderAmbientStore instance = ReaderAmbientStore._();

  /// 当前这一页的调色板。`null` = 还没有 / 这一页没采到 / 这条路不适用。
  final ValueNotifier<ReaderAmbientPalette?> palette =
      ValueNotifier<ReaderAmbientPalette?>(null);

  /// 发布一份调色板。
  ///
  /// 「同值不写」由 [ValueNotifier] 自己保证：setter 按 `==` 判同值不通知，
  /// 而 [ReaderAmbientPalette] 有逐字段的值相等语义。这里刻意**不再**叠一层
  /// 自造的比较 —— 早期版本在这里用 `toString()` 判同值，可默认的
  /// `Object.toString()` 只返回 `Instance of '…'`、不含任何字段值，
  /// 两个不同的调色板比出来永远相等，翻页后背景色就永远冻在第一页。
  void publish(ReaderAmbientPalette? value) {
    palette.value = value;
  }

  /// 退回"没有自适应颜色"（换书、离开阅读器）。
  void clear() {
    publish(null);
  }
}

/// 阅读背景的**底层**：静态底色 + 自适应取色。
///
/// # 它为什么必须是一层独立的东西
///
/// 阅读器的底色现在是一路 `Container(color:)` 传下去的（`read_mode_slot_builder`
/// 的 `backgroundColor` 就是这么来的）。把动态取色塞进那条链路会有两个后果：
///
/// 1. **每次变色都重建整棵阅读子树** —— `Container` 的颜色来自 `context.select`，
///    一变就是 `Stack` / `InteractiveViewer` / 所有页面节点重来一遍；
/// 2. 中间还有别的消费者（占位框、转场卡片）会跟着一起变。
///
/// 所以取色**不进那条链路**：静态底色照旧按 `readSetting` 算，自适应颜色只在
/// 这一层里叠加。这一层被 [RepaintBoundary] 圈住，颜色变化只重绘它自己，
/// 而它又压在页面**下面** —— 页面的绘制完全不参与。
///
/// # 动画的代价是**有界**的
///
/// 过渡（对齐 neoview 的 `transition: background-color 300ms ease`）只在
/// **翻页那一次**跑 300 ms，跑完就静止 —— 不是常驻动画。这也正是这里不做
/// 「流光溢彩 / 极光 / 聚光灯」那三档的原因：常驻动画在阅读器里是持续的
/// GPU 开销，与「不能影响阅读」直接冲突。
///
/// 全局关掉动画（阅读设置里的 `noAnimation`）时连这 300 ms 也省掉，直接切色。
class ReaderAmbientBackground extends StatelessWidget {
  const ReaderAmbientBackground({
    super.key,
    required this.baseColor,
    required this.palette,
    required this.enabled,
    required this.edgeMode,
    required this.dimPercent,
    required this.animate,
  });

  /// 静态底色（`resolveReaderBackgroundColor` 的结果）。
  ///
  /// 取色还没到、或这一页没采到、或这条上屏路不适用时，看到的就是它。
  final Color baseColor;

  /// 调色板来源。正常传 [ReaderAmbientStore.palette]。
  final ValueListenable<ReaderAmbientPalette?> palette;

  /// 当前档位是不是自适应那一档（`adaptive` / `adaptiveEdge`）。
  final bool enabled;

  /// [enabled] 为真时，画「边缘渐变」还是「单色铺底」。
  final bool edgeMode;

  /// 压暗程度（0..100）。见 [ReaderAmbientPalette.dimmed]。
  final int dimPercent;

  /// 是否走 300 ms 缓变。
  final bool animate;

  /// 一次取色过渡的时长。与 neoview 的 `transition: background-color 300ms` 同值。
  static const Duration transitionDuration = Duration(milliseconds: 300);

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ValueListenableBuilder<ReaderAmbientPalette?>(
        valueListenable: palette,
        builder: (BuildContext context, ReaderAmbientPalette? value, _) {
          // 没开这个档位、或这一页没采到 → 目标就是"四边色标都等于静态底色"，
          // 于是「固定底色 ⇄ 自适应」这条切换与「这一页 ⇄ 下一页」走的是同一条插值。
          final ReaderAmbientPalette target = (enabled && value != null)
              ? value
              : ReaderAmbientPalette.flat(baseColor);

          if (!animate) {
            return _AmbientSurface(
              palette: target,
              edgeMode: edgeMode,
              dimPercent: dimPercent,
            );
          }

          return TweenAnimationBuilder<ReaderAmbientPalette>(
            tween: _AmbientPaletteTween(begin: target, end: target),
            duration: transitionDuration,
            curve: Curves.easeOut,
            builder:
                (
                  BuildContext context,
                  ReaderAmbientPalette animated,
                  Widget? _,
                ) => _AmbientSurface(
                  palette: animated,
                  edgeMode: edgeMode,
                  dimPercent: dimPercent,
                ),
          );
        },
      ),
    );
  }
}

/// 真正画背景的那一层：单色铺底，或四边渐变。
class _AmbientSurface extends StatelessWidget {
  const _AmbientSurface({
    required this.palette,
    required this.edgeMode,
    required this.dimPercent,
  });

  final ReaderAmbientPalette palette;
  final bool edgeMode;
  final int dimPercent;

  @override
  Widget build(BuildContext context) {
    final ReaderAmbientPalette dimmed = palette.dimmed(dimPercent);
    if (!edgeMode) {
      return ColoredBox(color: dimmed.average);
    }
    // 四边渐变 = 代表色打底 + 四条边各自一条"从边色融进底色"的线性渐变。
    // 层序与 neoview 的 CSS 一致（上 / 下 / 左 / 右 依次叠上去）。
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        ColoredBox(color: dimmed.average),
        _edgeLayer(
          dimmed.top,
          dimmed.average,
          Alignment.topCenter,
          Alignment.bottomCenter,
        ),
        _edgeLayer(
          dimmed.bottom,
          dimmed.average,
          Alignment.bottomCenter,
          Alignment.topCenter,
        ),
        _edgeLayer(
          dimmed.left,
          dimmed.average,
          Alignment.centerLeft,
          Alignment.centerRight,
        ),
        _edgeLayer(
          dimmed.right,
          dimmed.average,
          Alignment.centerRight,
          Alignment.centerLeft,
        ),
      ],
    );
  }

  Widget _edgeLayer(
    List<Color> stops,
    Color fade,
    Alignment begin,
    Alignment end,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: edgeGradient(
          stops: stops,
          fade: fade,
          begin: begin,
          end: end,
        ),
      ),
    );
  }
}

/// 把一条边的色标铺成「边色 → 代表色」的线性渐变。
///
/// 口径照 neoview 的 `edgeFrameToPresentation` / `stopsAcross`：色标铺在渐变轴前
/// 42%，之后由 70% 处的代表色接手 —— 页面边色因此不是"到中段突然断掉"，
/// 而是从边缘往里逐渐融进背景。
///
/// 做成顶层函数是为了能被测试直接驱动：它是这一层唯一的几何/颜色约定。
@visibleForTesting
LinearGradient edgeGradient({
  required List<Color> stops,
  required Color fade,
  required Alignment begin,
  required Alignment end,
}) {
  final int last = stops.length <= 1 ? 1 : stops.length - 1;
  return LinearGradient(
    begin: begin,
    end: end,
    colors: <Color>[...stops, fade],
    stops: <double>[
      for (int index = 0; index < stops.length; index++) (index / last) * 0.42,
      0.70,
    ],
  );
}

/// 让 [ReaderAmbientPalette] 能被 `TweenAnimationBuilder` 当值用。
///
/// 用自定义 Tween 而不是 `AnimatedContainer`：`AnimatedContainer` 只能对**单个**
/// `BoxDecoration` 插值，而「边缘渐变」是四层渐变叠出来的，没有对应的单值表示。
class _AmbientPaletteTween extends Tween<ReaderAmbientPalette> {
  _AmbientPaletteTween({
    required ReaderAmbientPalette super.begin,
    required ReaderAmbientPalette super.end,
  });

  @override
  ReaderAmbientPalette lerp(double t) => begin!.lerpTo(end!, t);
}
