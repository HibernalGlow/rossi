import 'package:material_ui/material_ui.dart';
import 'package:plat/plat.dart';

/// rossi 的 MD3 口径套到 plat 的 chrome 上。
///
/// # 两个朝向是两种 MD3 组件，不是同一套数值转 90°
///
/// - **横向档 = MD3 Tabs**：标签自己不填色，选中只靠一条**内缩的圆角下划线**
///   加字色变化。
/// - **竖向档 = MD3 Navigation rail / drawer 那一族**：选中是一条 `secondaryContainer`
///   圆角底板（drawer 的画法），字号用 rail 那一档 label-medium —— 轨的宽度整块从
///   内容区扣，撑不起 drawer 的 14。右沿**不再**画那根通高的竖线。
///
/// 原来两处都不像 MD3，根因是把这两种语言叠在了一起：横档既有 `surfaceContainerHigh`
/// 方块又有一根通宽的硬线，竖档则是「方块 + 通高方角线」。
///
/// plat 自己的默认值已经**按 MD3 取色**了（分隔条：常态 `outlineVariant`、
/// 悬停/拖动 `primary`；落点提示：`primary` 18% 底 + 2px 边）。那些不需要我们重抄一遍 ——
/// 抄了就有了第二份口径，改主题时只改一处。这里补的是 plat 的默认值**不适配本应用**的四处：
///
/// 1. **条/轨的厚度与内边距**：plat 默认 32 高的条、标签内边距 12×8，横档撑不满
///    本应用的 48 顶栏，竖档又会在窄轨上把标签名挤到溢出；
/// 2. **选中底板**：plat 默认给选中项铺 `surfaceContainerHigh`，横档要的是「不填」，
///    竖档要的是 `secondaryContainer`；
/// 3. **字号**：横档是 label-large（14）、竖轨是 label-medium（12），而本应用的
///    `TextTheme` token 压根不带字号（见 [labelStyle] / [railLabelStyle]），
///    不显式写就永远停在默认那一档；
/// 4. **分隔条的命中区**：默认太薄，鼠标要正好压在那根线上才拖得动。
///
/// 悬停/按下的状态层（onSurface 8% / primary 10%）仍走 plat 的默认值，
/// 这样换主题（含动态取色 / AMOLED）它自己跟着走。
class RossiPlatTheme extends StatelessWidget {
  const RossiPlatTheme({
    super.key,
    required this.barThickness,
    required this.vertical,
    required this.child,
  });

  /// 条（横向档 = 高）/ 轨（竖向档 = 宽）的厚度。
  final double barThickness;

  /// 当前是不是竖向轨。决定标签沿哪条轴排、以及分隔条是竖是横。
  final bool vertical;

  final Widget child;

  /// 横向：标签左右各 12，MD3 Tabs 的标签内边距。
  static const EdgeInsets chipLabelPadding = EdgeInsets.symmetric(
    horizontal: 12,
  );

  /// 竖向：轨厚出来的每一像素都是从内容区扣的，所以左右比横档窄一档，
  /// 上下留出呼吸，选中底板才不会贴到上一条的下沿。
  static const EdgeInsets railLabelPadding = EdgeInsets.symmetric(
    horizontal: 6,
    vertical: 7,
  );

  /// 条自己的内边距。横向**不给上下**：下划线要贴着条的下沿，
  /// 给了就把那条线抬起来悬在内容上。
  static const EdgeInsets barPadding = EdgeInsets.symmetric(horizontal: 8);
  static const EdgeInsets railPadding = EdgeInsets.symmetric(
    horizontal: 6,
    vertical: 8,
  );

  /// 下划线：3 厚、两端全圆、左右各内缩 12（约等于标签文字那一段的宽度）。
  static const double indicatorThickness = 3;
  static const EdgeInsets indicatorInset = EdgeInsets.symmetric(horizontal: 12);

  /// 选中底板的圆角：横档只包住悬停状态层，竖档是那条 pill。
  static const double chipRadius = 8;
  static const double railChipRadius = 16;

  /// 分隔条画 1 逻辑像素，但命中区给到 9（两侧各 4）。
  static const double dividerThickness = 1;
  static const double dividerHitSlop = 4;

  /// 横档那一档字 = MD3 Tabs 的 label-large（14 / w500）。
  ///
  /// 字号**只能显式写**：material_ui 的 typography token 里 `fontSize` 是 null
  /// （只有 family / color / decoration），`MaterialUiCompatibilityBridge` 又是原样
  /// 把它搬进 legacy `TextTheme` 的 —— 所以「改拿 `labelLarge`」在这个应用里
  /// 一个像素都不会变，看着像换了档其实什么都没换。
  static const TextStyle labelStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
  );

  /// 竖轨那一档字 = MD3 Navigation rail 的 label-medium（12 / w500）。
  ///
  /// 两个朝向分开不是随手定的：轨的宽度整块从内容区扣，字号从 12 涨到 14，
  /// 132 宽的轨上「绅士 · よろず」就要多截掉一个字。
  static const TextStyle railLabelStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return PlatTheme(
      data: PlatThemeData(
        tabBar: vertical
            ? PlatTabBarTheme(
                size: barThickness,
                fit: TabStripFit.scrollable,
                spacing: 4,
                padding: railPadding,
                labelPadding: railLabelPadding,
                chipBorderRadius: BorderRadius.circular(railChipRadius),
                labelStyle: railLabelStyle,
                unselectedLabelStyle: railLabelStyle,
                // 0 = 不画线（`_indicatorBorder` 与堆叠那条都短路），选中只留底板。
                indicatorWeight: 0,
                chipBackgroundColor: WidgetStateProperty.resolveWith(
                  (states) => _railChipBackground(colors, states),
                ),
                chipForegroundColor: WidgetStateProperty.resolveWith(
                  (states) => _railChipForeground(colors, states),
                ),
              )
            : PlatTabBarTheme(
                size: barThickness,
                fit: TabStripFit.scrollable,
                spacing: 4,
                padding: barPadding,
                labelPadding: chipLabelPadding,
                chipBorderRadius: BorderRadius.circular(chipRadius),
                labelStyle: labelStyle,
                unselectedLabelStyle: labelStyle,
                indicator: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(indicatorThickness / 2),
                ),
                indicatorWeight: indicatorThickness,
                indicatorPadding: indicatorInset,
                chipBackgroundColor: WidgetStateProperty.resolveWith(
                  (states) => _chipBackground(colors, states),
                ),
                chipForegroundColor: WidgetStateProperty.resolveWith(
                  (states) => _chipForeground(colors, states),
                ),
              ),
        divider: const PlatDividerTheme(
          thickness: dividerThickness,
          hitSlop: dividerHitSlop,
        ),
      ),
      child: child,
    );
  }

  /// 拖起的那一份要能从内容里读出来，所以只有 `dragged` 给实色；
  /// 常态与选中都是透明 —— 横档的选中态全部交给下划线与字色。
  static Color _chipBackground(ColorScheme colors, Set<WidgetState> states) {
    if (states.contains(WidgetState.dragged)) {
      return Color.alphaBlend(
        colors.primary.withValues(alpha: 0.26),
        colors.surfaceContainerHigh,
      );
    }
    return Colors.transparent;
  }

  /// MD3 Tabs 的选中项：字与图标都取 `primary`（Flutter 自己的 `TabBar` 同一口径），
  /// 与那条 `primary` 下划线是同一个信号；未选中取 `onSurfaceVariant`。
  static Color _chipForeground(ColorScheme colors, Set<WidgetState> states) {
    return states.contains(WidgetState.selected)
        ? colors.primary
        : colors.onSurfaceVariant;
  }

  static Color _railChipBackground(
    ColorScheme colors,
    Set<WidgetState> states,
  ) {
    if (states.contains(WidgetState.dragged)) {
      return Color.alphaBlend(
        colors.secondary.withValues(alpha: 0.26),
        colors.surfaceContainerHigh,
      );
    }
    if (states.contains(WidgetState.selected)) return colors.secondaryContainer;
    return Colors.transparent;
  }

  static Color _railChipForeground(
    ColorScheme colors,
    Set<WidgetState> states,
  ) {
    if (states.contains(WidgetState.selected)) {
      return colors.onSecondaryContainer;
    }
    return colors.onSurfaceVariant;
  }
}
