import 'package:material_ui/material_ui.dart';
import 'package:plat/plat.dart';

/// rossi 的 MD3 口径套到 plat 的 chrome 上。
///
/// # 只管三件事
///
/// plat 自己的默认值已经**按 MD3 取色**了（分隔条：常态 `outlineVariant`、
/// 悬停/拖动 `primary`；落点提示：`primary` 18% 底 + 2px 边）。那些不需要我们重抄一遍 ——
/// 抄了就有了第二份口径，改主题时只改一处。这里补的是 plat 的默认值**不适配本应用**的三处：
///
/// 1. **条/轨的厚度**：横向一条 40、竖向一轨由调用方给（用户可拖）；
/// 2. **标签内边距**：Material 的 TabBar 默认给 16×2，窄轨上那 32 就是
///    「标签名明明没超长、Row 却溢出」的来源；
/// 3. **分隔条的命中区**：默认太薄，鼠标要正好压在那根线上才拖得动。
///
/// 其余（圆角、字色、选中底板）留给 plat 走 `ThemeData.tabBarTheme` 的回退链，
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

  /// 标签左右各 4：窄轨上多出来的每一像素都是从内容区扣的。
  static const EdgeInsets chipLabelPadding = EdgeInsets.symmetric(
    horizontal: 4,
  );

  /// 分隔条画 1 逻辑像素，但命中区给到 9（两侧各 4）。
  static const double dividerThickness = 1;
  static const double dividerHitSlop = 4;

  @override
  Widget build(BuildContext context) {
    return PlatTheme(
      data: PlatThemeData(
        tabBar: PlatTabBarTheme(
          size: barThickness,
          fit: TabStripFit.scrollable,
          spacing: 2,
          labelPadding: chipLabelPadding,
          padding: EdgeInsets.symmetric(horizontal: vertical ? 4 : 2),
        ),
        divider: const PlatDividerTheme(
          thickness: dividerThickness,
          hitSlop: dividerHitSlop,
        ),
      ),
      child: child,
    );
  }
}
