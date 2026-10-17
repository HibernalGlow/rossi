import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/navigation/navigation_dock.dart';
import 'package:zephyr/widgets/navigation/navigation_shape.dart';
import 'package:zephyr/widgets/spring_lens/elastic_press.dart';
import 'package:zephyr/widgets/popup_panel.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_gap_fill.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_gap_settings.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_gap_widgets.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_presentation.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_settings_controls.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_weight_selector.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_cover_tap_settings.dart';
import 'package:zephyr/i18n/strings.g.dart';

Future<LibraryPresentation?> showLibrarySizeSettings(
  BuildContext context,
  LibraryPresentation value,
  List<LibraryWeightSignal> signals, {
  LibraryPresentation defaults = const LibraryPresentation(),
  List<LibraryGapWidgetSpec> gapWidgets = const [],
  bool fileStats = false,
  bool hasReading = true,
  double? availableWidth,
  LibraryCoverTapAction? defaultCoverTapAction,
  Set<LibraryWeight> availableWeights = const {
    LibraryWeight.order,
    LibraryWeight.balanced,
    LibraryWeight.imageShape,
  },
}) => showPopupPanel<LibraryPresentation>(
  context: context,
  presentation: PopupPresentation.relative,
  anchorOf: () {
    final box = context.findRenderObject() as RenderBox?;
    return box == null || !box.hasSize
        ? Rect.zero
        : box.localToGlobal(Offset.zero) & box.size;
  },
  builder: (_) => _LibrarySizeSettings(
    value: value,
    signals: signals,
    defaults: defaults,
    gapWidgets: gapWidgets,
    fileStats: fileStats,
    hasReading: hasReading,
    availableWidth: availableWidth,
    defaultCoverTapAction: defaultCoverTapAction,
    availableWeights: availableWeights,
  ),
);

/// 展墙自定义面板的分组：按「用户来这排找什么」切，而不是按代码里的书写顺序。
///
/// 阅读设置给了一份可参照的答案：一屏只讲一件事，靠一排页签换场。这里同样
/// 把原先纵向平铺的尺寸 / 布局 / 空隙 / 封面向导 / 权重拆成五页，页签常驻
/// 顶部 —— 大多数调整在两次点击内到达，面板本身不再是一条长卷。
enum _WallTab { size, layout, components, cover, weights }

extension _WallTabX on _WallTab {
  Glyph get icon => switch (this) {
    _WallTab.size => AppGlyphs.resize,
    _WallTab.layout => AppGlyphs.layers,
    _WallTab.components => AppGlyphs.gradient,
    _WallTab.cover => AppGlyphs.touch,
    _WallTab.weights => AppGlyphs.sell,
  };

  String get label => switch (this) {
    _WallTab.size => t.workspace.wallTabSize,
    _WallTab.layout => t.workspace.wallTabLayout,
    _WallTab.components => t.workspace.wallTabComponents,
    _WallTab.cover => t.workspace.wallTabCover,
    _WallTab.weights => t.workspace.wallTabWeights,
  };
}

class _LibrarySizeSettings extends StatefulWidget {
  const _LibrarySizeSettings({
    required this.value,
    required this.signals,
    required this.defaults,
    this.gapWidgets = const [],
    required this.fileStats,
    required this.hasReading,
    this.availableWidth,
    this.defaultCoverTapAction,
    required this.availableWeights,
  });
  final LibraryPresentation value;
  final List<LibraryWeightSignal> signals;
  final LibraryPresentation defaults;
  final List<LibraryGapWidgetSpec> gapWidgets;
  final bool fileStats, hasReading;
  final double? availableWidth;
  final LibraryCoverTapAction? defaultCoverTapAction;
  final Set<LibraryWeight> availableWeights;
  @override
  State<_LibrarySizeSettings> createState() => _LibrarySizeSettingsState();
}

class _LibrarySizeSettingsState extends State<_LibrarySizeSettings> {
  late LibraryPresentation value = widget.value;

  /// 连续滚动下「当前在哪一页」由滚动位置决定，而不是由一次点击决定。
  /// 底部导航条只是这条长内容上的目录：点它滚过去，滚过去它也自己亮起来。
  late _WallTab _tab;

  final _scroll = ScrollController();
  final _viewportKey = GlobalKey();
  final _sectionKeys = {for (final tab in _WallTab.values) tab: GlobalKey()};

  /// 点击导航条触发的程序化滚动期间不反写 `_tab`，否则动画沿途每跨过
  /// 一个分段都会把选中项闪一下。
  bool _scrollSyncing = false;

  @override
  void initState() {
    super.initState();
    _tab = _tabs.first;
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  List<_WallTab> get _tabs => [
    _WallTab.size,
    _WallTab.layout,
    _WallTab.components,
    if (widget.defaultCoverTapAction != null) _WallTab.cover,
    if (widget.signals.isNotEmpty) _WallTab.weights,
  ];

  Widget slider(
    String label,
    double current,
    double min,
    double max,
    ValueChanged<double> change, {
    bool percent = false,
    String unit = '',
    bool dense = false,
  }) => LibrarySettingsSlider(
    label: label,
    value: current,
    min: min,
    max: max,
    percent: percent,
    unit: unit,
    dense: dense,
    onChanged: (v) => setState(() => change(v)),
  );

  Widget metric(
    String label,
    double current,
    double min,
    double max,
    ValueChanged<double> change, {
    bool percent = false,
    String unit = '',
  }) => LibrarySettingsMetricTile(
    child: slider(
      label,
      current,
      min,
      max,
      change,
      percent: percent,
      unit: unit,
      dense: true,
    ),
  );

  Widget toggle(String label, bool selected, ValueChanged<bool> change) =>
      LibrarySettingsToggle(
        label: label,
        selected: selected,
        onChanged: (v) => setState(() => change(v)),
      );

  void reset() {
    HapticFeedback.selectionClick();
    setState(
      () => value = widget.defaults.copyWith(
        signalWeights: {
          ...value.signalWeights,
          ...widget.defaults.signalWeights,
          for (final s in widget.signals) s.id: s.defaultWeight,
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopupPanel(
      maxWidth: 880,
      title: _header(context, theme),
      content: LayoutBuilder(
        builder: (context, constraints) {
          // 面板高度**整张固定**：连续滚动时卡片不缩放，底部导航条与动作条
          // 的落点也不动。内容在一整条滚动流里从尺寸一路排到权重，滚到哪一段
          // 底部导航就亮哪一段 —— 换页不需要另起一屏。
          final available = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : 640.0;
          return SizedBox(
            height: math.min(available, 560.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: KeyedSubtree(
                    key: _viewportKey,
                    child: SingleChildScrollView(
                      controller: _scroll,
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final (index, tab) in _tabs.indexed)
                            _section(context, tab, first: index == 0),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _bottomTabs(context),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _header(BuildContext context, ThemeData theme) => LayoutBuilder(
    builder: (context, constraints) {
      final compact =
          constraints.maxWidth < 260 ||
          MediaQuery.textScalerOf(context).scale(14) > 20;
      final actions = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: const ValueKey('wall-settings-reset'),
            tooltip: t.workspace.gapResetDefaults,
            onPressed: reset,
            icon: const GlyphIcon(AppGlyphs.reset, size: 20),
          ),
          IconButton(
            key: const ValueKey('wall-settings-cancel'),
            tooltip: t.common.cancel,
            onPressed: () => Navigator.pop(context),
            icon: const GlyphIcon(AppGlyphs.close, size: 20),
          ),
        ],
      );
      if (compact) {
        return Row(
          children: [
            Expanded(
              child: Text(
                t.workspace.displayWallCustom,
                style: theme.textTheme.titleSmall,
              ),
            ),
            actions,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.rectangle,
              borderRadius: const BorderRadius.all(Radius.circular(14)),
              color: theme.colorScheme.primaryContainer,
            ),
            child: GlyphIcon(
              AppGlyphs.gradient,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.workspace.displayWallCustom,
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 2),
                Text(
                  t.workspace.layoutFitsPanel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          actions,
        ],
      );
    },
  );

  /// 应用键：底部导航条右侧那颗悬浮图标。
  ///
  /// 取消与恢复默认收进标题栏右侧的两颗小图标 —— 一行三颗大按钮在手机和
  /// 桌面都白占一截高度，而「应用」才是这条面板的主出口。
  Widget _applyButton(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FloatingActionButton(
      key: const ValueKey('wall-settings-apply'),
      heroTag: null,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      tooltip: t.common.apply,
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      onPressed: () {
        HapticFeedback.lightImpact();
        Navigator.pop(context, value);
      },
      child: const GlyphIcon(AppGlyphs.check, size: 22),
    );
  }

  /// 底部导航条：与阅读设置同一套 `NavigationDock` 语言。
  ///
  /// 放在底部而不是顶部，是为了让**换页时它的位置永远不动**：面板高度固定，
  /// 内容在它上方切换；用户不必在每次换页后重新找那排键。
  Widget _bottomTabs(BuildContext context) {
    final tabs = _tabs;
    final selected = tabs.indexOf(_tab).clamp(0, tabs.length - 1);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Center(
        child: NavigationDock(
          key: const ValueKey('wall-settings-tabs'),
          destinations: [
            for (final tab in tabs)
              NavigationDockDestination(glyph: tab.icon, label: tab.label),
          ],
          selectedIndex: selected,
          trailing: _applyButton(context),
          onSelected: (index) {
            if (index < 0 || index >= tabs.length) return;
            _scrollTo(tabs[index]);
          },
        ),
      ),
    );
  }

  /// 一整段：小标题 + 该段内容。滚动流里每段都参与布局，底部导航只负责
  /// 当前段的高亮。
  Widget _section(BuildContext context, _WallTab tab, {required bool first}) {
    final theme = Theme.of(context);
    return Container(
      key: _sectionKeys[tab],
      padding: EdgeInsets.only(top: first ? 0 : 8, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!first)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Divider(
                height: 1,
                color: theme.colorScheme.outlineVariant.withValues(alpha: .2),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
            child: Row(
              children: [
                GlyphIcon(tab.icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(tab.label, style: theme.textTheme.titleSmall),
                ),
              ],
            ),
          ),
          _sectionBody(context, tab),
        ],
      ),
    );
  }

  Widget _sectionBody(BuildContext context, _WallTab tab) => switch (tab) {
    _WallTab.size => _sizeTab(context),
    _WallTab.layout => _layoutTab(context),
    _WallTab.components => _componentsTab(context),
    _WallTab.cover => _coverTab(),
    _WallTab.weights => _weightsTab(),
  };

  /// 导航条点按：滚到那一段的顶部；期间不外写选中项。
  void _scrollTo(_WallTab tab) {
    if (tab == _tab) return;
    HapticFeedback.selectionClick();
    final target = _offsetOf(tab);
    setState(() => _tab = tab);
    if (target == null || !_scroll.hasClients) return;
    _scrollSyncing = true;
    _scroll
        .animateTo(
          target,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() {
          _scrollSyncing = false;
          _onScroll();
        });
  }

  /// 滚动时按「哪一段的标题已经越过视口顶部」决定当前段。
  ///
  /// 分段高度由真实的布局决定，所以这里现量 `RenderBox` 而不是预算偏移；
  /// 换字号、换宽度后仍然成立。
  void _onScroll() {
    if (!mounted || _scrollSyncing || !_scroll.hasClients) return;
    final next = _sectionAt(_scroll.offset);
    if (next != _tab) setState(() => _tab = next);
  }

  _WallTab _sectionAt(double offset) {
    final viewport =
        _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (viewport == null) return _tab;
    final viewportTop = viewport.localToGlobal(Offset.zero).dy;
    var current = _tabs.first;
    for (final tab in _tabs) {
      final box =
          _sectionKeys[tab]!.currentContext?.findRenderObject() as RenderBox?;
      if (box == null) continue;
      final top = box.localToGlobal(Offset.zero).dy - viewportTop + offset;
      if (top <= offset + 16) {
        current = tab;
      } else {
        break;
      }
    }
    return current;
  }

  double? _offsetOf(_WallTab tab) {
    final viewport =
        _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    final box =
        _sectionKeys[tab]!.currentContext?.findRenderObject() as RenderBox?;
    if (viewport == null || box == null) return null;
    final delta =
        box.localToGlobal(Offset.zero).dy -
        viewport.localToGlobal(Offset.zero).dy;
    return (_scroll.offset + delta).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
  }

  Widget _sizeTab(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      if (widget.availableWidth != null) _densityChoices(context),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: LibrarySettingsMetricGrid(
          children: [
            metric(
              t.workspace.cardWidth,
              value.cardWidth,
              80,
              420,
              (v) => value = value.copyWith(cardWidth: v),
              unit: ' dp',
            ),
            metric(
              t.workspace.cardHeight,
              value.cardHeight,
              180,
              600,
              (v) => value = value.copyWith(cardHeight: v),
              unit: ' dp',
            ),
            metric(
              t.workspace.cardSpacing,
              value.gap,
              4,
              32,
              (v) => value = value.copyWith(gap: v),
              unit: ' dp',
            ),
            metric(
              t.workspace.imageSize,
              value.imageScale,
              .5,
              1,
              (v) => value = value.copyWith(imageScale: v),
              percent: true,
            ),
            metric(
              t.workspace.sizeCompare,
              value.emphasis,
              0,
              1,
              (v) => value = value.copyWith(emphasis: v),
              percent: true,
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
        child: Text(
          t.workspace.cardWidthAutoColumns,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    ],
  );

  Widget _layoutTab(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            toggle(
              t.workspace.displayWall,
              value.editorial,
              (v) => value = value.copyWith(editorial: v),
            ),
            if (widget.hasReading)
              toggle(
                t.workspace.heroVisual,
                value.hero,
                (v) => value = value.copyWith(hero: v),
              ),
            toggle(
              t.workspace.contentSections,
              value.sections,
              (v) => value = value.copyWith(sections: v),
            ),
            toggle(
              t.workspace.asymmetric,
              value.asymmetric,
              (v) => value = value.copyWith(asymmetric: v),
            ),
            if (widget.fileStats)
              toggle(
                t.workspace.includeSubdirStats,
                value.recursiveStats,
                (v) => value = value.copyWith(recursiveStats: v),
              ),
          ],
        ),
      ),
      LibraryWeightSelector(
        value: value.weight,
        available: widget.availableWeights,
        onChanged: (w) => setState(() => value = value.copyWith(weight: w)),
      ),
    ],
  );

  Widget _componentsTab(BuildContext context) => LibraryGapSettingsBody(
    value: value,
    widgets: widget.gapWidgets.isEmpty
        ? defaultLibraryGapWidgets()
        : widget.gapWidgets,
    onChanged: (next) => setState(() => value = next),
  );

  Widget _coverTab() {
    final action = value.coverTapAction ?? widget.defaultCoverTapAction;
    if (action == null) return const SizedBox.shrink();
    return LibraryCoverTapSettings(
      value: action,
      onChanged: (next) =>
          setState(() => value = value.copyWith(coverTapAction: next)),
    );
  }

  Widget _weightsTab() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      LibrarySettingsGroup(
        title: t.workspace.favouriteTagWeight,
        glyph: AppGlyphs.sell,
        description: t.workspace.weightBiggerWins,
        children: [
          for (final signal in widget.signals)
            slider(
              signal.label,
              value.signalWeights[signal.id] ?? signal.defaultWeight,
              0,
              10,
              (v) => value = value.copyWith(
                signalWeights: {...value.signalWeights, signal.id: v},
              ),
            ),
        ],
      ),
    ],
  );

  Widget _densityChoices(BuildContext context) {
    final width = widget.availableWidth!;
    final columns = libraryCanvasColumns(width, value);
    final choices = [2, 3, 4, 5, 6].where((count) {
      final target = libraryCardWidthForColumns(width, count, value.gap);
      return target >= 80 && target <= 420;
    });
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.workspace.columnsPerRow(columns: columns),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            t.workspace.normalOneWideTwoSlots,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final count in choices)
                ElasticButton(
                  enabled: !MediaQuery.disableAnimationsOf(context),
                  child: ChoiceChip(
                    label: Text(t.workspace.slotCount(count: count)),
                    selected: columns == count,
                    side: BorderSide.none,
                    shape: columns == count ? AppShape.xl : AppShape.md,
                    selectedColor: Theme.of(
                      context,
                    ).colorScheme.secondaryContainer,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHigh,
                    onSelected: (_) {
                      HapticFeedback.selectionClick();
                      setState(
                        () => value = value.copyWith(
                          cardWidth: libraryCardWidthForColumns(
                            width,
                            count,
                            value.gap,
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
