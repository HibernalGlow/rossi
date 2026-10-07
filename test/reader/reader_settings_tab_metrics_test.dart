import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/page/comic_read/widgets/settings/reader_settings_tab_metrics.dart';

/// 窄屏只留图标那条判据的单测。
///
/// 为什么必须有单测而不是只看界面：`flutter test` 用的是替代字体，每个字形都是
/// 正方形，量出来的宽度和真机字体不是一个量级 —— 所以**不能**在这里断言
/// 「360dp 一定会收成图标」。这里断言的是判据本身：同一份标签，
/// 可用宽度刚好放得下时必须留在「图标+文字」，只差 1dp 放不下时必须翻成仅图标。
/// 那两个数字由同一个测量函数算出来，与字体无关，所以两边都锁得住。
void main() {
  const style = TextStyle(fontSize: 20);
  const labels = <String>[
    'Reading',
    'Gestures',
    'Interface',
    'Picture',
    'Translate',
  ];

  // 一排的自然宽度：5 × (max(24, 文字宽) + 16 + 16)。
  // Ahem 下 7 个字符 = 140，所以那一排是 172 起跳。
  double naturalWidth() => ReaderSettingsTabMetrics.rowNaturalWidth(
    labels: labels,
    labelStyle: style,
    scaler: TextScaler.noScaling,
  );

  test('natural width is what the spec constants add up to', () {
    expect(
      ReaderSettingsTabMetrics.labelHorizontalPadding,
      16,
      reason: 'material_ui kTabLabelPadding：改了它这段判据就飘了',
    );
    expect(ReaderSettingsTabMetrics.textAndIconTabHeight, 72);
    expect(ReaderSettingsTabMetrics.compactTabHeight, 46);
    expect(ReaderSettingsTabMetrics.iconSize, 24);

    // 替代字体（Ahem）每个字形都是 fontSize 见方的方块，所以文字宽 = 字符数 × 20。
    final expected = labels.fold<double>(
      0,
      (sum, label) =>
          sum +
          ReaderSettingsTabMetrics.tabNaturalWidth(
            labelWidth: label.length * 20.0,
          ),
    );
    expect(naturalWidth(), expected);
  });

  test('flips to icon-only exactly where the row stops fitting', () {
    bool iconOnly(double width) => ReaderSettingsTabMetrics.shouldShowIconOnly(
      availableWidth: width,
      labels: labels,
      labelStyle: style,
      scaler: TextScaler.noScaling,
    );

    // 刚好放得下：不翻。翻了就是白丢文字（仅图标在触屏上没有 tooltip）。
    expect(iconOnly(naturalWidth()), isFalse, reason: '刚好放得下必须留在图标+文字');
    // 差 1dp：必须翻。不翻这一档就会溢出成横滚，而横滚的 tab 栏没人知道还能滑。
    expect(iconOnly(naturalWidth() - 1), isTrue, reason: '放不下必须收成仅图标');
  });

  test('bigger text scale raises the bar, not the label style alone', () {
    final iconOnlyAt2x = ReaderSettingsTabMetrics.shouldShowIconOnly(
      availableWidth: naturalWidth(),
      labels: labels,
      labelStyle: style,
      scaler: const TextScaler.linear(2.0),
    );
    expect(iconOnlyAt2x, isTrue, reason: '字号放大后同一排更宽，同一可用宽度下应转成仅图标');
  });

  test('infinite available width never collapses to icons', () {
    expect(
      ReaderSettingsTabMetrics.shouldShowIconOnly(
        availableWidth: double.infinity,
        labels: labels,
        labelStyle: style,
        scaler: TextScaler.noScaling,
      ),
      isFalse,
    );
  });
}
