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

/// 只保留一套标题与关闭入口，展开前后共享同一份工具栏。
class _ReaderSettingsHeader extends StatelessWidget {
  const _ReaderSettingsHeader({
    required this.expanded,
    required this.onToggleExpanded,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.showDescriptions,
    required this.onToggleDescriptions,
  });
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final ValueChanged<double> onDragUpdate;
  final ValueChanged<double> onDragEnd;
  final bool showDescriptions;
  final VoidCallback onToggleDescriptions;

  @override
  Widget build(BuildContext context) => ActionBubbleRegion(
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      key: const ValueKey('reader-settings-drag-handle'),
      onVerticalDragUpdate: (details) => onDragUpdate(details.delta.dy),
      onVerticalDragEnd: (details) =>
          onDragEnd(-details.velocity.pixelsPerSecond.dy),
      onVerticalDragCancel: () => onDragEnd(0),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                t.reader.settings,
                style: context.theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ActionBubbleTarget(
              child: ElasticButton(
                child: IconButton(
                  tooltip: t.common.help,
                  isSelected: showDescriptions,
                  icon: const GlyphIcon(AppGlyphs.info, size: 20),
                  onPressed: onToggleDescriptions,
                ),
              ),
            ),
            ActionBubbleTarget(
              child: ElasticButton(
                child: IconButton(
                  key: const ValueKey('reader-settings-expand'),
                  tooltip: expanded ? t.common.back : t.reader.fullscreen,
                  icon: GlyphIcon(
                    expanded ? AppGlyphs.fullscreenExit : AppGlyphs.fullscreen,
                    size: 20,
                  ),
                  onPressed: onToggleExpanded,
                ),
              ),
            ),
            ActionBubbleTarget(
              child: ExpressiveIconButton(
                key: const ValueKey('reader-settings-close'),
                glyph: AppGlyphs.close,
                tooltip: t.common.close,
                size: 48,
                shape: ExpressiveButtonShape.circle,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
