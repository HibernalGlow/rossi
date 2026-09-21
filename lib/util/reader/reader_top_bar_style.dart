// 阅读器顶栏的材质规格：用户设置 → 可直接渲染的一层。
//
// 这里刻意只做**纯逻辑**（玻璃 ⇄ 蒙层二选一 + 不透明度钳制 + 阴影档），
// 不引用任何 widget，于是判据可以在 `flutter test` 里直接断言，不需要把界面跑起来。
//
// 为什么要一个「透明」档：现在的顶栏是**最实的一档**液态玻璃（`thick`），
// 压在漫画上等于把画面顶端那一整块盖住。JHenTai 的阅读页走的是另一条路 ——
// `readPageMenuColor = Colors.black.withValues(alpha: 0.85)`：一层半透明蒙层，
// 画面透出来一点，但文字仍然读得清。
//
// 蒙层颜色取主题的 `surface`（而不是写死黑）：这样 `onSurface` 对它的对比度
// 天然成立，**顶栏里几十个文字 / 图标一个都不用改色**，浅色主题也不会得到
// 「白底 + 浅色字」。默认档是玻璃，没进过设置页的用户零感知。

import 'package:flutter/widgets.dart';
import 'package:zephyr/config/global/global_setting.dart';

/// 各字段的合法区间。
///
/// 设置可能来自「云端同步覆盖」或旧版本写入，所以**读的时候一律再夹一次**，
/// 不能假定它一定落在滑块范围内。
abstract final class ReaderTopBarStyleLimits {
  static const int minOpacityPercent = 0;
  static const int maxOpacityPercent = 100;

  /// 不给用户挑的时候用它：与 JHenTai 的 `readPageMenuColor`（黑 85%）同一档。
  static const int defaultOpacityPercent = 85;

  /// 玻璃档的外阴影缩放。顶栏贴着屏幕顶边、体量又小，全套阴影会重得离谱。
  static const double glassShadowScale = 0.4;

  /// 透明档不给阴影 —— 没有材质还留着那圈阴影，看着像「玻璃没画完」。
  static const double transparentShadowScale = 0.0;

  /// 主行高度（逻辑像素）。
  static const double rowHeight = 48;

  /// 「版式组可以带文字标签」的下限宽度。
  ///
  /// 阈值不是拍脑袋，是按**书名的最低生存宽度**定的：宽档那一串固定成本
  /// （返回 + 视图三项 + 条漫胶囊 + 单双页 + 方向 + 旋转 + 下载 + 超分芯片 +
  /// 滚屏 + 全屏 + 钉住 + 设置 + 更多，其中带文字的三颗各要 60~90px）实测约 700px，
  /// 再低书名就读不出来了（实测固定成本约 810px，1060 那一档书名剩 250px）。判据在
  /// `test/comic_read/reader_top_bar_layout_test.dart` 的「书名不被挤没」那一组：
  /// 越过这条线书名若剩不下 240px，就是这一档的阈值给低了。
  static const double labeledToolbarMinWidth = 1060;

  /// 「版式组摊开成独立控件」的下限宽度；再窄就换成一颗循环切换按钮。
  ///
  /// 中档比宽档省掉「文字标签 + 钉住 + 全屏」，固定成本约 620px，
  /// 所以这条线压在 880。前两版分别写的是 720 与 800，都被书名预算那条判据
  /// 抓出来过：720 时书名只剩 97px，800 时只剩 177px —— 都比窄档还窄，
  /// 等于「不溢出了，但看不见在读什么」。
  static const double expandedLayoutMinWidth = 880;
}

/// 顶栏主行按可用宽度分的那三档。
///
/// 分档只看**可用宽度**，不看设备类型：桌面端可以把窗口拖到 400 宽，
/// 平板可以横过来给阅读器 900 宽，硬件类别在这两头都会骗人。
enum ReaderToolbarTier {
  /// 宽：所有组平铺，开关芯片带文字。
  wide,

  /// 中：组还在，但芯片收成图标。
  medium,

  /// 窄：版式组并成一颗循环按钮，低频的窗口控件收进「更多」菜单。
  narrow;

  /// 自动滚屏那颗开关是否还留在主行上。
  ///
  /// 窄档不让位就放不下超分芯片（用户点名要留的那一颗）—— 按同一句口径，
  /// 滚屏收进「更多」，超分留在第一行。
  bool get keepsAutoScrollInline => this != ReaderToolbarTier.narrow;

  /// 版式组是否摊开成「条漫胶囊 + 单双页 + 方向」这一排独立控件。
  bool get expandsLayoutGroup => this != ReaderToolbarTier.narrow;

  /// 开关芯片是否带文字（只有宽档带）。
  bool get showsChipLabels => this == ReaderToolbarTier.wide;

  /// 三块面板的入口（视图组）与下载是否还留在主行上。
  ///
  /// 窄档收进末尾那颗「更多」菜单 —— 不是砍掉，是换个入口。
  bool get keepsViewControlsInline => this != ReaderToolbarTier.narrow;

  /// 「钉住 / 全屏」这两颗窗口控件是否还留在主行上。
  ///
  /// 只有宽档留：它们成对出现、各自 40px，是主行上最贵也最低频的一节。
  bool get keepsWindowControlsInline => this == ReaderToolbarTier.wide;
}

/// 由可用宽度决定主行走哪一档。
ReaderToolbarTier resolveReaderToolbarTier(double availableWidth) {
  if (availableWidth >= ReaderTopBarStyleLimits.labeledToolbarMinWidth) {
    return ReaderToolbarTier.wide;
  }
  if (availableWidth >= ReaderTopBarStyleLimits.expandedLayoutMinWidth) {
    return ReaderToolbarTier.medium;
  }
  return ReaderToolbarTier.narrow;
}

/// 一层顶栏的材质规格。
@immutable
class ReaderTopBarSpec {
  const ReaderTopBarSpec({
    required this.liquidGlass,
    required this.scrim,
    required this.shadowScale,
  });

  /// true = 走液态玻璃（改造前的样子）；false = 透明档。
  final bool liquidGlass;

  /// 透明档下的蒙层颜色；玻璃档为 `null`。
  final Color? scrim;

  /// 外阴影缩放。
  final double shadowScale;

  bool get isTransparent => !liquidGlass;
}

/// 把不透明度百分比夹进合法区间（越界值直接抛给 `Slider` 会炸）。
int clampReaderTopBarOpacityPercent(int percent) => percent.clamp(
  ReaderTopBarStyleLimits.minOpacityPercent,
  ReaderTopBarStyleLimits.maxOpacityPercent,
);

/// 把用户设置解析成渲染规格。
///
/// [surface] 是当前主题的 `colorScheme.surface` —— 蒙层由它加透明度得到。
ReaderTopBarSpec resolveReaderTopBarSpec(
  ReadSettingState setting, {
  required Color surface,
}) {
  if (!setting.transparentTopBar) {
    return const ReaderTopBarSpec(
      liquidGlass: true,
      scrim: null,
      shadowScale: ReaderTopBarStyleLimits.glassShadowScale,
    );
  }

  final percent = clampReaderTopBarOpacityPercent(
    setting.topBarScrimOpacityPercent,
  );
  return ReaderTopBarSpec(
    liquidGlass: false,
    scrim: surface.withValues(alpha: percent / 100),
    shadowScale: ReaderTopBarStyleLimits.transparentShadowScale,
  );
}
