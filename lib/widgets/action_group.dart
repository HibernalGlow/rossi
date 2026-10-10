// 工具条上「一组图标钮」的统一外壳与度量。
//
// 出处：FlClash（https://github.com/chen08209/FlClash），GPL-3.0 —— 顶栏右上角
// 那两颗图标装在一个胶囊里、组与组之间靠间距分级，是从它那边照搬的观感。
// 本仓原先只有文件管理器一处把它写成了组件（`file_manager_toolbar.dart` 的
// `FileManagerToolbarMetrics` / `FileManagerToolbarGroup`），书架页右上角那两颗
// 是裸 `IconButton`、侧栏底部又是另一套。同一屏上并排看，圆角、内边距、图标尺寸
// 各处各漂一点 —— 这一份把它们收成**一处**。
//
// 为什么不复用 `themeRadius(context)`（`config/global/theme_shape.dart`）：
// 那个是**面板圆角**（用户可调的一档），而工具条分组槽的圆角是组件自己的形状语言
// （全圆），跟着面板圆角走会让「大圆角主题」下这条槽变成一颗药丸蛋。
//
// 这一份只给「横向排的图标组」用。竖排那一档（侧栏底部在窄侧栏里的样子）见
// `ActionGroup` 的 `axis` —— 同一个组换个方向，槽与间距口径不变。
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';

/// 工具条分组槽的度量：**全应用一份**。
///
/// `file_manager_toolbar.dart` 里的 `FileManagerToolbarMetrics` 直接读这里，
/// 所以那边几十处调用点不必改，而数值只会有一处能漂。
abstract final class ActionGroupMetrics {
  /// 图标按钮的见方边长 —— MD3 图标按钮的规范尺寸。
  static const double buttonSize = 40;

  /// 图标本身的边长。一行要塞十几颗控件，MD3 缺省的 24 会把整条拉得比内容还抢眼。
  static const double iconSize = 20;

  /// 同一组之内的间距。
  static const double gapWithinGroup = 4;

  /// 组与组之间的间距。MD3 的分组靠**间距分级**，不靠分隔线 ——
  /// 组内 4、组间 12，一眼能看出哪几颗是一回事。
  static const double gapBetweenGroups = 12;

  /// 分组槽的槽壁厚度。槽在**与排布垂直的那一条**上锁死为 [buttonSize]
  /// （横排锁高、竖排锁宽），所以里头的图标钮与槽外邻居仍然共用同一条 40 的带。
  static const double wellPadding = 2;

  /// 分组槽的圆角：取 [buttonSize] 的一半，即全圆（胶囊）。
  static const double radius = buttonSize / 2;
}

/// 一**组**图标钮共用的下沉槽。
///
/// 取代「每颗按钮自己画一个底」：一组是一个可操作区，组与组用
/// [ActionGroupMetrics.gapBetweenGroups] 分开，不画分隔线。
///
/// [fill] 不传时取 [ColorScheme.surfaceContainer]（「比卡片低一档」）——
/// 卡片底是 `surfaceContainerHigh` 的那几处（工作台里的卡片）读作「这里是一片
/// 可操作区」，而不是又加一层海拔。铺在 app bar 那一类底色上的组（书架页右上角）
/// 另传一档，与同一条栏上的其它容器对齐。
///
/// [axis] 是这一组此刻的排布方向。**同一组动作在侧栏里竖排、在底部 Dock 里横排**
/// （见 `NavigationSidebar.actions` 与 `_showDockActions`），两档用的是同一个槽 ——
/// 换个方向只换 `axis`，圆角、内边距、组内间距都不另写一遍。
class ActionGroup extends StatelessWidget {
  const ActionGroup({
    super.key,
    required this.children,
    this.fill,
    this.axis = Axis.horizontal,
  });

  final List<Widget> children;

  /// 槽的底色。为空时取 [ColorScheme.surfaceContainer]。
  final Color? fill;

  final Axis axis;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isHorizontal = axis == Axis.horizontal;
    return Container(
      // 横排锁**高**、竖排锁**宽** —— 两档都是「锁住与图标钮见方的那一条」，
      // 于是槽里的图标钮与槽外的邻居共用同一条 40 的带（横向的带是高度、
      // 侧栏的带是宽度）。写死的那一条不能两档通用：竖排的槽内容比 40 高，
      // 高度也锁 40 会直接把内容挤爆。
      height: isHorizontal ? ActionGroupMetrics.buttonSize : null,
      width: isHorizontal ? null : ActionGroupMetrics.buttonSize,
      padding: EdgeInsets.symmetric(
        horizontal: isHorizontal ? ActionGroupMetrics.wellPadding : 0,
        vertical: isHorizontal ? 0 : ActionGroupMetrics.wellPadding,
      ),
      decoration: BoxDecoration(
        color: fill ?? colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(ActionGroupMetrics.radius),
      ),
      child: Flex(
        direction: axis,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

/// 工具条里的一颗**瞬时动作**键：后退 / 前进 / 上一级 / 刷新 / 主页 / 搜索。
///
/// 它没有「选中」这一态 —— 按完就完，留下状态的是别的东西。开关见
/// [ActionToggleButton]。
///
/// 配色：常态 `onSurfaceVariant` 图标 + 无底；禁用 `onSurfaceVariant` 38%
/// （MD3 的禁用档就是这个数）。悬停/按压的水波纹由官方 `IconButton` 的状态层承担。
///
/// 图标给两档：[icon] 收 `IconData`（Material 图标），[glyph] 收本仓自绘的
/// `Glyph`（`lib/icons/`）—— 导航栏那一份动作用的是后者。两者只给一个。
/// `GlyphIcon` 自己读 `IconTheme`，而 `IconButton` 会把这一档 [style] 里的
/// `iconSize` 与前景色包成 `IconTheme` 传下去，所以两条路的尺寸与颜色同源。
class ActionIconButton extends StatelessWidget {
  const ActionIconButton({
    super.key,
    this.icon,
    this.glyph,
    required this.tooltip,
    required this.onPressed,
    this.enabled = true,
    this.muted = false,
    this.onLongPress,
  }) : assert(
         (icon == null) != (glyph == null),
         '图标只给一个：icon（IconData）或 glyph（Glyph）',
       );

  final IconData? icon;
  final Glyph? glyph;
  final String tooltip;
  final bool enabled;

  /// 「在这儿了，点了也没去处」：按禁用的样子画，但仍然可点。
  ///
  /// 文件管理器的主页那颗用得上 —— 已经站在主页上时它不再提供「回主页」，
  /// 但长按/右键的主页菜单还得留口，所以不能真的走 [enabled]。
  final bool muted;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;

  /// 整行共用的几何档。[selected] 为真画 `secondaryContainer` 底，
  /// 只有开关态（[ActionToggleButton] 与带值的菜单触发键）用得上；
  /// 各处的菜单触发键也走它，整行才只有一个几何口径。
  static ButtonStyle style(BuildContext context, {bool selected = false}) {
    final colorScheme = Theme.of(context).colorScheme;
    final fg = selected
        ? colorScheme.onSecondaryContainer
        : colorScheme.onSurfaceVariant;
    return ButtonStyle(
      iconSize: const WidgetStatePropertyAll(ActionGroupMetrics.iconSize),
      fixedSize: const WidgetStatePropertyAll(
        Size.square(ActionGroupMetrics.buttonSize),
      ),
      minimumSize: const WidgetStatePropertyAll(
        Size.square(ActionGroupMetrics.buttonSize),
      ),
      maximumSize: const WidgetStatePropertyAll(
        Size.square(ActionGroupMetrics.buttonSize),
      ),
      padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      // 见方的可点区缩到画出来的这一圈：一行要塞十几颗，
      // MD3 的 48 触摸外扩留给正文里的按钮，不留在这条带上。
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: const WidgetStatePropertyAll(CircleBorder(side: BorderSide.none)),
      backgroundColor: WidgetStatePropertyAll(
        selected ? colorScheme.secondaryContainer : Colors.transparent,
      ),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return colorScheme.onSurfaceVariant.withValues(alpha: 0.38);
        }
        return fg;
      }),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return fg.withValues(alpha: 0.12);
        }
        if (states.contains(WidgetState.hovered)) {
          return fg.withValues(alpha: 0.08);
        }
        if (states.contains(WidgetState.focused)) {
          return fg.withValues(alpha: 0.12);
        }
        return Colors.transparent;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final glyph = this.glyph;
    return IconButton(
      tooltip: tooltip,
      onPressed: enabled ? onPressed : null,
      onLongPress: enabled ? onLongPress : null,
      style: style(context).copyWith(
        foregroundColor: muted
            ? WidgetStatePropertyAll(
                colorScheme.onSurfaceVariant.withValues(alpha: 0.38),
              )
            : null,
      ),
      icon: glyph != null ? GlyphIcon(glyph) : Icon(icon),
    );
  }
}

/// 工具条里的一颗**开关**键：文件树、穿透模式、多选、搜索展开。
///
/// 与瞬时动作键唯一的区别就是它有 `on` 这一态，用 MD3 的 tonal 底
/// （`secondaryContainer`）表达「这个功能现在开着」。
///
/// 选中态除了底色还有**填充**：glyph 走 [AnimatedGlyph]，`on` 时描边图标
/// 涨成实心（fill 0→1 的 350ms 过渡 + 一记弹跳），与侧栏选中目的地
/// 同一个口径 —— 只变底色的话，开与关看起来只差一层淡底，太含糊。
class ActionToggleButton extends StatelessWidget {
  const ActionToggleButton({
    super.key,
    this.icon,
    this.glyph,
    required this.tooltip,
    required this.on,
    required this.onPressed,
    this.enabled = true,
  }) : assert(
         (icon == null) != (glyph == null),
         '图标只给一个：icon（IconData）或 glyph（Glyph）',
       );

  final IconData? icon;
  final Glyph? glyph;
  final String tooltip;
  final bool on;
  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final glyph = this.glyph;
    return IconButton(
      isSelected: on,
      tooltip: tooltip,
      onPressed: enabled ? onPressed : null,
      style: ActionIconButton.style(context, selected: on),
      icon: glyph != null
          ? AnimatedGlyph(glyph: glyph, filled: on)
          : Icon(icon),
    );
  }
}
