part of '../reader_settings_sheet.dart';

/// 面板里的标签分组：按「用户到这排来找什么」分，不按代码里 section 的书写顺序分。
///
/// # 本漫设置沿用上游的独立 tab
///
/// 阅读页带 source/comicId 时增加上游的本漫 tab，全局入口隐藏它。
/// 标签继续由可滚动宿主承载，读写目标由上游 _PerComicScope 决定。
///
/// # 翻译排为什么可以整排不见
///
/// OCR 翻译在 Android / iOS 是**排除项而不是待办**（ADR-0018 §决定 6：本仓 `ort`
/// 的 android/linux 那两段没注册任何加速器 EP，识别模型还是 fp32 的 441 MB）。
/// 入口画出来却必然报错，比不画更坏，所以那一排在移动端整个不出现。
enum _ReaderSettingsTab { read, gesture, screen, picture, translate, perComic }

extension _ReaderSettingsTabLabel on _ReaderSettingsTab {
  Glyph get icon => switch (this) {
    _ReaderSettingsTab.read => AppGlyphs.openBook,
    _ReaderSettingsTab.gesture => AppGlyphs.touch,
    _ReaderSettingsTab.screen => AppGlyphs.gridPlus,
    _ReaderSettingsTab.picture => AppGlyphs.quality,
    _ReaderSettingsTab.translate => AppGlyphs.translate,
    _ReaderSettingsTab.perComic => AppGlyphs.openBook,
  };

  String get label => switch (this) {
    _ReaderSettingsTab.read => t.reader.tabRead,
    _ReaderSettingsTab.gesture => t.reader.tabGesture,
    _ReaderSettingsTab.screen => t.reader.tabScreen,
    _ReaderSettingsTab.picture => t.reader.tabPicture,
    _ReaderSettingsTab.translate => t.reader.tabTranslate,
    _ReaderSettingsTab.perComic => t.reader.perComicThisComic,
  };

  Widget body(_ReaderSettingsArgs args) => switch (this) {
    _ReaderSettingsTab.read => _ReaderSettingsReadTab(
      changePageIndex: args.changePageIndex,
      onLandscapeChanged: args.onLandscapeChanged,
      source: args.source,
      comicId: args.comicId,
    ),
    _ReaderSettingsTab.gesture => _ReaderSettingsGestureTab(
      isAndroidPhone: args.isAndroidPhone,
    ),
    _ReaderSettingsTab.screen => const _ReaderSettingsInfoTab(),
    _ReaderSettingsTab.picture => const _ReaderSettingsPictureTab(),
    _ReaderSettingsTab.translate => const _ReaderSettingsTranslateTab(),
    _ReaderSettingsTab.perComic => _ReaderSettingsPerComicTab(
      changePageIndex: args.changePageIndex,
      onLandscapeChanged: args.onLandscapeChanged,
      source: args.source,
      comicId: args.comicId,
      isAndroidPhone: args.isAndroidPhone,
    ),
  };
}

/// 这一次真正要画出来的几排。
List<_ReaderSettingsTab> _visibleReaderSettingsTabs({
  required bool translateAvailable,
  required bool perComicAvailable,
}) {
  return [
    for (final tab in _ReaderSettingsTab.values)
      if ((tab != _ReaderSettingsTab.translate || translateAvailable) &&
          (tab != _ReaderSettingsTab.perComic || perComicAvailable))
        tab,
  ];
}

/// 各排共用的入口参数。
///
/// 三排的时候是各自挑想要的字段传（阅读排四个、手势排一个），加到五排这条
/// 构造函数链就会变成「谁想得起什么就传什么」。收成一个对象：往下加一排
/// 只需要在 [_ReaderSettingsTabLabel.body] 里加一个 case。
class _ReaderSettingsArgs {
  const _ReaderSettingsArgs({
    required this.changePageIndex,
    required this.isAndroidPhone,
    this.onLandscapeChanged,
    this.source = '',
    this.comicId = '',
  });

  final ValueChanged<int> changePageIndex;
  final bool isAndroidPhone;
  final ValueChanged<bool>? onLandscapeChanged;
  final String source;
  final String comicId;

  /// 只有从阅读页进来（带图源与书号）才给「这一本单独设阅读模式」那档；
  /// 从全局设置进来时这两个是空串，那一档整块不画。
  bool get perComicAvailable =>
      source.trim().isNotEmpty && comicId.trim().isNotEmpty;
}

/// 面板头部：拖拽条 + MD3 图标文字标签栏 + 关闭。
class _ReaderSettingsHeader extends StatelessWidget {
  const _ReaderSettingsHeader({required this.tabs});

  final List<_ReaderSettingsTab> tabs;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.theme.colorScheme;
    // MD3 主标签栏的文字档位就是 titleSmall；不覆盖字重，交给主题默认值
    // （选中 primary / 未选中 onSurfaceVariant / 指示条 primary 3dp）。
    //
    // 量宽度要用**真正渲染那一份**样式：`Text`（inherit: true）是把自己的 style
    // 合进 DefaultTextStyle 的，而本仓主题是 `withConfiguredFonts(...)` 出来的 ——
    // 字体档位那条链可能只改字族、把 fontSize 留成 null。拿原始 token 直接量，
    // 在 fontSize 为 null 那一档上量到的是回落值，和画出来的宽度不是一回事，
    // 「什么时候收成仅图标」就会在某个没人注意的字号上开始说假话。
    final labelStyle = DefaultTextStyle.of(
      context,
    ).style.merge(context.theme.textTheme.titleSmall);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).maybePop(),
          child: Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 2),
          child: Row(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // 挤不下「图标+文字」时只留图标。判据是这一排实测的自然宽度，
                    // 不是写死的 dp：中文「阅读」两颗字和英文 "Interface" 差一倍多，
                    // 再加上用户开的字号缩放，任何固定数字都会在某一档说假话。
                    final iconOnly =
                        ReaderSettingsTabMetrics.shouldShowIconOnly(
                          availableWidth: constraints.maxWidth,
                          labels: [for (final tab in tabs) tab.label],
                          labelStyle: labelStyle,
                          scaler: MediaQuery.textScalerOf(context),
                        );
                    final controller = DefaultTabController.of(context);
                    final widths = [
                      for (final tab in tabs)
                        ReaderSettingsTabMetrics.tabNaturalWidth(
                          labelWidth: iconOnly
                              ? 0
                              : ReaderSettingsTabMetrics.measureLabelWidth(
                                  label: tab.label,
                                  labelStyle: labelStyle,
                                  scaler: MediaQuery.textScalerOf(context),
                                ),
                        ),
                    ];
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        height: iconOnly
                            ? ReaderSettingsTabMetrics.compactTabHeight
                            : ReaderSettingsTabMetrics.textAndIconTabHeight,
                        child: AnimatedBuilder(
                          animation: controller,
                          builder: (context, _) => SpringLensBar(
                            tabSizes: widths,
                            selectedIndex: controller.index,
                            onSelected: controller.animateTo,
                            tintColor: colorScheme.onSecondaryContainer,
                            tabs: [
                              for (final tab in tabs)
                                SpringLensTab(
                                  semanticLabel: tab.label,
                                  tooltip: iconOnly ? tab.label : null,
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        GlyphIcon(
                                          tab.icon,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                        if (!iconOnly) ...[
                                          const SizedBox(
                                            height: ReaderSettingsTabMetrics
                                                .iconMargin,
                                          ),
                                          Text(
                                            tab.label,
                                            style: labelStyle.copyWith(
                                              color:
                                                  colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              IconButton(
                tooltip: t.common.close,
                icon: const GlyphIcon(AppGlyphs.close, size: 20),
                style: IconButton.styleFrom(
                  backgroundColor: colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.4),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
