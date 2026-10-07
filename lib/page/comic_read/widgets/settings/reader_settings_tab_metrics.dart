import 'package:material_ui/material_ui.dart';

/// 阅读设置标签栏「图标+文字 还是 只留图标」的判据。
///
/// # 为什么不写死一个 dp 阈值
///
/// 5 个标签的自然宽度取决于**当前语言的标签有多长**：中文「阅读/手势/界面/画面/翻译」
/// 两颗字，英文 "Reading/Gestures/Interface/Display/Translate" 差两三倍宽。
/// 写死 360 之类的数字，等于给英文用户一套恰好挤不下的排版、给中文用户一套
/// 早就该收成图标却没收的排版。
///
/// 所以这里直接量：把每个标签的文字按 tab 用的字号排一遍取宽度，取
/// `max(图标宽, 文字宽) + 左右 labelPadding` 作为该 tab 的自然宽度，求和后与
/// 实际可用宽度比。超了就只画图标（图标 tab 自己那一套宽度同样算得出来）。
///
/// # 为什么用 [TextPainter] 而不是 `IntrinsicWidth`
///
/// `TabBar` 不支持内在尺寸，包一层 `IntrinsicWidth` 只能得到「撑满」的结果。
/// TextPainter 量的是真实字体的排版宽度，和 tab 里那颗 [Text] 拿到的是同一套
/// 度量（含 `textScaler`，无障碍放大时该收就收）。
class ReaderSettingsTabMetrics {
  ReaderSettingsTabMetrics._();

  /// MD3 图标+文字 tab 的高度（material_ui `_kTextAndIconTabHeight`）。
  static const double textAndIconTabHeight = 72;

  /// MD3 纯文字 / 纯图标 tab 的高度（material_ui `_kTabHeight`）。
  static const double compactTabHeight = 46;

  /// tab 内容的左右内边距（material_ui `kTabLabelPadding`）。
  static const double labelHorizontalPadding = 16;

  /// tab 里图标的默认边长。
  static const double iconSize = 24;

  /// 图标与文字之间的间距（material_ui `_TabsDefaultsM3.iconMargin`）。
  static const double iconMargin = 2;

  /// 单个 tab 的自然宽度：内容取图标与文字里更宽的那个，再加左右 padding。
  static double tabNaturalWidth({
    required double labelWidth,
    bool withIcon = true,
  }) {
    final contentWidth = withIcon
        ? iconSize > labelWidth
              ? iconSize
              : labelWidth
        : labelWidth;
    return contentWidth + labelHorizontalPadding * 2;
  }

  /// 一排标签需要的总宽度。
  static double rowNaturalWidth({
    required List<String> labels,
    required TextStyle? labelStyle,
    required TextScaler scaler,
    double textWidthFactor = 1.0,
    bool withIcon = true,
  }) {
    double total = 0;
    for (final label in labels) {
      total += tabNaturalWidth(
        labelWidth: measureLabelWidth(
          label: label,
          labelStyle: labelStyle,
          scaler: scaler,
          textWidthFactor: textWidthFactor,
        ),
        withIcon: withIcon,
      );
    }
    return total;
  }

  /// 量一颗标签的文字宽度。
  ///
  /// [textWidthFactor] 是测试注入口：`flutter test` 用的替代字体每个字形都是
  /// 正方形，量出来的宽度和真机字体不是一个量级，没法用它验证「刚好挤不下」
  /// 那一侧的行为。生产传 1.0。
  static double measureLabelWidth({
    required String label,
    required TextStyle? labelStyle,
    required TextScaler scaler,
    double textWidthFactor = 1.0,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style:
            labelStyle?.copyWith(
              fontSize: (labelStyle.fontSize ?? 14) * textWidthFactor,
            ) ??
            TextStyle(fontSize: 14 * textWidthFactor),
      ),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  /// 可用宽度放不下「图标+文字」时，就只画图标。
  ///
  /// 判据是**严格大于**：刚好放得下时保留文字，因为文字才是这排 tab 的可达性
  /// （仅图标时靠 tooltip，触屏上没有 tooltip）。
  static bool shouldShowIconOnly({
    required double availableWidth,
    required List<String> labels,
    required TextStyle? labelStyle,
    required TextScaler scaler,
    double textWidthFactor = 1.0,
  }) {
    if (!availableWidth.isFinite) return false;
    return rowNaturalWidth(
          labels: labels,
          labelStyle: labelStyle,
          scaler: scaler,
          textWidthFactor: textWidthFactor,
        ) >
        availableWidth;
  }
}
